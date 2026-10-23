"""PeerDB peers and mirrors for the commerce read model (RFC-0030 phase 6).

Idempotent: a peer or mirror that already exists is left alone. Mirrors are
admitted one source at a time (order, checkout, payment); the next starts only
once the previous one's heartbeat and every table's row count have reached
ClickHouse. Each table mapping excludes every source column outside the
ADR-067 allowlist, so a column added upstream never reaches the target.

Ported from local-stack/analytics/control.py (the Compose prototype).
"""
import base64
import json
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request

API = os.environ['FLOW_API']
CH = os.environ['CLICKHOUSE_HTTP']
CH_AUTH = 'Basic ' + base64.b64encode(
    f"{os.environ['CLICKHOUSE_USER']}:{os.environ['CLICKHOUSE_PASSWORD']}".encode()).decode()
POOLER = os.environ['SOURCE_HOST']
CA_FILE = os.environ['CA_FILE']
ALLOW = json.load(open(os.environ['ALLOWLIST']))
for tables in ALLOW.values():
    tables['analytics_cdc_heartbeat'] = ['id', 'emitted_at']
ORDER = ['order', 'checkout', 'payment']


def log(msg):
    print(time.strftime('%H:%M:%S'), msg, flush=True)


def api(path, payload=None):
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(API + path, data=data, method='POST' if data else 'GET',
                                 headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read() or b'{}')


def ch(sql):
    req = urllib.request.Request(CH + '/?' + urllib.parse.urlencode({'query': sql}),
                                 headers={'Authorization': CH_AUTH})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode().strip()


def pg(db, sql):
    env = dict(os.environ, PGPASSWORD=os.environ[f'PEERDB_{db.upper()}_PASSWORD'])
    dsn = (f'host={POOLER} port=5432 dbname={db} user=peerdb_{db} '
           f'sslmode=verify-full sslrootcert={CA_FILE} application_name=peerdb-bootstrap')
    out = subprocess.run(['psql', '-XAtq', dsn, '-c', sql], env=env, capture_output=True, text=True)
    if out.returncode:
        raise RuntimeError(f'{db}: {out.stderr.strip()}')
    return out.stdout.strip()


def source_ready(db):
    """Every allowlisted table is in the publication and readable as peerdb_<db>."""
    tables = ALLOW[db]
    published = pg(db, f"SELECT count(*) FROM pg_publication_tables WHERE pubname = 'analytics_{db}'")
    if int(published or 0) < len(tables):
        return False
    for table in tables:
        pg(db, f'SELECT 1 FROM public.{table} LIMIT 0')
    return True


def wait_for(check, what, timeout):
    deadline = time.time() + timeout
    while True:
        try:
            if check():
                return
        except Exception as exc:  # noqa: BLE001 — retried until the deadline
            last = exc
        else:
            last = None
        if time.time() > deadline:
            raise RuntimeError(f'timed out waiting for {what}: {last}')
        time.sleep(5)


def mappings(db):
    maps = []
    for table, columns in ALLOW[db].items():
        actual = pg(db, "SELECT column_name FROM information_schema.columns WHERE table_schema='public' "
                        f"AND table_name='{table}' ORDER BY ordinal_position").splitlines()
        if not set(columns) <= set(actual):
            raise RuntimeError(f'{db}.{table}: allowlist differs from the source schema: {sorted(set(columns) - set(actual))}')
        maps.append({'sourceTableIdentifier': f'public.{table}',
                     'destinationTableIdentifier': f'{db}_{table}',
                     'exclude': [c for c in actual if c not in columns],
                     'engine': 'CH_ENGINE_REPLICATED_REPLACING_MERGE_TREE'})
    return maps


def ensure_peer(name, kind, config, existing):
    # allowUpdate: a changed config (or a rotated password) converges in place.
    key = 'postgresConfig' if kind == 'POSTGRES' else 'clickhouseConfig'
    resp = api('/v1/peers/create', {'peer': {'name': name, 'type': kind, key: config}, 'allowUpdate': True})
    if resp.get('status') not in ('CREATED', 1):
        raise RuntimeError(f'peer {name} rejected: {resp}')
    log(f"peer {name}: {'updated' if name in existing else 'created'}")


