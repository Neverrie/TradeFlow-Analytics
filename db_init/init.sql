DROP TABLE IF EXISTS trades;
DROP TABLE IF EXISTS companies;

CREATE TABLE companies (
    symbol VARCHAR(10) PRIMARY KEY,
    name VARCHAR(255)
);

CREATE TABLE trades (
    id SERIAL PRIMARY KEY,
    symbol VARCHAR(10) REFERENCES companies(symbol),
    price DECIMAL(10, 2) NOT NULL,
    quantity INT NOT NULL,
    total_cost DECIMAL(15, 2) NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_trades_symbol ON trades(symbol);
CREATE INDEX idx_trades_ts ON trades(timestamp);