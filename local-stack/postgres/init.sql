-- Creates one database per backend service. All owned by the default
-- `postgres` superuser; each service connects with DB_USER=postgres locally.
-- `user` and `order` are reserved words, hence the quoting.
CREATE DATABASE auth;
CREATE DATABASE "user";
CREATE DATABASE product;
CREATE DATABASE cart;
CREATE DATABASE "order";
CREATE DATABASE review;
CREATE DATABASE shipping;
CREATE DATABASE notification;
CREATE DATABASE payment;
CREATE DATABASE checkout;
CREATE DATABASE inventory;
-- Temporal's own stores. Created here rather than by `temporal-sql-tool create`
-- so the topology mirrors the cluster, where CNPG postInitSQL owns creation and
-- Temporal runs with `createDatabase: false`. The tables inside them are managed
-- by the `temporal-schema` container.
CREATE DATABASE temporal;
CREATE DATABASE temporal_visibility;
