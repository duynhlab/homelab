-- Compose-only identities for the analytics fixture (serving.sql). The CHI
-- declares the same users from its spec; CREATE USER is refused there.
-- Passwords are disposable local-stack values, like every other credential
-- in compose.yaml; the cluster delivers the reader's from OpenBAO.
CREATE DATABASE IF NOT EXISTS analytics;
CREATE USER IF NOT EXISTS analytics_reader IDENTIFIED WITH sha256_password BY 'analytics-reader-local'
  SETTINGS max_memory_usage = 536870912, max_execution_time = 2;
-- The reader gets the ten views and nothing else (the CHI lists the same).
GRANT SELECT ON analytics.order_orders_live TO analytics_reader;
GRANT SELECT ON analytics.order_order_items_live TO analytics_reader;
GRANT SELECT ON analytics.checkout_checkout_sessions_live TO analytics_reader;
GRANT SELECT ON analytics.payment_payments_live TO analytics_reader;
GRANT SELECT ON analytics.payment_ledger_transactions_live TO analytics_reader;
GRANT SELECT ON analytics.payment_ledger_entries_live TO analytics_reader;
GRANT SELECT ON analytics.payment_ledger_accounts_live TO analytics_reader;
GRANT SELECT ON analytics.order_analytics_cdc_heartbeat_live TO analytics_reader;
GRANT SELECT ON analytics.checkout_analytics_cdc_heartbeat_live TO analytics_reader;
GRANT SELECT ON analytics.payment_analytics_cdc_heartbeat_live TO analytics_reader;
