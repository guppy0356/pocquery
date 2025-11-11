-- ============================================
-- 複合インデックステスト用データ
-- ============================================
-- テーマ: 複合インデックスによるSort Aggregate vs Hash Aggregate
-- WHERE句での絞り込み + GROUP BYでの集計
-- ============================================

-- 店舗マスター
CREATE TABLE shops (
  id INT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  region VARCHAR(50) NOT NULL
);

-- 注文テーブル
CREATE TABLE orders (
  id INT PRIMARY KEY,
  shop_id INT NOT NULL,
  shipped_date DATE NOT NULL,
  customer_id INT NOT NULL,
  total_amount INT NOT NULL
);

-- ============================================
-- データ投入
-- ============================================

-- 店舗データ（100店舗）
INSERT INTO shops (id, name, region)
SELECT
  i as id,
  'Shop_' || i as name,
  CASE
    WHEN i % 4 = 0 THEN 'North'
    WHEN i % 4 = 1 THEN 'South'
    WHEN i % 4 = 2 THEN 'East'
    ELSE 'West'
  END as region
FROM generate_series(1, 100) as i;

-- 注文データ（5,000,000件）
-- shipped_dateの分布:
--   直近1日: 約20,000件（0.4%）← WHEREで絞り込む対象
--   2日以降: 約4,980,000件（99.6%）
INSERT INTO orders (id, shop_id, shipped_date, customer_id, total_amount)
SELECT
  i as id,
  ((i - 1) % 100) + 1 as shop_id,  -- 1-100の店舗IDを均等に割り当て
  CASE
    -- 直近1日（0.4%のデータ）
    WHEN i <= 20000 THEN
      CURRENT_DATE
    -- 2日以降（99.6%のデータ）
    ELSE
      CURRENT_DATE - 1 - ((i - 20001) % 364)
  END as shipped_date,
  ((i - 1) % 50000) + 1 as customer_id,  -- 50,000人の顧客
  (random() * 10000 + 1000)::INT as total_amount  -- 1,000-11,000円
FROM generate_series(1, 5000000) as i;

-- ============================================
-- 統計情報更新
-- ============================================
ANALYZE shops;
ANALYZE orders;
