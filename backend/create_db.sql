CREATE USER pos_user WITH PASSWORD 'pos_password';
CREATE DATABASE pos_db OWNER pos_user;
GRANT ALL PRIVILEGES ON DATABASE pos_db TO pos_user;
