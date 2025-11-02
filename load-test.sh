#!/bin/bash
# テストケースをロードするヘルパースクリプト

set -e

TEMPLATES_DIR="init-db-templates"
INIT_DB_DIR="init-db"
TEST_FILE="test-data.sql"

# 使い方表示
show_usage() {
    echo "Usage: ./load-test.sh <test-case>"
    echo ""
    echo "Available test cases:"
    for file in "$TEMPLATES_DIR"/*.sql; do
        basename "$file" .sql
    done
    exit 1
}

# 引数チェック
if [ $# -eq 0 ]; then
    show_usage
fi

TEST_CASE=$1
TEMPLATE_FILE="$TEMPLATES_DIR/${TEST_CASE}.sql"

# テンプレートファイルの存在確認
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Error: Test case '$TEST_CASE' not found in $TEMPLATES_DIR/"
    echo ""
    show_usage
fi

# 既存のテストファイルを削除（もし存在すれば）
if [ -f "$INIT_DB_DIR/$TEST_FILE" ]; then
    echo "Removing existing test file: $INIT_DB_DIR/$TEST_FILE"
    rm "$INIT_DB_DIR/$TEST_FILE"
fi

# テンプレートをコピー
echo "Loading test case: $TEST_CASE"
cp "$TEMPLATE_FILE" "$INIT_DB_DIR/$TEST_FILE"

echo "✓ Test case loaded: $INIT_DB_DIR/$TEST_FILE"
echo ""
echo "Next steps:"
echo "  1. docker compose down -v"
echo "  2. docker compose up -d"
