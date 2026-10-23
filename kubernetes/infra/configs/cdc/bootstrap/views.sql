-- Serving views over PeerDB's raw tables (RFC-0030 / ADR-069, shape from
-- #1366): the highest _peerdb_version row per key via FINAL, tombstones hidden,
-- allowlisted columns only. The definer is the non-login analytics_view_owner
-- (CHI users); analytics_reader holds SELECT on these views and nothing else.
-- Generated from allowlist.json — regenerate both together.
CREATE OR REPLACE VIEW analytics.order_orders_live DEFINER = analytics_view_owner SQL SECURITY DEFINER AS
  SELECT id, status, version, created_at, updated_at, completed_at
  FROM analytics.order_orders FINAL WHERE _peerdb_is_deleted = 0;
CREATE OR REPLACE VIEW analytics.order_order_items_live DEFINER = analytics_view_owner SQL SECURITY DEFINER AS
  SELECT id, order_id, product_id, product_name, quantity, price, subtotal, created_at
  FROM analytics.order_order_items FINAL WHERE _peerdb_is_deleted = 0;
CREATE OR REPLACE VIEW analytics.order_analytics_cdc_heartbeat_live DEFINER = analytics_view_owner SQL SECURITY DEFINER AS
  SELECT id, emitted_at
  FROM analytics.order_analytics_cdc_heartbeat FINAL WHERE _peerdb_is_deleted = 0;
CREATE OR REPLACE VIEW analytics.checkout_checkout_sessions_live DEFINER = analytics_view_owner SQL SECURITY DEFINER AS
  SELECT id, status, order_id, currency, created_at, updated_at
  FROM analytics.checkout_checkout_sessions FINAL WHERE _peerdb_is_deleted = 0;
CREATE OR REPLACE VIEW analytics.checkout_analytics_cdc_heartbeat_live DEFINER = analytics_view_owner SQL SECURITY DEFINER AS
  SELECT id, emitted_at
  FROM analytics.checkout_analytics_cdc_heartbeat FINAL WHERE _peerdb_is_deleted = 0;
CREATE OR REPLACE VIEW analytics.payment_payments_live DEFINER = analytics_view_owner SQL SECURITY DEFINER AS
  SELECT id, order_id, currency, created_at, updated_at
  FROM analytics.payment_payments FINAL WHERE _peerdb_is_deleted = 0;
CREATE OR REPLACE VIEW analytics.payment_ledger_transactions_live DEFINER = analytics_view_owner SQL SECURITY DEFINER AS
  SELECT id, payment_id, kind, created_at
  FROM analytics.payment_ledger_transactions FINAL WHERE _peerdb_is_deleted = 0;
CREATE OR REPLACE VIEW analytics.payment_ledger_entries_live DEFINER = analytics_view_owner SQL SECURITY DEFINER AS
  SELECT id, transaction_id, account_id, direction, amount_minor
  FROM analytics.payment_ledger_entries FINAL WHERE _peerdb_is_deleted = 0;
CREATE OR REPLACE VIEW analytics.payment_ledger_accounts_live DEFINER = analytics_view_owner SQL SECURITY DEFINER AS
  SELECT id, name, type
  FROM analytics.payment_ledger_accounts FINAL WHERE _peerdb_is_deleted = 0;
CREATE OR REPLACE VIEW analytics.payment_analytics_cdc_heartbeat_live DEFINER = analytics_view_owner SQL SECURITY DEFINER AS
  SELECT id, emitted_at
  FROM analytics.payment_analytics_cdc_heartbeat FINAL WHERE _peerdb_is_deleted = 0;
