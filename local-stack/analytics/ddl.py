#!/usr/bin/env python3
"""Exercise pause + explicit resnapshot for DDL on a disposable schema copy."""
import hashlib
import json
import os
from pathlib import Path
import sys
import time

from control import api, ch, create_peer, pg, wait_for

SOURCE = 'analytics_ddl_probe'
PUBLICATION = 'analytics_ddl_probe'


def state(name, target):
    api('/v1/mirrors/state_change', {'flowJobName': name,
        'requestedFlowState': target, 'skipDestinationDrop': True})
    if target == 'STATUS_PAUSED':
        wait_for(lambda: api('/v1/mirrors/status', {'flowJobName': name,
            'excludeBatches': True, 'excludeSnapshotStatus': True}).get('currentFlowState') == target,
            name + ' paused', 180)
    else:
        wait_for(lambda: pg('peerdb_catalog', f"SELECT count(*) FROM flows WHERE name='{name}'") == '0',
                 name + ' terminated with raw evidence retained', 180)
        wait_for(lambda: pg('order', f"SELECT count(*) FROM pg_replication_slots WHERE slot_name='peerflow_slot_{name}'") == '0',
                 name + ' slot removed deliberately', 180)


def copy(version, columns):
    name = 'analytics_ddl_v' + str(version)
    table = 'ddl_v' + str(version)
    actual = pg('order', f"SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name='{SOURCE}'").splitlines()
    pg('order', f'ALTER PUBLICATION {PUBLICATION} SET TABLE public.{SOURCE} ({",".join(columns)})')
    result = api('/v1/flows/cdc/create', {'connectionConfigs': {
        'flowJobName': name, 'sourceName': 'ddl_source', 'destinationName': 'commerce',
        'publicationName': PUBLICATION, 'doInitialSnapshot': True,
        'snapshotMaxParallelWorkers': 1, 'snapshotNumTablesInParallel': 1,
        'snapshotNumRowsPerPartition': 10000, 'maxBatchSize': 1000, 'idleTimeoutSeconds': 10,
        'softDeleteColName': '_peerdb_is_deleted', 'syncedAtColName': '_peerdb_synced_at',
        'env': {'PEERDB_NULLABLE': 'true', 'PEERDB_CLICKHOUSE_SKIP_STAGING_CLEANUP': 'true'},
        'tableMappings': [{'sourceTableIdentifier': 'public.' + SOURCE,
            'destinationTableIdentifier': table, 'exclude': [c for c in actual if c not in columns]}]}})
    if not result.get('workflowId'):
        raise RuntimeError('DDL mirror creation did not return a workflow')
    wait_for(lambda: ch(f'SELECT count() FROM commerce.{table}') == '1', name + ' snapshot', 300)
    actual_target = set(ch(f"SELECT name FROM system.columns WHERE database='commerce' AND table='{table}'").splitlines())
    if actual_target != set(columns) | {'_peerdb_version', '_peerdb_is_deleted', '_peerdb_synced_at'}:
        raise RuntimeError('Resnapshot produced an unexpected schema')
    if ch(f'SELECT id FROM commerce.{table}') != '-1':
        raise RuntimeError('Resnapshot changed the source identity')
    if 'product_name' in columns and ch(f'SELECT product_name FROM commerce.{table}') != 'Before DDL':
        raise RuntimeError('Type migration changed the source value')
    if 'RFC0030_FORBIDDEN_PII' in ch(f'SELECT * FROM commerce.{table} FORMAT JSONEachRow'):
        raise RuntimeError('Resnapshot leaked the excluded fixture')
    wait_for(lambda: pg('order', f"SELECT count(*) FROM pg_replication_slots WHERE slot_name='peerflow_slot_{name}'") == '1',
             name + ' source slot', 180)
    state(name, 'STATUS_PAUSED')
    # The workflow consumes TERMINATING; TERMINATED is an observed end state.
    state(name, 'STATUS_TERMINATING')


def main():
    rows = []
    try:
        if pg('order', f"SELECT to_regclass('public.{SOURCE}') IS NOT NULL") != 'f':
            raise RuntimeError('DDL evidence already exists; use a fresh disposable project for a repeat')
        pg('order', f"""CREATE TABLE {SOURCE} AS SELECT id,product_name FROM order_items WITH NO DATA;
ALTER TABLE {SOURCE} ADD PRIMARY KEY(id);
INSERT INTO {SOURCE} VALUES (-1,'Before DDL');
CREATE ROLE peerdb_ddl LOGIN REPLICATION PASSWORD 'peerdb-ddl-local' NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
GRANT CONNECT ON DATABASE "order" TO peerdb_ddl;
GRANT USAGE ON SCHEMA public TO peerdb_ddl;
GRANT SELECT ON {SOURCE} TO peerdb_ddl;
CREATE PUBLICATION {PUBLICATION};""")
        create_peer('ddl_source', 'POSTGRES', {'host': 'postgres', 'port': 5432,
            'user': 'peerdb_ddl', 'password': 'peerdb-ddl-local', 'database': 'order', 'disableTls': True})
        copy(1, ['id', 'product_name'])
        rows.append({'gate': 'baseline schema copy, pause and deliberate slot removal', 'result': 'PASS'})
        # PostgreSQL rejects type changes while the column belongs to a publication.
        pg('order', f'ALTER PUBLICATION {PUBLICATION} SET TABLE {SOURCE} (id)')
        pg('order', f"ALTER TABLE {SOURCE} ADD COLUMN pii_note text DEFAULT 'RFC0030_FORBIDDEN_PII'; ALTER TABLE {SOURCE} ALTER COLUMN product_name TYPE text;")
        copy(2, ['id', 'product_name'])
        rows.append({'gate': 'add excluded column and change varchar to text, then resnapshot', 'result': 'PASS'})
        # The publication dependency is explicitly replaced before dropping the mapped column.
        pg('order', f'ALTER PUBLICATION {PUBLICATION} SET TABLE {SOURCE} (id); ALTER TABLE {SOURCE} DROP COLUMN product_name;')
        copy(3, ['id'])
        rows.append({'gate': 'drop mapped column, update contract and resnapshot', 'result': 'PASS'})
    except Exception as error:
        rows.append({'gate': 'DDL qualification', 'result': 'FAIL', 'reason': str(error)[:500]})
    out = Path(os.environ.get('ANALYTICS_EVIDENCE_DIR', '/tmp/rfc0030-evidence'))
    out.mkdir(parents=True, exist_ok=True)
    evidence = {'scope': 'Compose copied schema; explicit pause/termination/new snapshot, not automatic propagation or CNPG',
                'input_sha256': {name: hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest()
                                 for name in ['ddl.py', 'control.py']},
                'timestamp_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), 'rows': rows}
    (out / 'ddl.json').write_text(json.dumps(evidence, indent=2) + '\n')
    (out / 'ddl.md').write_text('| Gate | Result |\n|---|---|\n' + ''.join(f"| {r['gate']} | {r['result']} |\n" for r in rows))
    for row in rows:
        print(row['gate'], row['result'])
    return 0 if all(row['result'] == 'PASS' for row in rows) else 1


if __name__ == '__main__':
    sys.exit(main())
