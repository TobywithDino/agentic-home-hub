# -*- coding: utf-8 -*-
"""
建置執行工具：依 README.pdf 建議順序，對 PostgreSQL 資料庫執行
database 資料夾內的建表 DDL，並匯入所有種子/範例資料 JSON。

用途：
- 本地測試環境（Docker PostgreSQL）一鍵建置
- 未來遷移 AWS RDS for PostgreSQL 時，同一腳本改連線參數即可重複使用

用法：
    python import_seed_data.py --host localhost --port 5432 \
        --dbname aiwave --user postgres --password <PASSWORD>

    或透過環境變數：
    PGHOST / PGPORT / PGDATABASE / PGUSER / PGPASSWORD
    （不帶密碼於 command line，避免留在 shell history）

注意事項：
1. 需先安裝相依套件：pip install psycopg2-binary
2. 此腳本會直接對指定資料庫執行 DDL（CREATE TABLE）與 DML（INSERT），
   建議只在全新/測試用資料庫執行，避免與現有 schema 衝突。
3. AES-256-GCM 加密欄位（member_name/contact_name 等 bytea 欄位）於範例
   JSON 中已是密文格式，本腳本會盡力還原成原始 bytes 寫入 bytea 欄位；
   若字串包含超出可還原範圍的字元（來源匯出瑕疵），會改寫入 NULL，
   不會中斷整體匯入流程。這些欄位在沒有對應加解密金鑰的情況下，
   本就無法在本地驗證解密正確性，僅供欄位格式參考。
"""
import argparse
import json
import os
import sys

import psycopg2

# ---------------------------------------------------------------------------
# 建置順序設定（對應 README.pdf 「資料寫入順序（建議）」章節）
# ---------------------------------------------------------------------------

# Step 1：建表 DDL，依外鍵依賴順序排列
DDL_FILES = [
    "縣市區域檔.sql",                # sys_county, sys_district
    "cms_homepage_service.sql",      # cms_homepage_service_vendor, cms_homepage_service（補建，README缺漏)
    "account_and_label.sql",         # label, service_label, vendor_accounts, user_accounts（新增)
    "諮詢單相關table.sql",           # pms_form 系列
    "mms_order_record.sql",          # mms_order_record
    "mms_order_review.sql",          # mms_order_review（訂單評價單，新增）
]

# Step 2：主檔種子資料（依 README 建議順序 + 新增表插入正確位置）
SEED_FILES_STEP2 = [
    "縣市區域範例資料.json",
    "相關主檔設定.json",
    "帳號與標籤範例資料.json",
    "諮詢單相關範例資料.json",
]

# Step 3：交易資料
SEED_FILES_STEP3 = [
    "order_record範例資料.json",
    "order_review範例資料.json",     # mms_order_review（訂單評價單種子資料，依賴訂單先存在）
]

# bytea 欄位：JSON 範例資料以逐byte映射字串(latin-1)表示加密二進位內容
BYTEA_COLUMNS = {
    "member_name", "member_phone", "member_email",
    "contact_name", "contact_mobile", "contact_landline",
    "contact_email", "contact_address_detail",
}

# 使用 serial4/bigserial 主鍵、且種子資料以「明確指定id值」寫入的表格。
# PostgreSQL 用顯式值 INSERT 不會自動同步內部序列(sequence)，
# 若不手動校正，之後透過 API 新增資料（不帶id，交由序列自動產生）
# 會產生與既有種子資料id衝突的 UniqueViolation 錯誤。
# 格式："資料表名": "主鍵欄位名"
SERIAL_PK_TABLES = {
    "label": "id",
    "pms_form": "id",
    "pms_form_group": "id",
    "pms_form_topic": "id",
    "pms_topic_media": "id",
    "pms_topic_option": "id",
    "mms_order_record": "record_id",
}


def split_top_level_json_objects(content):
    """依大括號深度切分檔案內多個獨立 JSON 物件（正確處理字串內的引號/轉義字元）。"""
    objs = []
    depth = 0
    start = None
    in_string = False
    escape = False
    for i, ch in enumerate(content):
        if in_string:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_string = False
            continue
        if ch == '"':
            in_string = True
        elif ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start is not None:
                objs.append(content[start:i + 1])
                start = None
    return objs


def load_json_tables(path):
    with open(path, encoding="utf-8") as f:
        content = f.read()
    result = {}
    for block in split_top_level_json_objects(content):
        result.update(json.loads(block))
    return result


