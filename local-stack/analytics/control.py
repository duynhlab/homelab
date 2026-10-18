#!/usr/bin/env python3
"""Disposable RFC-0030 bootstrap and qualification; stdlib only."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
import hashlib
import json
import math
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import threading
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
PROJECT = 'rfc0030-phase0'
API = 'http://127.0.0.1:8113'
ALLOW = json.loads((HERE / 'allowlist.json').read_text())
for tables in ALLOW.values():
    tables['analytics_cdc_heartbeat'] = ['id', 'emitted_at']


def compose(*args, sql=None, timeout=180):
    binary = ['docker-compose'] if shutil.which('docker-compose') else ['docker', 'compose']
    cmd = binary + ['-p', PROJECT, '-f', str(ROOT / 'local-stack/compose.yaml'),
                    '-f', str(ROOT / 'local-stack/compose.analytics.yaml')] + list(args)
    r = subprocess.run(cmd, input=sql, text=True, capture_output=True, timeout=timeout)
    if r.returncode:
        # Commands can carry fixture credentials: never echo the argv or payload.
        raise RuntimeError('Compose operation failed: ' + r.stderr[-1500:])
    return r.stdout.strip()


def pg(db, sql, user='postgres'):
    return compose('exec', '-T', 'postgres', 'psql', '-XAt', '-v', 'ON_ERROR_STOP=1',
                   '-U', user, '-d', db, sql=sql)


def ch(sql):
    return compose('exec', '-T', 'clickhouse', 'clickhouse-client', '--user', 'default',
                   '--password', 'otel', '--multiquery', sql=sql)


def api(path, payload=None):
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(API + path, data=data, headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)


def wait_for(check, label, seconds=180):
    deadline = time.monotonic() + seconds
    last = None
    while time.monotonic() < deadline:
        try:
            if check():
                return
        except (RuntimeError, ValueError, OSError) as error:
            last = type(error).__name__
        time.sleep(2)
    raise RuntimeError(f'{label}: deadline exceeded ({last or "condition false"})')


def quote(value):
    return "'" + value.replace("'", "''") + "'"


def source_mappings():
    """Inspect all source contracts before changing grants or publications."""
    mappings = {}
    for db, tables in ALLOW.items():
        maps = []
        for table, columns in tables.items():
            actual = pg(db, f"SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name='{table}' ORDER BY ordinal_position").splitlines()
            if table == 'analytics_cdc_heartbeat' and not actual:
                # Bootstrap owns this fixed schema and creates it after preflight.
                actual, pk = ['id', 'emitted_at'], ['id']
            else:
                pk = pg(db, f"SELECT a.attname FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='public.{table}'::regclass AND i.indisprimary").splitlines()
            if not set(columns) <= set(actual):
                raise RuntimeError(f'{db}.{table}: allowlist differs from source migrations')
            if not pk or not set(pk) <= set(columns):
                raise RuntimeError(f'{db}.{table}: missing replica identity in allowlist')
            maps.append({'sourceTableIdentifier': 'public.' + table,
                         'destinationTableIdentifier': db + '_' + table,
                         'exclude': [c for c in actual if c not in columns]})
        mappings[db] = maps
    return mappings


def source_setup():
    for db, tables in ALLOW.items():
        role = 'peerdb_' + db
        pg(db, f"""
DO $$ BEGIN
 IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='{role}') THEN
  CREATE ROLE {role} LOGIN REPLICATION PASSWORD '{role}-local'
   NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
 END IF;
END $$;
GRANT CONNECT ON DATABASE "{db}" TO {role}, analytics_heartbeat;
GRANT USAGE ON SCHEMA public TO {role}, analytics_heartbeat;
CREATE TABLE IF NOT EXISTS analytics_cdc_heartbeat (
 id SMALLINT PRIMARY KEY CHECK (id=1), emitted_at TIMESTAMPTZ NOT NULL);
