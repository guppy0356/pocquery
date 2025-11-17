-- ==================================================
-- join-index-test: JOINでのインデックスの効果検証
-- ==================================================
-- テーマ: INNER JOINでインデックスがあるカラムを使って結合する方が早いことを検証
-- ドメイン: 在庫管理（商品・倉庫・在庫）
-- データ量: 100,000件
-- データ分布: 倉庫ごとの偏り（メイン倉庫に70%）

-- ==================================================
-- テーブル定義
-- ==================================================

-- 商品テーブル
CREATE TABLE products (
  id INT PRIMARY KEY,
  name VARCHAR(100),
  category_id INT
);

-- 倉庫テーブル
CREATE TABLE warehouses (
  id INT PRIMARY KEY,
  name VARCHAR(100),
  location VARCHAR(100)
);

-- 在庫テーブル
-- 注意: 最初はproduct_idにインデックスを作成しない（検証のため）
CREATE TABLE stock (
  id SERIAL PRIMARY KEY,
  product_id INT NOT NULL,
  warehouse_id INT NOT NULL,
  quantity INT NOT NULL
);

-- ==================================================
-- データ投入
-- ==================================================

-- 商品データ: 100,000件
INSERT INTO products (id, name, category_id)
SELECT
  i as id,
  'Product ' || i as name,
  ((i - 1) % 20) + 1 as category_id  -- 20カテゴリに均等分散
FROM generate_series(1, 100000) as i;

-- 倉庫データ: 5件
INSERT INTO warehouses (id, name, location) VALUES
  (1, 'Main Warehouse', 'Tokyo'),
  (2, 'West Warehouse', 'Osaka'),
  (3, 'East Warehouse', 'Sendai'),
  (4, 'North Warehouse', 'Sapporo'),
  (5, 'South Warehouse', 'Fukuoka');

-- 在庫データ: 100,000件（倉庫ごとの偏り）
-- 70%の在庫がメイン倉庫（id=1）に集中
-- 30%が他の倉庫に分散
INSERT INTO stock (product_id, warehouse_id, quantity)
SELECT
  i as product_id,
  CASE
    WHEN (i % 10) < 7 THEN 1  -- 70%がメイン倉庫
    ELSE ((i % 4) + 2)         -- 30%が他の倉庫（2-5）
  END as warehouse_id,
  (i % 100) + 1 as quantity    -- 在庫数: 1-100
FROM generate_series(1, 100000) as i;

-- ==================================================
-- 統計情報を更新
-- ==================================================
ANALYZE products;
ANALYZE warehouses;
ANALYZE stock;
