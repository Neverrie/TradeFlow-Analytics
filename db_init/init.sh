#!/bin/bash
set -e

echo "Настройка базы: $DB_NAME для пользователя $DB_USER..."

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$DB_USER') THEN
            CREATE ROLE "$DB_USER" LOGIN PASSWORD '$DB_PASSWORD';
        ELSE
            ALTER ROLE "$DB_USER" WITH PASSWORD '$DB_PASSWORD';
        END IF;
    END
    \$\$;
EOSQL

DB_EXISTS=$(psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'")

if [ "$DB_EXISTS" != "1" ]; then
    echo "Creating database $DB_NAME..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -c "CREATE DATABASE \"$DB_NAME\" OWNER \"$DB_USER\""
else
    echo "Database $DB_NAME already exists. Skipping."
fi

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DB_NAME" <<-EOSQL
    
    CREATE TABLE IF NOT EXISTS companies (
        symbol VARCHAR(10) PRIMARY KEY,
        name VARCHAR(255)
    );

    CREATE TABLE IF NOT EXISTS trades (
        id SERIAL PRIMARY KEY,
        symbol VARCHAR(10) REFERENCES companies(symbol),
        price DECIMAL(10, 2) NOT NULL,
        quantity INT NOT NULL,
        total_cost DECIMAL(15, 2) NOT NULL,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    CREATE INDEX IF NOT EXISTS idx_trades_symbol ON trades(symbol);
    CREATE INDEX IF NOT EXISTS idx_trades_ts ON trades(timestamp);

    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO "$DB_USER";
    GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO "$DB_USER";
EOSQL

echo "Инициализация завершена успешно"