INSERT INTO analytics_cdc_heartbeat VALUES (1,clock_timestamp())
 ON CONFLICT (id) DO NOTHING;
GRANT SELECT,INSERT,UPDATE ON analytics_cdc_heartbeat TO analytics_heartbeat;
""")
        targets = []
        for table, columns in tables.items():
            pg(db, f'GRANT SELECT ON public.{table} TO {role}')
            targets.append(f'public.{table} ({",".join(columns)})')
        pub = 'analytics_' + db
        if pg(db, f"SELECT count(*) FROM pg_publication WHERE pubname='{pub}'") == '0':
            pg(db, f'CREATE PUBLICATION {pub}')
        pg(db, f'ALTER PUBLICATION {pub} SET TABLE ' + ','.join(targets))
        command = 'INSERT INTO public.analytics_cdc_heartbeat VALUES (1,clock_timestamp()) ON CONFLICT (id) DO UPDATE SET emitted_at=EXCLUDED.emitted_at'
        pg('postgres', f"SELECT cron.schedule_in_database('analytics-{db}','30 seconds',{quote(command)},'{db}','analytics_heartbeat')")
    pg('postgres', """SET ROLE analytics_heartbeat;
SELECT cron.schedule('analytics-history-cleanup','0 3 * * *',
 $$DELETE FROM cron.job_run_details WHERE end_time < now()-interval '7 days'$$);
RESET ROLE;""")


def fixtures():
    pg('order', """INSERT INTO orders(id,user_id,subtotal,shipping,total,status)
 VALUES (-30000,'RFC0030_FORBIDDEN_PII',1000,0,1000,'pending') ON CONFLICT DO NOTHING;
INSERT INTO order_items(id,order_id,product_id,product_name,quantity,price,subtotal)
 VALUES (-30000,-30000,1,'Phase 0 product',1,1000,1000) ON CONFLICT DO NOTHING;""")
    pg('checkout', """INSERT INTO checkout_sessions(id,user_id,status,currency,expires_at)
 VALUES ('00300000-0000-0000-0000-000000000001','RFC0030_FORBIDDEN_PII','open','USD',now()+interval '1 day') ON CONFLICT DO NOTHING;""")
    pg('payment', """INSERT INTO payments(id,user_id,order_id,amount_minor,currency,payment_method)
 OVERRIDING SYSTEM VALUE VALUES (-30000,'RFC0030_FORBIDDEN_PII',-30000,1000,'USD','RFC0030_FORBIDDEN_PII') ON CONFLICT DO NOTHING;
INSERT INTO ledger_transactions(id,payment_id,kind,external_ref) OVERRIDING SYSTEM VALUE
 VALUES (-30000,-30000,'capture','RFC0030_FORBIDDEN_PII') ON CONFLICT DO NOTHING;
