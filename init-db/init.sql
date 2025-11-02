-- POC Query - PostgreSQL 初期化スクリプト
-- SQLパフォーマンス検証用のデータベース設定

-- パフォーマンス検証用の拡張機能を有効化
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- パフォーマンス分析用のスキーマ
CREATE SCHEMA IF NOT EXISTS performance;

-- クエリ統計を記録するためのテーブル
CREATE TABLE IF NOT EXISTS performance.query_stats (
    id SERIAL PRIMARY KEY,
    query_name VARCHAR(255),
    execution_time_ms NUMERIC(10, 2),
    rows_returned INTEGER,
    executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    notes TEXT
);

-- インデックス作成
CREATE INDEX IF NOT EXISTS idx_query_stats_executed_at
    ON performance.query_stats(executed_at);
CREATE INDEX IF NOT EXISTS idx_query_stats_query_name
    ON performance.query_stats(query_name);

-- パフォーマンス分析用のビュー
CREATE OR REPLACE VIEW performance.query_summary AS
SELECT
    query_name,
    COUNT(*) as execution_count,
    AVG(execution_time_ms) as avg_time_ms,
    MIN(execution_time_ms) as min_time_ms,
    MAX(execution_time_ms) as max_time_ms,
    SUM(rows_returned) as total_rows
FROM performance.query_stats
GROUP BY query_name;

-- 便利な関数：クエリ実行時間を記録
CREATE OR REPLACE FUNCTION performance.log_query_execution(
    p_query_name VARCHAR(255),
    p_execution_time_ms NUMERIC(10, 2),
    p_rows_returned INTEGER,
    p_notes TEXT DEFAULT NULL
) RETURNS void AS $$
BEGIN
    INSERT INTO performance.query_stats (query_name, execution_time_ms, rows_returned, notes)
    VALUES (p_query_name, p_execution_time_ms, p_rows_returned, p_notes);
END;
$$ LANGUAGE plpgsql;

-- 完了メッセージ
DO $$
BEGIN
    RAISE NOTICE 'POC Query database initialized successfully!';
    RAISE NOTICE 'Performance schema and tools are ready to use.';
END $$;