def main():
    wait_for(lambda: api('/v1/mirrors/list') is not None, 'flow-api', 600)
    ca = open(CA_FILE).read()
    peers = api('/v1/peers/list')
    existing = {p['name'] for p in peers.get('items', [])}
    ensure_peer('analytics_service', 'CLICKHOUSE', {
        'host': os.environ['CLICKHOUSE_HOST'], 'port': 9000, 'database': 'analytics',
        'user': os.environ['CLICKHOUSE_USER'], 'password': os.environ['CLICKHOUSE_PASSWORD'],
        # The CHI has no TLS listener yet (ADR-069 T1); the fence is the
        # ingest password and the in-cluster network.
        'disableTls': True,
        # Replicated* engines for the target and _peerdb_raw tables. No
        # `cluster`: the database is Replicated, so DDL fans out without ON
        # CLUSTER and no Distributed table is needed. The ingest profile lets
        # ClickHouse swap PeerDB's explicit Keeper path for the database's own.
        'replicated': True,
        's3Path': 's3://analytics-service-cdc', 'region': 'us-east-1',
        'accessKeyId': os.environ['S3_ACCESS_KEY_ID'], 'secretAccessKey': os.environ['S3_SECRET_ACCESS_KEY'],
        'endpoint': os.environ['S3_ENDPOINT']}, existing)
    for db in ORDER:
        ensure_peer(db, 'POSTGRES', {
            'host': POOLER, 'port': 5432, 'database': db, 'user': f'peerdb_{db}',
            'password': os.environ[f'PEERDB_{db.upper()}_PASSWORD'],
            'requireTls': True, 'rootCa': ca, 'tlsHost': POOLER}, existing)

    running = {m['name'] for m in api('/v1/mirrors/list').get('mirrors', [])}
    for db in ORDER:
        name = f'analytics_service_{db}'
        # On a cold start the service migrations create these tables while this
        # Job runs; the publication and the grants converge after them.
        wait_for(lambda db=db: source_ready(db), f'{db} publication and grants', 1800)
        if name in running:
            log(f'mirror {name}: exists')
        else:
            resp = api('/v1/flows/cdc/create', {'connectionConfigs': {
                'flowJobName': name, 'sourceName': db, 'destinationName': 'analytics_service',
                'tableMappings': mappings(db), 'publicationName': f'analytics_{db}',
                'doInitialSnapshot': True, 'snapshotNumRowsPerPartition': 10000,
                'snapshotMaxParallelWorkers': 1, 'snapshotNumTablesInParallel': 1,
                'maxBatchSize': 10000, 'idleTimeoutSeconds': 10,
                'softDeleteColName': '_peerdb_is_deleted', 'syncedAtColName': '_peerdb_synced_at',
                # Upstream defaults NULL handling off: completed_at would become epoch.
                'env': {'PEERDB_NULLABLE': 'true'}}})
            if not resp.get('workflowId'):
                raise RuntimeError(f'mirror {name}: no workflow ({resp})')
            log(f'mirror {name}: created ({resp["workflowId"]})')
        # Admit one source at a time: the heartbeat proves CDC flows end to
        # end, the counts prove the snapshot is complete.
        wait_for(lambda db=db: int(ch(f'SELECT count() FROM analytics.{db}_analytics_cdc_heartbeat') or 0) > 0,
                 f'{db} heartbeat in ClickHouse', 900)
        for table in ALLOW[db]:
            if table == 'analytics_cdc_heartbeat':
                continue
            want = pg(db, f'SELECT count(*) FROM public.{table}')
            wait_for(lambda db=db, table=table, want=want:
                     int(ch(f'SELECT uniqExact(id) FROM analytics.{db}_{table}') or 0) >= int(want),
                     f'{db}.{table} snapshot ({want} rows)', 900)
            log(f'{db}.{table}: {want} rows in ClickHouse')
    log('mirrors admitted: ' + ', '.join(f'analytics_service_{db}' for db in ORDER))


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        log(f'ERROR: {exc}')
        sys.exit(1)
