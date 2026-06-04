CREATE TABLE IF NOT EXISTS generations (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL,
    prompt TEXT NOT NULL,
    result TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);