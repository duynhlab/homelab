-- One database per consumer, confined to its own logins (pg_hba on the
-- cluster; REVOKE CONNECT FROM PUBLIC here). Services not yet converted to the
-- RFC-0029 roles still use one login that owns its database; converted ones
-- are created in the second block. The `postgres` superuser stays for
-- administration and the audit's psql reads. Passwords are dev-only
-- `<role>-local`; `user` and `order` are reserved words.
DO $$
DECLARE
  r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['product','cart','order','payment','checkout','inventory',
                           'keycloak','temporal'] LOOP
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE',
                   r, r || '-local');
  END LOOP;
END $$;

CREATE DATABASE product OWNER product;
CREATE DATABASE cart OWNER cart;
CREATE DATABASE "order" OWNER "order";
-- Converted services use the owner / migrator / runtime split (RFC-0029,
-- docs/databases/authorization.md): the owner owns the database and never
-- logs in; the migrator reaches it only through SET ROLE.
DO $$
DECLARE
  s text;
BEGIN
  FOREACH s IN ARRAY ARRAY['user','notification','shipping','review'] LOOP
    EXECUTE format('CREATE ROLE %I NOLOGIN', s || '_owner');
    EXECUTE format('CREATE ROLE %I LOGIN NOINHERIT PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE',
                   s || '_migrator', s || '_migrator-local');
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE',
                   s || '_runtime', s || '_runtime-local');
    EXECUTE format('GRANT %I TO %I WITH INHERIT FALSE, SET TRUE, ADMIN FALSE',
                   s || '_owner', s || '_migrator');
  END LOOP;
END $$;
CREATE DATABASE "user" OWNER user_owner;
CREATE DATABASE notification OWNER notification_owner;
CREATE DATABASE shipping OWNER shipping_owner;
CREATE DATABASE review OWNER review_owner;
CREATE DATABASE payment OWNER payment;
CREATE DATABASE checkout OWNER checkout;
CREATE DATABASE inventory OWNER inventory;
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
-- The owners cannot log in, so each converted service's two logins get
-- CONNECT explicitly.
GRANT CONNECT ON DATABASE "user" TO user_runtime, user_migrator;
GRANT CONNECT ON DATABASE notification TO notification_runtime, notification_migrator;
GRANT CONNECT ON DATABASE shipping TO shipping_runtime, shipping_migrator;
GRANT CONNECT ON DATABASE review TO review_runtime, review_migrator;