def insert_rows(cur, table, rows):
    if not rows:
        return 0
    cols = list(rows[0].keys())
    col_list = ", ".join(f'"{c}"' for c in cols)
    placeholders = ", ".join(["%s"] * len(cols))
    sql = f'INSERT INTO "{table}" ({col_list}) VALUES ({placeholders})'
    count = 0
    for row in rows:
        values = []
        for c in cols:
            v = row[c]
            if v is not None and c in BYTEA_COLUMNS:
                try:
                    v = psycopg2.Binary(v.encode("latin-1"))
                except UnicodeEncodeError:
                    v = None
            values.append(v)
        cur.execute(sql, values)
        count += 1
    return count


def run_ddl(cur, conn, base_dir, filename):
    path = os.path.join(base_dir, filename)
    with open(path, encoding="utf-8") as f:
        sql = f.read()
    try:
        cur.execute(sql)
        conn.commit()
        print(f"[DDL OK]   {filename}")
    except Exception as e:
        conn.rollback()
        print(f"[DDL FAIL] {filename}: {e}")
        raise


def sync_serial_sequences(cur, conn):
    """校正 serial/bigserial 主鍵表格的內部序列，避免種子資料以顯式id寫入後，
    序列仍停在初始值，導致之後應用程式端新增資料時id衝突。"""
    for table, pk_col in SERIAL_PK_TABLES.items():
        try:
            cur.execute(
                f"SELECT setval(pg_get_serial_sequence('{table}', '{pk_col}'), "
                f"COALESCE((SELECT MAX(\"{pk_col}\") FROM \"{table}\"), 1), "
                f"(SELECT MAX(\"{pk_col}\") FROM \"{table}\") IS NOT NULL)"
            )
            conn.commit()
            print(f"[SEQ OK]   {table}.{pk_col} 序列已同步")
        except Exception as e:
            conn.rollback()
            print(f"[SEQ FAIL] {table}.{pk_col}: {e}")
            raise


def run_seed(cur, conn, base_dir, filename):
    path = os.path.join(base_dir, filename)
    data = load_json_tables(path)
    for table, rows in data.items():
        try:
            n = insert_rows(cur, table, rows)
            conn.commit()
            print(f"[SEED OK]  {filename} -> {table}: {n} rows")
        except Exception as e:
            conn.rollback()
            print(f"[SEED FAIL] {filename} -> {table}: {e}")
            raise


def main():
    parser = argparse.ArgumentParser(description="建置資料庫並匯入種子資料")
    parser.add_argument("--host", default=os.environ.get("PGHOST", "localhost"))
    parser.add_argument("--port", default=os.environ.get("PGPORT", "5432"))
    parser.add_argument("--dbname", default=os.environ.get("PGDATABASE", "postgres"))
    parser.add_argument("--user", default=os.environ.get("PGUSER", "postgres"))
    parser.add_argument("--password", default=os.environ.get("PGPASSWORD"))
    parser.add_argument("--sslmode", default=os.environ.get("PGSSLMODE", "prefer"),
                         help="本地測試用 disable/prefer；連線 AWS RDS 建議用 require")
    args = parser.parse_args()

    if not args.password:
        print("錯誤：未提供資料庫密碼，請用 --password 或設定 PGPASSWORD 環境變數。", file=sys.stderr)
        sys.exit(1)

    base_dir = os.path.dirname(os.path.abspath(__file__))

    conn = psycopg2.connect(
        host=args.host, port=args.port, dbname=args.dbname,
        user=args.user, password=args.password, sslmode=args.sslmode,
    )
    conn.autocommit = False
    cur = conn.cursor()

    print("=== Step 1: 建表 (DDL) ===")
    for f in DDL_FILES:
        run_ddl(cur, conn, base_dir, f)

    print("\n=== Step 2: 匯入主檔種子資料 ===")
    for f in SEED_FILES_STEP2:
        run_seed(cur, conn, base_dir, f)

    print("\n=== Step 3: 匯入交易資料 ===")
    for f in SEED_FILES_STEP3:
        run_seed(cur, conn, base_dir, f)

    print("\n=== Step 4: 同步 serial 主鍵序列 ===")
    sync_serial_sequences(cur, conn)

    cur.close()
    conn.close()
    print("\n建置完成，無錯誤。")


if __name__ == "__main__":
    main()
