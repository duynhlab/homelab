-- One login role and one database per consumer, each database OWNED by its
-- role — the cluster's per-service triplet (RFC-0012, ADR-013): a non-superuser
-- role, `owner: <role>` on the Database, and the role confined to its own
-- database (pg_hba on the cluster; REVOKE CONNECT FROM PUBLIC here). The
-- `postgres` superuser stays for administration and the audit's psql reads.
-- Passwords are dev-only `<role>-local`; `user` and `order` are reserved words.
DO $$
DECLARE
  r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['user','product','cart','order','shipping',
                           'notification','payment','checkout','inventory',
                           'keycloak','temporal'] LOOP
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE',
                   r, r || '-local');
  END LOOP;
END $$;

CREATE DATABASE "user" OWNER "user";
CREATE DATABASE product OWNER product;
CREATE DATABASE cart OWNER cart;
CREATE DATABASE "order" OWNER "order";
-- review uses the owner / migrator / runtime split (RFC-0029,
-- docs/databases/authorization.md): the owner owns the database and never
-- logs in; the migrator reaches it only through SET ROLE.
CREATE ROLE review_owner NOLOGIN;
CREATE ROLE review_migrator LOGIN NOINHERIT PASSWORD 'review_migrator-local'
  NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE review_runtime LOGIN PASSWORD 'review_runtime-local'
  NOSUPERUSER NOCREATEDB NOCREATEROLE;
GRANT review_owner TO review_migrator WITH INHERIT FALSE, SET TRUE, ADMIN FALSE;
CREATE DATABASE review OWNER review_owner;
CREATE DATABASE shipping OWNER shipping;
CREATE DATABASE notification OWNER notification;
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
-- review's owner cannot log in, so its two logins get CONNECT explicitly.
GRANT CONNECT ON DATABASE review TO review_runtime, review_migrator;
