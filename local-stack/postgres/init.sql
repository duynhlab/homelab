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
