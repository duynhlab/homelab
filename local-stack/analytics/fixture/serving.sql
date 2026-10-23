-- Fixture-backed serving layer for analytics-service: local-stack and the
-- Kind dark launch (scripts/analytics/serving-fixture.sh) run this same file.
--
-- CDC is NOT deployed in either: the raw tables are created in the shape
-- PeerDB produces (the allowlisted columns plus _peerdb_version,
-- _peerdb_is_deleted and _peerdb_synced_at, ReplacingMergeTree on the
-- version) and seeded with representative commerce facts, so the API, the
-- Admin page and the telemetry rows can be exercised end to end. The *_live
-- views are the serving contract of RFC-0030 (local-stack/analytics/
-- control.py serving()); the opt-in PeerDB overlay creates the same objects
-- from real mirrors. The heartbeat rows are refreshed every 30 seconds by
-- the analytics-heartbeat container (compose) or Deployment (Kind).
--
-- Identities are NOT here: compose creates them from users.sql, the CHI
-- declares them (users are config there, so CREATE USER is refused).
-- The database is created outside this file as well: compose as a plain
-- database, Kind as Replicated on every replica, so the tables below land
-- on all three.
--
-- Re-runnable: the raw tables are replaced (a type change lands on the next
-- run), the views recreated and the seed regenerated.

-- Raw tables, PeerDB shape. Key types follow the sources as PeerDB maps them:
-- order ids are integer (Int32), checkout stores the order id as text
-- (String), payment as bigint (Int64); the reader's SQL normalizes them.
CREATE OR REPLACE TABLE analytics.order_orders (
  id Int32, status String, version Int64,
  created_at DateTime64(6, 'UTC'), updated_at DateTime64(6, 'UTC'), completed_at Nullable(DateTime64(6, 'UTC')),
  _peerdb_synced_at DateTime64(9) DEFAULT now64(9), _peerdb_is_deleted Int8, _peerdb_version Int64
) ENGINE = ReplacingMergeTree(_peerdb_version) ORDER BY id;

CREATE OR REPLACE TABLE analytics.order_order_items (
  id Int32, order_id Int32, product_id Int32, product_name String, quantity Int32, price Int64, subtotal Int64,
  created_at DateTime64(6, 'UTC'),
  _peerdb_synced_at DateTime64(9) DEFAULT now64(9), _peerdb_is_deleted Int8, _peerdb_version Int64
) ENGINE = ReplacingMergeTree(_peerdb_version) ORDER BY id;

CREATE OR REPLACE TABLE analytics.checkout_checkout_sessions (
  id String, status String, order_id Nullable(String), currency String,
  created_at DateTime64(6, 'UTC'), updated_at DateTime64(6, 'UTC'),
  _peerdb_synced_at DateTime64(9) DEFAULT now64(9), _peerdb_is_deleted Int8, _peerdb_version Int64
) ENGINE = ReplacingMergeTree(_peerdb_version) ORDER BY id;

CREATE OR REPLACE TABLE analytics.payment_payments (
  id Int64, order_id Nullable(Int64), currency String,
  created_at DateTime64(6, 'UTC'), updated_at DateTime64(6, 'UTC'),
  _peerdb_synced_at DateTime64(9) DEFAULT now64(9), _peerdb_is_deleted Int8, _peerdb_version Int64
) ENGINE = ReplacingMergeTree(_peerdb_version) ORDER BY id;

CREATE OR REPLACE TABLE analytics.payment_ledger_transactions (
  id Int64, payment_id Int64, kind String, created_at DateTime64(6, 'UTC'),
  _peerdb_synced_at DateTime64(9) DEFAULT now64(9), _peerdb_is_deleted Int8, _peerdb_version Int64
) ENGINE = ReplacingMergeTree(_peerdb_version) ORDER BY id;

CREATE OR REPLACE TABLE analytics.payment_ledger_entries (
  id Int64, transaction_id Int64, account_id Int64, direction String, amount_minor Int64,
  _peerdb_synced_at DateTime64(9) DEFAULT now64(9), _peerdb_is_deleted Int8, _peerdb_version Int64
) ENGINE = ReplacingMergeTree(_peerdb_version) ORDER BY id;

CREATE OR REPLACE TABLE analytics.payment_ledger_accounts (
  id Int64, name String, type String,
  _peerdb_synced_at DateTime64(9) DEFAULT now64(9), _peerdb_is_deleted Int8, _peerdb_version Int64
) ENGINE = ReplacingMergeTree(_peerdb_version) ORDER BY id;

