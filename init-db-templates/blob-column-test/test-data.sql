-- ============================================
-- BLOB Column Performance Test
-- ============================================
-- テーマ: BLOBカラムがSELECTパフォーマンスに与える影響を検証
--
-- データ構成:
--   - attachments テーブル (10,000件)
--   - 各レコードに10KBのBLOBデータ
--   - 合計データサイズ: 約100MB
--
-- 学習ポイント:
--   - SELECT * によるBLOB取得のオーバーヘッド
--   - 必要なカラムのみ選択する重要性
--   - テーブル設計（BLOBの分離）のベストプラクティス
-- ============================================

-- pgcrypto拡張を有効化（gen_random_bytes()に必要）
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- attachments テーブル作成
CREATE TABLE attachments (
  id SERIAL PRIMARY KEY,
  filename VARCHAR(255) NOT NULL,
  content_type VARCHAR(100) NOT NULL,
  file_size INTEGER NOT NULL,
  uploaded_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  file_data BYTEA NOT NULL  -- BLOBデータ（約10KB/レコード）
);

-- データ投入（10,000件、各10KB）
INSERT INTO attachments (filename, content_type, file_size, uploaded_at, file_data)
SELECT
  'file_' || LPAD(i::TEXT, 5, '0') ||
    CASE (i % 4)
      WHEN 0 THEN '.pdf'
      WHEN 1 THEN '.jpg'
      WHEN 2 THEN '.zip'
      ELSE '.docx'
    END as filename,
  CASE (i % 4)
    WHEN 0 THEN 'application/pdf'
    WHEN 1 THEN 'image/jpeg'
    WHEN 2 THEN 'application/zip'
    ELSE 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
  END as content_type,
  10240 as file_size,  -- 10KB
  CURRENT_TIMESTAMP - (i || ' minutes')::INTERVAL as uploaded_at,
  -- 10KBのランダムBLOBデータ生成（圧縮されにくいデータ）
  -- gen_random_bytes() を複数回連結して10KB作成（1024バイト × 10回）
  gen_random_bytes(1024) || gen_random_bytes(1024) || gen_random_bytes(1024) || gen_random_bytes(1024) || gen_random_bytes(1024) ||
  gen_random_bytes(1024) || gen_random_bytes(1024) || gen_random_bytes(1024) || gen_random_bytes(1024) || gen_random_bytes(1024) as file_data
FROM generate_series(1, 10000) as i;

-- インデックス作成
CREATE INDEX idx_attachments_uploaded_at ON attachments(uploaded_at);
CREATE INDEX idx_attachments_content_type ON attachments(content_type);

-- VACUUM ANALYZE で統計情報を更新
VACUUM ANALYZE attachments;