INSERT INTO ledger_entries(id,transaction_id,account_id,direction,amount_minor) OVERRIDING SYSTEM VALUE
 VALUES (-30000,-30000,(SELECT id FROM ledger_accounts WHERE name='merchant_revenue'),'credit',1000),
 (-30001,-30000,(SELECT id FROM ledger_accounts WHERE name='customer_funds'),'debit',1000) ON CONFLICT DO NOTHING;""")


def create_peer(name, kind, config):
    if pg('peerdb_catalog', f'SELECT count(*) FROM peers WHERE name={quote(name)}') != '0':
        return
    key = 'postgresConfig' if kind == 'POSTGRES' else 'clickhouseConfig'
    response = api('/v1/peers/create', {'peer': {'name': name, 'type': kind, key: config}})
    if response.get('status') not in ('CREATED', 1):
        raise RuntimeError('Peer validation failed for ' + name)


@contextmanager
def concurrent_snapshot_writes(enabled):
    if not enabled:
        yield
        return
    stop = threading.Event()
    def writer():
        count = 0
        while not stop.is_set():
            pg('order', 'UPDATE orders SET version=version+1,updated_at=clock_timestamp() WHERE id=-30000')
            count += 1
            stop.wait(0.25)
        return count
    with ThreadPoolExecutor(max_workers=1) as pool:
        future = pool.submit(writer)
        try:
            yield
        finally:
            stop.set()
            count = future.result(timeout=190)
            pg('postgres', 'CREATE TABLE IF NOT EXISTS analytics_snapshot_evidence (source text PRIMARY KEY, concurrent_writes int NOT NULL)')
            pg('postgres', f"INSERT INTO analytics_snapshot_evidence VALUES ('order',{count}) ON CONFLICT(source) DO UPDATE SET concurrent_writes=EXCLUDED.concurrent_writes")


def bootstrap():
    def api_ready():
        api('/v1/mirrors/list')
        return True
    wait_for(api_ready, 'flow API')
    mappings = source_mappings()
    contract = hashlib.sha256(json.dumps({'maps': mappings, 'nullable': True,
        'peerdb': 'v0.37.5', 'retained_snapshot_staging': True,
        'resource_naming': 'analytics-service-v1'}, sort_keys=True).encode()).hexdigest()
    pg('postgres', 'CREATE TABLE IF NOT EXISTS analytics_phase0_contract (id int PRIMARY KEY CHECK(id=1), fingerprint text NOT NULL)')
    old = pg('postgres', 'SELECT fingerprint FROM analytics_phase0_contract WHERE id=1')
    if old and old != contract:
        raise RuntimeError('Source/mirror contract changed: use a fresh disposable project; do not silently reuse mirrors')
    if not old and pg('peerdb_catalog', 'SELECT count(*) FROM flows') != '0':
        raise RuntimeError('Existing mirrors lack this qualification contract: reset the disposable project')
    pg('postgres', f"INSERT INTO analytics_phase0_contract VALUES (1,'{contract}') ON CONFLICT DO NOTHING")
    source_setup()
    fixtures()
    ch("""CREATE DATABASE IF NOT EXISTS analytics;