CREATE OR REPLACE TABLE analytics.order_analytics_cdc_heartbeat (
  id Int16, emitted_at DateTime64(6, 'UTC'),
  _peerdb_synced_at DateTime64(9) DEFAULT now64(9), _peerdb_is_deleted Int8, _peerdb_version Int64
) ENGINE = ReplacingMergeTree(_peerdb_version) ORDER BY id;
CREATE OR REPLACE TABLE analytics.checkout_analytics_cdc_heartbeat AS analytics.order_analytics_cdc_heartbeat;
CREATE OR REPLACE TABLE analytics.payment_analytics_cdc_heartbeat AS analytics.order_analytics_cdc_heartbeat;

-- Serving views: latest version per id, tombstones hidden. FINAL returns the
-- whole highest-_peerdb_version row (NULLs included) without the per-call
-- GROUP BY an argMax wrapper costs (analytics-service#4). The fixture's
-- definer is `default` (exists on every replica of the CHI and in compose);
-- the mirrors phase introduces the non-login analytics_view_owner the ADR
-- names, together with the real raw tables.

CREATE OR REPLACE VIEW analytics.order_orders_live DEFINER = default SQL SECURITY DEFINER AS
  SELECT id, status, version, created_at, updated_at, completed_at
  FROM analytics.order_orders FINAL WHERE _peerdb_is_deleted = 0;
CREATE OR REPLACE VIEW analytics.order_order_items_live DEFINER = default SQL SECURITY DEFINER AS
  SELECT id, order_id, product_id, product_name, quantity, price, subtotal, created_at
  FROM analytics.order_order_items FINAL WHERE _peerdb_is_deleted = 0;
CREATE OR REPLACE VIEW analytics.checkout_checkout_sessions_live DEFINER = default SQL SECURITY DEFINER AS
  SELECT id, status, order_id, currency, created_at, updated_at
  FROM analytics.checkout_checkout_sessions FINAL WHERE _peerdb_is_deleted = 0;
CREATE OR REPLACE VIEW analytics.payment_payments_live DEFINER = default SQL SECURITY DEFINER AS
  SELECT id, order_id, currency, created_at, updated_at
  FROM analytics.payment_payments FINAL WHERE _peerdb_is_deleted = 0;
CREATE OR REPLACE VIEW analytics.payment_ledger_transactions_live DEFINER = default SQL SECURITY DEFINER AS
  SELECT id, payment_id, kind, created_at
  FROM analytics.payment_ledger_transactions FINAL WHERE _peerdb_is_deleted = 0;
CREATE OR REPLACE VIEW analytics.payment_ledger_entries_live DEFINER = default SQL SECURITY DEFINER AS
  SELECT id, transaction_id, account_id, direction, amount_minor
  FROM analytics.payment_ledger_entries FINAL WHERE _peerdb_is_deleted = 0;
CREATE OR REPLACE VIEW analytics.payment_ledger_accounts_live DEFINER = default SQL SECURITY DEFINER AS
  SELECT id, name, type
  FROM analytics.payment_ledger_accounts FINAL WHERE _peerdb_is_deleted = 0;
CREATE OR REPLACE VIEW analytics.order_analytics_cdc_heartbeat_live DEFINER = default SQL SECURITY DEFINER AS
  SELECT id, emitted_at
  FROM analytics.order_analytics_cdc_heartbeat FINAL WHERE _peerdb_is_deleted = 0;
CREATE OR REPLACE VIEW analytics.checkout_analytics_cdc_heartbeat_live DEFINER = default SQL SECURITY DEFINER AS
  SELECT id, emitted_at
  FROM analytics.checkout_analytics_cdc_heartbeat FINAL WHERE _peerdb_is_deleted = 0;
CREATE OR REPLACE VIEW analytics.payment_analytics_cdc_heartbeat_live DEFINER = default SQL SECURITY DEFINER AS
  SELECT id, emitted_at
  FROM analytics.payment_analytics_cdc_heartbeat FINAL WHERE _peerdb_is_deleted = 0;

-- Representative seed: {orders} orders spread over the last 100 UTC days,
-- one line each, every order captured, every twentieth refunded a day later,
-- one in ten still processing. Deterministic from the row number so a rerun
-- produces the same facts.
INSERT INTO analytics.payment_ledger_accounts (id, name, type, _peerdb_is_deleted, _peerdb_version)
  VALUES (6, 'merchant_revenue', 'revenue', 0, 1), (7, 'cash', 'asset', 0, 1);

INSERT INTO analytics.order_orders (id, status, version, created_at, updated_at, completed_at, _peerdb_is_deleted, _peerdb_version)
  SELECT toInt32(number + 1),
         if(number % 10 = 9, 'processing', 'completed'), 3,
         toDateTime64(now() - toIntervalDay(number % 100) - toIntervalSecond((number * 7919) % 86400), 6, 'UTC') AS created,
         created + toIntervalMinute(30),
         if(number % 10 = 9, NULL, created + toIntervalHour(2)),
         0, 1
  FROM numbers({orders:UInt64});

INSERT INTO analytics.order_order_items (id, order_id, product_id, product_name, quantity, price, subtotal, created_at, _peerdb_is_deleted, _peerdb_version)
  SELECT toInt32(number + 1), toInt32(number + 1), toInt32(number % 50 + 1), concat('Product ', toString(number % 50 + 1)),
         toInt32(number % 3 + 1), 1000 + (number % 50) * 100, (number % 3 + 1) * (1000 + (number % 50) * 100),
         toDateTime64(now() - toIntervalDay(number % 100) - toIntervalSecond((number * 7919) % 86400), 6, 'UTC'),
         0, 1
  FROM numbers({orders:UInt64});

INSERT INTO analytics.checkout_checkout_sessions (id, status, order_id, currency, created_at, updated_at, _peerdb_is_deleted, _peerdb_version)
  SELECT concat('cs-', toString(number + 1)), 'completed', toString(number + 1), 'USD',
         toDateTime64(now() - toIntervalDay(number % 100) - toIntervalSecond((number * 7919) % 86400) - toIntervalMinute(5), 6, 'UTC') AS created,
         created + toIntervalMinute(5), 0, 1
  FROM numbers({orders:UInt64});

INSERT INTO analytics.payment_payments (id, order_id, currency, created_at, updated_at, _peerdb_is_deleted, _peerdb_version)
  SELECT number + 1, number + 1, 'USD',
         toDateTime64(now() - toIntervalDay(number % 100) - toIntervalSecond((number * 7919) % 86400), 6, 'UTC') AS created,
         created, 0, 1
  FROM numbers({orders:UInt64});

-- Captures: transaction id = order id. Refunds: id = orders + order id, a day later.
INSERT INTO analytics.payment_ledger_transactions (id, payment_id, kind, created_at, _peerdb_is_deleted, _peerdb_version)
  SELECT number + 1, number + 1, 'capture',
         toDateTime64(now() - toIntervalDay(number % 100) - toIntervalSecond((number * 7919) % 86400), 6, 'UTC'), 0, 1
  FROM numbers({orders:UInt64});
INSERT INTO analytics.payment_ledger_transactions (id, payment_id, kind, created_at, _peerdb_is_deleted, _peerdb_version)
  SELECT {orders:UInt64} + number + 1, number + 1, 'refund',
         toDateTime64(now() - toIntervalDay(number % 100) - toIntervalSecond((number * 7919) % 86400) + toIntervalDay(1), 6, 'UTC'), 0, 1
  FROM numbers({orders:UInt64}) WHERE number % 20 = 0;

-- Entries: the merchant_revenue leg (account 6) carries the figures the
-- overview sums; the cash leg (account 7) balances it.
INSERT INTO analytics.payment_ledger_entries (id, transaction_id, account_id, direction, amount_minor, _peerdb_is_deleted, _peerdb_version)
  SELECT number + 1, number + 1, 6, 'credit', (number % 3 + 1) * (1000 + (number % 50) * 100), 0, 1
  FROM numbers({orders:UInt64});
INSERT INTO analytics.payment_ledger_entries (id, transaction_id, account_id, direction, amount_minor, _peerdb_is_deleted, _peerdb_version)
  SELECT {orders:UInt64} + number + 1, number + 1, 7, 'debit', (number % 3 + 1) * (1000 + (number % 50) * 100), 0, 1
  FROM numbers({orders:UInt64});
INSERT INTO analytics.payment_ledger_entries (id, transaction_id, account_id, direction, amount_minor, _peerdb_is_deleted, _peerdb_version)
  SELECT 2 * {orders:UInt64} + number + 1, {orders:UInt64} + number + 1, 6, 'debit', 1000 + (number % 50) * 100, 0, 1
  FROM numbers({orders:UInt64}) WHERE number % 20 = 0;

-- First heartbeat so the API is healthy as soon as the stack is up; the
-- analytics-heartbeat loop keeps them within 30 seconds from here on.
INSERT INTO analytics.order_analytics_cdc_heartbeat (id, emitted_at, _peerdb_is_deleted, _peerdb_version) VALUES (1, now64(6), 0, 1);
INSERT INTO analytics.checkout_analytics_cdc_heartbeat (id, emitted_at, _peerdb_is_deleted, _peerdb_version) VALUES (1, now64(6), 0, 1);
INSERT INTO analytics.payment_analytics_cdc_heartbeat (id, emitted_at, _peerdb_is_deleted, _peerdb_version) VALUES (1, now64(6), 0, 1);
