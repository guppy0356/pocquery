-- ============================================================
-- GROUP BY Filter Test: WHERE vs HAVING
-- ============================================================
--
-- このテストケースは、GROUP BYを使った集計クエリにおいて、
-- WHERE（集計前フィルタ）とHAVING（集計後フィルタ）の
-- パフォーマンス差を検証するためのデータセットです。
--
-- テーブル構成:
-- - shops: 店舗マスタ (1,000店舗)
-- - orders: 注文データ (500,000件)
-- - items: 注文明細 (2,000,000件、平均4件/注文)
--
-- データ分布:
-- - 期間: 2024年1月〜12月
-- - 偏り: 11-12月に60%、1-10月に40%（年末商戦を想定）
-- ============================================================

-- ============================================================
-- shops テーブル: 店舗マスタ
-- ============================================================
CREATE TABLE shops (
  id INT PRIMARY KEY,
  name VARCHAR(100) NOT NULL
);

-- 1,000店舗を生成
INSERT INTO shops (id, name)
SELECT
  i as id,
  'Shop ' || LPAD(i::TEXT, 4, '0') as name
FROM generate_series(1, 1000) as i;

-- ============================================================
-- orders テーブル: 注文データ
-- ============================================================
CREATE TABLE orders (
  id INT PRIMARY KEY,
  shop_id INT NOT NULL,
  customer_id INT NOT NULL,
  order_day DATE NOT NULL,    -- 注文日
  ship_day DATE NOT NULL       -- 発送日（注文日の1-7日後）
);

-- 500,000件の注文を生成
-- データ分布: 11-12月に60% (300,000件)、1-10月に40% (200,000件)
INSERT INTO orders (id, shop_id, customer_id, order_day, ship_day)
SELECT
  i as id,
  ((i - 1) % 1000) + 1 as shop_id,  -- 1〜1000の店舗にランダム割り当て
  ((i - 1) % 50000) + 1 as customer_id,  -- 50,000人の顧客
  -- データ分布の作成
  CASE
    -- 最初の200,000件: 1-10月に分散（40%）
    WHEN i <= 200000 THEN
      DATE '2024-01-01' + ((i - 1) % 304) * INTERVAL '1 day'
    -- 残りの300,000件: 11-12月に集中（60%）
    ELSE
      DATE '2024-11-01' + ((i - 200001) % 61) * INTERVAL '1 day'
  END as order_day,
  -- ship_day は order_day の 1-7日後
  CASE
    WHEN i <= 200000 THEN
      DATE '2024-01-01' + ((i - 1) % 304) * INTERVAL '1 day' + ((i % 7) + 1) * INTERVAL '1 day'
    ELSE
      DATE '2024-11-01' + ((i - 200001) % 61) * INTERVAL '1 day' + ((i % 7) + 1) * INTERVAL '1 day'
  END as ship_day
FROM generate_series(1, 500000) as i;

-- ============================================================
-- items テーブル: 注文明細
-- ============================================================
CREATE TABLE items (
  id INT PRIMARY KEY,
  order_id INT NOT NULL,
  product_name VARCHAR(100) NOT NULL,
  price INT NOT NULL  -- 商品価格（1,000円〜50,000円）
);

-- 2,000,000件の明細を生成（平均4件/注文）
INSERT INTO items (id, order_id, product_name, price)
SELECT
  i as id,
  ((i - 1) / 4) + 1 as order_id,  -- 4件ずつ同じorder_idに割り当て
  'Product ' || LPAD((((i - 1) % 1000) + 1)::TEXT, 4, '0') as product_name,
  1000 + ((i * 73) % 49000) as price  -- 1,000〜50,000円のランダムな価格
FROM generate_series(1, 2000000) as i;

-- ============================================================
-- データ投入完了メッセージ
-- ============================================================
DO $$
BEGIN
  RAISE NOTICE '============================================================';
  RAISE NOTICE 'GROUP BY Filter Test: Data loading completed!';
  RAISE NOTICE '============================================================';
  RAISE NOTICE 'Tables created:';
  RAISE NOTICE '  - shops: 1,000 rows';
  RAISE NOTICE '  - orders: 500,000 rows (40%% Jan-Oct, 60%% Nov-Dec)';
  RAISE NOTICE '  - items: 2,000,000 rows';
  RAISE NOTICE '';
  RAISE NOTICE 'Ready for verification!';
  RAISE NOTICE 'See init-db-templates/groupby-filter-test/README.md for steps.';
  RAISE NOTICE '============================================================';
END $$;
