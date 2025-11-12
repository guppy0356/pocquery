# BLOBカラムとSELECTパフォーマンス

## データ構成

### テーブル構造

```sql
CREATE TABLE attachments (
  id SERIAL PRIMARY KEY,
  filename VARCHAR(255) NOT NULL,
  content_type VARCHAR(100) NOT NULL,
  file_size INTEGER NOT NULL,
  uploaded_at TIMESTAMP NOT NULL,
  file_data BYTEA NOT NULL  -- BLOBデータ（約10KB/レコード）
);
```

### データ量と分布

- **レコード数**: 10,000件
- **BLOBサイズ**: 10KB/レコード
- **合計データサイズ**: 約100MB
- **ファイルタイプ分布**:
  - PDF (25%)
  - JPEG (25%)
  - ZIP (25%)
  - DOCX (25%)

### インデックス

- `idx_attachments_uploaded_at`: uploaded_at カラム
- `idx_attachments_content_type`: content_type カラム

## 検証内容

このテストケースでは、**BLOBカラムがSELECTパフォーマンスに与える影響**を検証します。

### 学べること

1. `SELECT *` によるBLOB取得の非効率性
2. 必要なカラムのみを選択する重要性
3. I/Oオーバーヘッドとネットワーク転送の影響
4. テーブル設計におけるBLOB分離のベストプラクティス

### 体験できる現象

- BLOBカラムを含むSELECTの実行時間とデータ転送量
- カラムを限定することによる劇的な改善
- テーブル分離による設計レベルの最適化

---

## 検証手順

PostgreSQLコンテナに接続してクエリを実行します：

```bash
docker exec -it pocquery_postgres psql -U postgres -d pocquery
```

### ステップ1: SELECT * でBLOBを含めて取得（非効率）

まず、全カラムを取得するクエリを実行します。

```sql
EXPLAIN ANALYZE
SELECT *
FROM attachments
WHERE uploaded_at >= CURRENT_TIMESTAMP - INTERVAL '1 day'
ORDER BY uploaded_at DESC
LIMIT 100;
```

**期待される結果:**

- Limit と Sort が使われる
- **大量のデータ転送**: 100件 × 10KB = 約1MB
- 実行時間: BLOB読み込みとネットワーク転送のオーバーヘッドで遅い

**実行計画のポイント:**

```
Limit
  -> Sort
      -> Seq Scan (or Index Scan) on attachments
         Filter: uploaded_at >= ...
```

- 実際にはデータ転送のオーバーヘッドが大きいが、EXPLAIN ANALYZEではそれが見えにくい
- psqlでの表示時間やネットワーク転送量に注目

**データ転送量を確認:**

```sql
-- 実際に転送されるデータサイズを計算
SELECT
  COUNT(*) as record_count,
  pg_size_pretty(SUM(LENGTH(file_data))) as total_blob_size,
  pg_size_pretty(AVG(LENGTH(file_data))::BIGINT) as avg_blob_size
FROM attachments
WHERE uploaded_at >= CURRENT_TIMESTAMP - INTERVAL '1 day'
LIMIT 100;
```

---

### ステップ2: 必要なカラムのみSELECT（改善）

次に、BLOBカラムを除外して必要なカラムのみを取得します。

```sql
EXPLAIN ANALYZE
SELECT id, filename, content_type, file_size, uploaded_at
FROM attachments
WHERE uploaded_at >= CURRENT_TIMESTAMP - INTERVAL '1 day'
ORDER BY uploaded_at DESC
LIMIT 100;
```

**期待される改善:**

- **実行計画は同じ**だが、**データ転送量が大幅に削減**
- 100件 × 数百バイト = 約数十KB（BLOBなし）
- 実行時間: 劇的に高速化（特にネットワーク越しのアクセス時）

**データ転送量の比較:**

```sql
-- BLOBなしのデータサイズ（推定）
SELECT
  COUNT(*) as record_count,
  pg_size_pretty(
    COUNT(*) * (
      8 +  -- id (INTEGER)
      LENGTH('file_00001.pdf') +  -- filename (平均)
      LENGTH('application/pdf') +  -- content_type (平均)
      4 +  -- file_size (INTEGER)
      8    -- uploaded_at (TIMESTAMP)
    )
  ) as estimated_size_without_blob
FROM attachments
WHERE uploaded_at >= CURRENT_TIMESTAMP - INTERVAL '1 day'
LIMIT 100;
```

**学習ポイント:**

- SELECT * は避けるべき（特にBLOBを含むテーブル）
- 必要なカラムのみを明示的に指定する
- I/Oとネットワーク転送のコストを意識する

---

### ステップ3: 一覧表示と詳細表示の分離

実際のアプリケーション設計では、以下のパターンが推奨されます：

**パターンA: クエリを分ける**

1. **一覧表示用**: BLOBを除外
   ```sql
   SELECT id, filename, content_type, file_size, uploaded_at
   FROM attachments
   ORDER BY uploaded_at DESC
   LIMIT 100;
   ```

2. **詳細表示/ダウンロード用**: BLOBを取得
   ```sql
   SELECT id, filename, content_type, file_data
   FROM attachments
   WHERE id = 123;  -- 特定の1件のみ
   ```

**パターンB: テーブルを分離（正規化）**

