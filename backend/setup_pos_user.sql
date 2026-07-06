-- Check if pos_user exists
SELECT usename FROM pg_user WHERE usename='pos_user';

-- Create user if not exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_user WHERE usename = 'pos_user') THEN
        EXECUTE 'CREATE USER pos_user WITH PASSWORD ''pos_password''';
        RAISE NOTICE 'User pos_user created';
    ELSE
        RAISE NOTICE 'User pos_user already exists';
    END IF;
END $$;

-- Create database if not exists (in PostgreSQL, we need to create it outside SQL)
-- But we can check if it exists
SELECT datname FROM pg_database WHERE datname = 'pos_db';

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE pos_db TO pos_user;
