-- =============================================
-- BETWEEN Index Test - Test Data
-- =============================================
-- テスト内容:
--   - BETWEEN句を使った日時範囲検索でのインデックスの効果を検証
--   - タイムスタンプ型カラムでの範囲検索パフォーマンス
--   - 時系列データの偏りがある場合の最適化
--
-- データ構成:
--   - orders: 500,000件の注文データ
--   - 時系列の偏り: 直近1ヶ月に50%のデータが集中
-- =============================================

-- ordersテーブル作成
CREATE TABLE orders (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL,
  product_id INT NOT NULL,
  amount INT NOT NULL,
  status TEXT NOT NULL,
  created_at TIMESTAMP NOT NULL
);

-- データ投入（500,000件）
-- 時系列の偏りを持たせる:
--   - 直近1ヶ月: 250,000件（50%）
--   - 1-3ヶ月前: 125,000件（25%）
--   - 3-6ヶ月前: 75,000件（15%）
--   - 6-12ヶ月前: 50,000件（10%）

INSERT INTO orders (user_id, product_id, amount, status, created_at)
SELECT
  (random() * 999 + 1)::INT as user_id,
  (random() * 499 + 1)::INT as product_id,
  (random() * 99000 + 1000)::INT as amount,
  CASE
    WHEN random() < 0.7 THEN 'completed'
    WHEN random() < 0.9 THEN 'pending'
    ELSE 'cancelled'
  END as status,
  -- 直近1ヶ月に50%のデータ（1-250,000）
  CASE
    WHEN i <= 250000 THEN
      NOW() - (random() * INTERVAL '30 days')
    -- 1-3ヶ月前に25%のデータ（250,001-375,000）
    WHEN i <= 375000 THEN
      NOW() - (INTERVAL '30 days' + random() * INTERVAL '60 days')
    -- 3-6ヶ月前に15%のデータ（375,001-450,000）
    WHEN i <= 450000 THEN
      NOW() - (INTERVAL '90 days' + random() * INTERVAL '90 days')
    -- 6-12ヶ月前に10%のデータ（450,001-500,000）
    ELSE
      NOW() - (INTERVAL '180 days' + random() * INTERVAL '180 days')
  END as created_at
FROM generate_series(1, 500000) as i;

-- 統計情報を更新
ANALYZE orders;
