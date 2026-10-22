-- One login role and one database per unsplit consumer (Keycloak, Temporal), each database OWNED
-- by its role — the cluster's per-service triplet (RFC-0012, ADR-013): a non-superuser
-- role, `owner: <role>` on the Database, and the role confined to its own
-- database (pg_hba on the cluster; REVOKE CONNECT FROM PUBLIC here). The
-- `postgres` superuser stays for administration and the audit's psql reads.
-- Passwords are dev-only `<role>-local`; `user` and `order` are reserved words.
DO $$
DECLARE
  r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['keycloak','temporal'] LOOP
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE',
                   r, r || '-local');
  END LOOP;
END $$;

-- All ten services use the owner / migrator / runtime split (RFC-0029,
-- ADR-088, docs/databases/authorization.md). This file plays
-- the platform: the owner owns the database and never logs in; the migrator
-- becomes the owner at login (role=), so the service runs no SET ROLE; the
-- runtime gets CRUD through the owner's default privileges, applied after the
-- migration by each <svc>-authz service with the cluster's own grants.sql.
DO $$
DECLARE
  s text;
BEGIN
  FOREACH s IN ARRAY ARRAY['review','user','shipping','notification','product','inventory',
                           'cart','order','checkout','payment'] LOOP
    EXECUTE format('CREATE ROLE %I NOLOGIN', s || '_owner');
    EXECUTE format('CREATE ROLE %I LOGIN NOINHERIT PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE',
                   s || '_migrator', s || '_migrator-local');
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE',
                   s || '_runtime', s || '_runtime-local');
    EXECUTE format('GRANT %I TO %I WITH INHERIT FALSE, SET TRUE, ADMIN FALSE',
                   s || '_owner', s || '_migrator');
    EXECUTE format('ALTER ROLE %I SET role = %L', s || '_migrator', s || '_owner');
  END LOOP;
END $$;
CREATE DATABASE review OWNER review_owner;
CREATE DATABASE "user" OWNER user_owner;
CREATE DATABASE shipping OWNER shipping_owner;
CREATE DATABASE notification OWNER notification_owner;
CREATE DATABASE product OWNER product_owner;
CREATE DATABASE inventory OWNER inventory_owner;
CREATE DATABASE cart OWNER cart_owner;
CREATE DATABASE "order" OWNER order_owner;
CREATE DATABASE checkout OWNER checkout_owner;
CREATE DATABASE payment OWNER payment_owner;
-- Keycloak's store (RFC-0024 P3). Mirrors the cluster, where CNPG postInitSQL
-- creates the `keycloak` database on platform-db; tables inside are managed by
-- Keycloak itself on first start.
CREATE DATABASE keycloak OWNER keycloak;
-- Temporal's own stores, both owned by `temporal` as on the cluster. Created
-- here rather than by `temporal-sql-tool create` so the topology mirrors the
-- cluster, where CNPG owns creation and Temporal runs with
-- `createDatabase: false`. The tables inside are managed by `temporal-schema`.
CREATE DATABASE temporal OWNER temporal;
CREATE DATABASE temporal_visibility OWNER temporal;

-- PUBLIC holds CONNECT on every database by default, so revoking from one role
-- is a no-op; take it from PUBLIC and the owner keeps it.
REVOKE CONNECT ON DATABASE "user", product, cart, "order", review, shipping,
  notification, payment, checkout, inventory, keycloak, temporal,
  temporal_visibility FROM PUBLIC;
-- The split services' owners cannot log in, so their logins get CONNECT
-- explicitly.
GRANT CONNECT ON DATABASE review TO review_runtime, review_migrator;
GRANT CONNECT ON DATABASE "user" TO user_runtime, user_migrator;
GRANT CONNECT ON DATABASE shipping TO shipping_runtime, shipping_migrator;
GRANT CONNECT ON DATABASE notification TO notification_runtime, notification_migrator;
GRANT CONNECT ON DATABASE product TO product_runtime, product_migrator;
GRANT CONNECT ON DATABASE inventory TO inventory_runtime, inventory_migrator;
GRANT CONNECT ON DATABASE cart TO cart_runtime, cart_migrator;
GRANT CONNECT ON DATABASE "order" TO order_runtime, order_migrator;
GRANT CONNECT ON DATABASE checkout TO checkout_runtime, checkout_migrator;
GRANT CONNECT ON DATABASE payment TO payment_runtime, payment_migrator;