BLOBを別テーブルに分離することで、一覧クエリのパフォーマンスを根本的に改善：

```sql
-- メタデータテーブル（頻繁にアクセス）
CREATE TABLE attachment_metadata (
  id SERIAL PRIMARY KEY,
  filename VARCHAR(255) NOT NULL,
  content_type VARCHAR(100) NOT NULL,
  file_size INTEGER NOT NULL,
  uploaded_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- BLOBテーブル（必要な時のみアクセス）
CREATE TABLE attachment_blobs (
  id INTEGER PRIMARY KEY REFERENCES attachment_metadata(id),
  file_data BYTEA NOT NULL
);

-- 一覧表示: メタデータのみ（高速）
SELECT id, filename, content_type, file_size, uploaded_at
FROM attachment_metadata
ORDER BY uploaded_at DESC
LIMIT 100;

-- ダウンロード: JOINしてBLOBを取得（必要な時のみ）
SELECT m.filename, m.content_type, b.file_data
FROM attachment_metadata m
JOIN attachment_blobs b ON m.id = b.id
WHERE m.id = 123;
```

**テーブル分離のメリット:**

1. **一覧クエリの高速化**: メタデータテーブルのサイズが小さいため、キャッシュ効率が向上
2. **バキューム効率の向上**: メタデータの更新時にBLOBをスキャンする必要がない
3. **バックアップの柔軟性**: メタデータとBLOBを別々に管理できる

---

## 学習ポイント

### 1. SELECT * のコスト

- BLOBカラムを含むテーブルでは、SELECT * は大量のデータ転送を引き起こす
- 必要なカラムのみを明示的に指定することが重要
- 開発時の便利さとパフォーマンスのトレードオフを理解する

### 2. I/Oとネットワーク転送

- クエリ実行時間 = SQL実行時間 + データ転送時間
- EXPLAIN ANALYZEはSQL実行時間のみを表示（データ転送時間は含まれない）
- 実際のアプリケーションでは、ネットワーク越しの転送コストが大きい

### 3. アプリケーション設計のベストプラクティス

- **一覧表示**: メタデータのみ取得（高速）
- **詳細表示/ダウンロード**: 必要な時のみBLOBを取得
- **テーブル分離**: 頻繁にアクセスするデータとBLOBを分ける

### 4. データベース設計の原則

- **垂直分割**: 大きなカラム（BLOB、TEXT）は別テーブルに分離
- **キャッシュ効率**: 頻繁にアクセスするデータは小さく保つ
- **VACUUM効率**: 更新頻度の高いカラムと低いカラムを分ける

---

## 実測値の確認

### テーブルサイズの確認

```sql
-- attachments テーブルのサイズ確認
SELECT
  pg_size_pretty(pg_total_relation_size('attachments')) as total_size,
  pg_size_pretty(pg_relation_size('attachments')) as table_size,
  pg_size_pretty(pg_indexes_size('attachments')) as indexes_size;
```

**期待される結果:**
- total_size: 約100MB（データ + インデックス）

### データ転送量の比較

```sql
-- SELECT * のデータ転送量（推定）
SELECT
  '100 records with BLOB' as query_type,
  pg_size_pretty(SUM(LENGTH(file_data))) as data_transferred
FROM (
  SELECT file_data
  FROM attachments
  LIMIT 100
) sub

UNION ALL

-- 必要なカラムのみのデータ転送量（推定）
SELECT
  '100 records without BLOB' as query_type,
  pg_size_pretty(
    COUNT(*) * (8 + 50 + 50 + 4 + 8)  -- 概算
  ) as data_transferred
FROM (
  SELECT id, filename, content_type, file_size, uploaded_at
  FROM attachments
  LIMIT 100
) sub;
```

**期待される結果:**
- BLOBあり: 約1MB
- BLOBなし: 約12KB
- **差: 約80倍**

---

## トレードオフ

### SELECT * を使うケース

- **開発/デバッグ時**: 一時的に全データを確認したい場合
- **レコード数が少ない**: 数件のみ取得する場合
- **全カラムが本当に必要**: ダウンロード機能など

### テーブル分離のデメリット

- **設計の複雑さ**: テーブル数が増える
- **JOINのコスト**: BLOB取得時にJOINが必要
- **トランザクション管理**: 複数テーブルへの挿入/削除が必要

---

## 次のステップ

### さらなる学習

1. **PostgreSQLのTOAST機能**
   - 大きなデータの自動圧縮・外部格納の仕組み
   - https://www.postgresql.org/docs/current/storage-toast.html

2. **オブジェクトストレージの活用**
   - S3やCloudStorageにBLOBを保存
   - DBにはURLやパスのみ保存（メタデータのみDB）

3. **ページング戦略**
   - カーソルベースのページング
   - オフセットベースの問題点

### 関連するテストケース

- **nested-loop-test**: JOINパフォーマンスの基礎
- **composite-index-test**: インデックス設計の最適化

---

## 参考資料

- [PostgreSQL: BYTEA型](https://www.postgresql.org/docs/current/datatype-binary.html)
- [PostgreSQL: TOAST (The Oversized-Attribute Storage Technique)](https://www.postgresql.org/docs/current/storage-toast.html)
- [Best Practices for Storing Binary Data in PostgreSQL](https://wiki.postgresql.org/wiki/BinaryFilesInDB)
