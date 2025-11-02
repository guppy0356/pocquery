-- Nested Loop 検証用テストデータ
-- クエリ最適化の検証用データ

-- 1. ユーザーテーブルの作成 (件数は少なめ)
CREATE TABLE users (
    id INT PRIMARY KEY,
    name VARCHAR(100)
);

-- 2. 注文テーブルの作成 (件数は多め)
CREATE TABLE orders (
    id INT PRIMARY KEY,
    user_id INT,
    order_date DATE,
    amount INT
);

-- 3. テストデータの挿入
-- (users は少なく、orders は多くして偏りを作る)
INSERT INTO users (id, name) VALUES
(1, 'Alice'),
(2, 'Bob'),
(3, 'Charlie');

-- (Bob (id=2) の注文を意図的に多くする)
-- 10,000件のordersを生成: Bob=8000件, Alice=1000件, Charlie=1000件
INSERT INTO orders (id, user_id, order_date, amount)
SELECT
    i as id,
    CASE
        WHEN i <= 8000 THEN 2   -- Bob: 8000件 (80%)
        WHEN i <= 9000 THEN 1   -- Alice: 1000件 (10%)
        ELSE 3                   -- Charlie: 1000件 (10%)
    END as user_id,
    DATE '2024-01-01' + (i % 365) * INTERVAL '1 day' as order_date,
    (1000 + (i % 9000)) as amount
FROM generate_series(1, 10000) as i;

-- 完了メッセージ
DO $$
BEGIN
    RAISE NOTICE 'Nested Loop test data created successfully!';
    RAISE NOTICE 'Users: 3 records, Orders: 7 records (Bob has 5 orders)';
END $$;