CREATE USER IF NOT EXISTS analytics_ingest IDENTIFIED WITH sha256_password BY 'analytics-ingest-local';
GRANT ALL ON analytics.* TO analytics_ingest;
GRANT CREATE TEMPORARY TABLE, S3 ON *.* TO analytics_ingest;
CREATE USER IF NOT EXISTS analytics_reader IDENTIFIED WITH sha256_password BY 'analytics-reader-local';""")
    create_peer('analytics_service', 'CLICKHOUSE', {'host': 'clickhouse', 'port': 9000,
        'user': 'analytics_ingest', 'password': 'analytics-ingest-local', 'database': 'analytics',
        'disableTls': True, 's3Path': 's3://analytics-service-cdc', 'accessKeyId': 'analytics-service-cdc',
        'secretAccessKey': 'analytics-service-cdc-local-secret', 'region': 'us-east-1',
        'endpoint': 'http://analytics-service-cdc-storage:9000'})
    for db, maps in mappings.items():
        create_peer(db, 'POSTGRES', {'host': 'postgres', 'port': 5432,
            'user': 'peerdb_' + db, 'password': 'peerdb_' + db + '-local',
            'database': db, 'disableTls': True})
        name = 'analytics_service_' + db
        new_mirror = pg('peerdb_catalog', f'SELECT count(*) FROM flows WHERE name={quote(name)}') == '0'
        with concurrent_snapshot_writes(db == 'order' and new_mirror):
            if new_mirror:
                result = api('/v1/flows/cdc/create', {'connectionConfigs': {
                    'flowJobName': name, 'sourceName': db, 'destinationName': 'analytics_service',
                    'tableMappings': maps, 'publicationName': 'analytics_' + db,
                    'doInitialSnapshot': True, 'snapshotNumRowsPerPartition': 10000,
                    'snapshotMaxParallelWorkers': 1, 'snapshotNumTablesInParallel': 1,
                    'maxBatchSize': 10000, 'idleTimeoutSeconds': 10,
                    'softDeleteColName': '_peerdb_is_deleted', 'syncedAtColName': '_peerdb_synced_at',
                    # Upstream defaults NULL handling off: otherwise completed_at becomes epoch.
                    'env': {'PEERDB_NULLABLE': 'true',
                            # Retain disposable staging files for the PII inspection gate.
                            'PEERDB_CLICKHOUSE_SKIP_STAGING_CLEANUP': 'true'}}})
                if not result.get('workflowId'):
                    raise RuntimeError('No workflow returned for ' + name)
            # Admit one source at a time; lifecycle RUNNING alone is insufficient.
            wait_for(lambda: int(ch(f'SELECT count() FROM analytics.{db}_analytics_cdc_heartbeat')) > 0,
                     db + ' snapshot and normalized heartbeat', 300)
            if new_mirror:
                for table in ALLOW[db]:
                    expected = pg(db, f'SELECT count(*) FROM {table}')
                    wait_for(lambda table=table, expected=expected:
                             ch(f'SELECT uniqExact(id) FROM analytics.{db}_{table}') == expected,
                             db + '.' + table + ' initial copy', 300)
    serving()


def serving():
    # A non-login definer reads exact raw tables; consumers receive view grants only.
    ch("CREATE USER IF NOT EXISTS analytics_view_owner IDENTIFIED WITH sha256_password BY 'view-owner-local' HOST NONE")
    for db, tables in ALLOW.items():
        for table, columns in tables.items():
            name = db + '_' + table
            # A tuple preserves NULLs from the latest row; per-column argMax would skip NULL.
            fields = ','.join(f'latest.{i+1} AS {c}' for i, c in enumerate(columns))
            ch(f'''GRANT SELECT ON analytics.{name} TO analytics_view_owner;
 CREATE OR REPLACE VIEW analytics.{name}_live
 DEFINER = analytics_view_owner SQL SECURITY DEFINER AS
 SELECT {fields} FROM (
 SELECT id,argMax(tuple({','.join(columns)},_peerdb_is_deleted),_peerdb_version) AS latest
 FROM analytics.{name} GROUP BY id) WHERE latest.{len(columns)+1}=0;
 GRANT SELECT ON analytics.{name}_live TO analytics_reader;''')


def freshness_state(lags):
    if len(lags) != 3 or any(lag is None or not math.isfinite(lag) or lag < 0 or lag > 300 for lag in lags):
        return 'unavailable'
    return 'stale' if max(lags) > 120 else 'healthy'


def gate():
    rows = []
    def check(name, fn):
        started = time.monotonic()
        try:
            fn()
            rows.append({'gate': name, 'result': 'PASS'})
        except Exception as error:
            rows.append({'gate': name, 'result': 'FAIL', 'reason': str(error)[:500]})
        rows[-1]['duration_seconds'] = round(time.monotonic() - started, 3)
        print(name, rows[-1]['result'], flush=True)
    def assert_true(condition, message):
        if not condition:
            raise RuntimeError(message)
    def snapshot_counts():
        assert_true(int(pg('postgres', "SELECT concurrent_writes FROM analytics_snapshot_evidence WHERE source='order'")) > 1, 'snapshot under writes not exercised')
        for db, tables in ALLOW.items():
            for table in tables:
                expected = pg(db, f'SELECT count(*) FROM {table}')
                wait_for(lambda db=db, table=table, expected=expected:
                         ch(f'SELECT count() FROM analytics.{db}_{table}_live') == expected,
                         f'{db}.{table} snapshot count')
        assert_true(ch('SELECT sum(amount_minor) FROM analytics.payment_ledger_entries_live') ==
                    pg('payment', 'SELECT sum(amount_minor) FROM ledger_entries'), 'ledger amount checksum')
    def source_privileges():
        for db, tables in ALLOW.items():
            role = 'peerdb_' + db
            assert_true(pg(db, f"SELECT rolreplication AND NOT rolsuper AND NOT rolbypassrls AND NOT rolcreatedb AND NOT rolcreaterole FROM pg_roles WHERE rolname='{role}'") == 't', role + ' attributes')
            assert_true(pg(db, f"SELECT has_database_privilege('{role}','{db}','CREATE')") == 'f', role + ' database DDL')
            for table in tables:
                assert_true(pg(db, f"SELECT has_table_privilege('{role}','{table}','SELECT') AND NOT has_table_privilege('{role}','{table}','INSERT,UPDATE,DELETE,TRUNCATE')") == 't', role + ' table ACL')
        assert_true(pg('postgres', "SELECT count(*) FROM cron.job WHERE username='analytics_heartbeat' AND schedule='30 seconds'") == '3', 'heartbeat job count')
    def reader_privileges():
        def read(sql):
            return compose('exec', '-T', 'clickhouse', 'clickhouse-client',
                           '--user', 'analytics_reader', '--password', 'analytics-reader-local', sql=sql)
        assert_true(int(read('SELECT count() FROM analytics.order_orders_live')) > 0,
                    'serving view not readable')
        for sql in ['SELECT count() FROM analytics.order_orders',
                    'INSERT INTO analytics.order_orders (id) VALUES (-39999)']:
            try:
                read(sql)
            except RuntimeError as error:
                if 'ACCESS_DENIED' not in str(error):
                    raise
            else:
                raise RuntimeError('read identity gained raw access or write permission')
    def schema():
        for db, tables in ALLOW.items():
            for table, columns in tables.items():
                name = db + '_' + table
                actual = set(ch(f"SELECT name FROM system.columns WHERE database='analytics' AND table='{name}'").splitlines())
                assert_true(actual == set(columns) | {'_peerdb_version','_peerdb_is_deleted','_peerdb_synced_at'}, name + ': unexpected raw columns')
                assert_true('RFC0030_FORBIDDEN_PII' not in ch(f'SELECT * FROM analytics.{name} FORMAT JSONEachRow'), name + ': PII marker')
    def freshness(after=0):
        for db in ALLOW:
            wait_for(lambda db=db: 0 <= float(ch(f'SELECT dateDiff(\'second\',max(emitted_at),now()) FROM analytics.{db}_analytics_cdc_heartbeat_live')) <= 120,
                     db + ' target freshness', 150)
            wait_for(lambda db=db: float(ch(f'SELECT toUnixTimestamp64Milli(max(emitted_at))/1000 FROM analytics.{db}_analytics_cdc_heartbeat_live')) > after, db + ' new heartbeat', 150)
    def update_delete():
        pg('order', 'DELETE FROM order_items WHERE id=-30002')
        wait_for(lambda: ch('SELECT count() FROM analytics.order_order_items_live WHERE id=-30002') == '0', 'CDC insert precondition')
        pg('order', "INSERT INTO order_items(id,order_id,product_id,product_name,quantity,price,subtotal) VALUES(-30002,-30000,1,'CDC-only product',1,1000,1000)")
        wait_for(lambda: ch('SELECT count() FROM analytics.order_order_items_live WHERE id=-30002') == '1', 'CDC insert')
        pg('order', "UPDATE orders SET status='confirmed',version=version+1 WHERE id=-30000")
        wait_for(lambda: ch('SELECT status FROM analytics.order_orders_live WHERE id=-30000') == 'confirmed', 'update')
        pg('order', 'UPDATE orders SET completed_at=now() WHERE id=-30000')
        wait_for(lambda: ch('SELECT isNotNull(completed_at) FROM analytics.order_orders_live WHERE id=-30000') == '1', 'non-null update')
        pg('order', 'UPDATE orders SET completed_at=NULL WHERE id=-30000')
        wait_for(lambda: ch('SELECT isNull(completed_at) FROM analytics.order_orders_live WHERE id=-30000') == '1', 'NULL update')
        ch('INSERT INTO analytics.order_orders SELECT * FROM analytics.order_orders WHERE id=-30000 ORDER BY _peerdb_version DESC LIMIT 1')
        assert_true(ch('SELECT count() FROM analytics.order_orders_live WHERE id=-30000') == '1', 'replayed row not deduplicated')
        pg('order', 'DELETE FROM order_items WHERE id IN (-30000,-30002)')
        wait_for(lambda: ch('SELECT count() FROM analytics.order_order_items_live WHERE id IN (-30000,-30002)') == '0', 'tombstone')
    def restart():
        start = float(pg('postgres', 'SELECT extract(epoch FROM clock_timestamp())'))
        compose('restart', 'analytics-flow-worker')
        freshness(after=start)
        assert_true(ch('SELECT count() FROM analytics.order_orders_live WHERE id=-30000') == '1', 'duplicate live order')
    def staging():
        data = json.loads(compose('run', '--rm', '--no-deps', '--entrypoint', 'aws',
            'analytics-service-cdc-bootstrap', '--endpoint-url', 'http://analytics-service-cdc-storage:9000',
            's3api', 'list-objects-v2', '--bucket', 'analytics-service-cdc', '--output', 'json'))
        keys = [x['Key'] for x in data.get('Contents', []) if x['Key'].endswith('.avro')]
        assert_true(bool(keys), 'no retained Avro artifacts to inspect')
        inspected = set()
        for key in keys:
            match = [(db, table, cols) for db, tables in ALLOW.items() for table, cols in tables.items()
                     if f'clone_analytics_{db}_public_{table}_' in key]
            if not match:
                fn = f"s3({quote('http://analytics-service-cdc-storage:9000/analytics-service-cdc/' + key)},'analytics-service-cdc','analytics-service-cdc-local-secret','Avro')"
                assert_true('RFC0030_FORBIDDEN_PII' not in ch('SELECT * FROM ' + fn + ' FORMAT JSONEachRow'), 'PII in CDC staging')
                continue
            db, table, cols = match[0]
            fn = f"s3({quote('http://analytics-service-cdc-storage:9000/analytics-service-cdc/' + key)},'analytics-service-cdc','analytics-service-cdc-local-secret','Avro')"
            # PeerDB Avro field names encode source ordinal: completed_at_5.
            names = {re.sub(r'_\d+$', '', line.split('\t')[0])
                     for line in ch('DESCRIBE TABLE ' + fn).splitlines()}
            assert_true(names <= set(cols) | {'_peerdb_synced_at','_peerdb_is_deleted','_peerdb_version'}, 'unexpected Avro column: ' + db + '.' + table)
            assert_true('RFC0030_FORBIDDEN_PII' not in ch('SELECT * FROM ' + fn + ' FORMAT JSONEachRow'), 'PII in staged snapshot')
            inspected.add((db, table))
        expected = {(db, table) for db, tables in ALLOW.items() for table in tables}
        assert_true(inspected == expected, 'snapshot Avro coverage incomplete')
    def response_states():
        pg('postgres', "UPDATE cron.job SET active=false WHERE jobname IN ('analytics-order','analytics-checkout','analytics-payment')")
        try:
            for age, expected in [(180, 'stale'), (360, 'unavailable')]:
                pg('payment', f"UPDATE analytics_cdc_heartbeat SET emitted_at=clock_timestamp()-interval '{age} seconds'")
                def observed():
                    lags = [float(ch(f"SELECT dateDiff('second',max(emitted_at),now()) FROM analytics.{db}_analytics_cdc_heartbeat_live")) for db in ALLOW]
                    return freshness_state(lags) == expected
                wait_for(observed, expected + ' observed target state', 90)
            assert_true(freshness_state([None, 0, 0]) == 'unavailable', 'unknown progress')
        finally:
            pg('postgres', "UPDATE cron.job SET active=true WHERE jobname IN ('analytics-order','analytics-checkout','analytics-payment')")
        freshness(after=float(pg('postgres', 'SELECT extract(epoch FROM clock_timestamp())')))
    def outage(service):
        start = float(pg('postgres', 'SELECT extract(epoch FROM clock_timestamp())'))
        compose('stop', service)
        try:
            pg('order', 'UPDATE orders SET version=version+1 WHERE id=-30000')
            version = pg('order', 'SELECT version FROM orders WHERE id=-30000')
            time.sleep(15)
            assert_true(pg('postgres', "SELECT count(*) FROM pg_replication_slots WHERE slot_type='logical' AND wal_status='lost'") == '0', 'logical slot invalidated')
            assert_true(pg('postgres', 'SHOW max_slot_wal_keep_size') == '1GB', 'WAL cap missing')
        finally:
            compose('start', service)
        wait_for(lambda: ch('SELECT version FROM analytics.order_orders_live WHERE id=-30000') == version, service + ' catch-up', 180)
        freshness(after=start)
    check('snapshot counts and ledger sum', snapshot_counts)
    check('source roles and cron jobs', source_privileges)
    check('reader view access and raw/write denial', reader_privileges)
    check('raw column allowlist and PII fixture', schema)
    check('retained snapshot staging PII exclusion', staging)
    check('three target-observed heartbeats', freshness)
    check('CDC updates, NULLs and deletes', update_delete)
    check('worker restart and latest-row uniqueness', restart)
    check('target stale and unavailable classification', response_states)
    for service in ['analytics-service-cdc-storage', 'clickhouse']:
        check(service + ' outage and catch-up', lambda service=service: outage(service))
    check('post-recovery raw PII exclusion', schema)
    check('post-CDC staging PII exclusion', staging)
    def logs():
        value = compose('logs', '--no-color', 'analytics-flow-api', 'analytics-flow-worker', 'analytics-snapshot-worker')
        assert_true('RFC0030_FORBIDDEN_PII' not in value, 'PII marker in PeerDB logs')
    check('PeerDB logs exclude PII fixture', logs)
    output = Path(os.environ.get('ANALYTICS_EVIDENCE_DIR', '/tmp/rfc0030-evidence'))
    output.mkdir(parents=True, exist_ok=True)
    evidence = {'scope': 'Compose only; not CNPG qualification', 'project': PROJECT,
        'input_sha256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                         for p in [HERE / 'control.py', HERE / 'allowlist.json',
                                   ROOT / 'local-stack/compose.analytics.yaml',
                                   HERE / 'postgres/Dockerfile']},
        'dirty_status': {name: subprocess.check_output(['git','-C',str(ROOT.parent / name),'status','--short'], text=True).strip()
                         for name in ['homelab','order-service','checkout-service','payment-service']},
        'source_shas': {name: subprocess.check_output(['git','-C',str(ROOT.parent / name),'rev-parse','HEAD'], text=True).strip() for name in ['homelab','order-service','checkout-service','payment-service']},
        'timestamp_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), 'rows': rows}
    (output / 'results.json').write_text(json.dumps(evidence, indent=2) + '\n')
    (output / 'results.md').write_text('| Gate | Result |\n|---|---|\n' + ''.join(f"| {r['gate']} | {r['result']} |\n" for r in rows))
    return 0 if all(r['result'] == 'PASS' for r in rows) else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['bootstrap', 'gate', 'serving'])
    args = parser.parse_args()
    # The hardcoded project is a deliberate destructive-test boundary.
    if args.action == 'bootstrap':
        bootstrap()
    elif args.action == 'serving':
        serving()
    else:
        return gate()
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as exc:
        print(type(exc).__name__ + ': ' + str(exc)[:1000], file=sys.stderr)
        sys.exit(1)
