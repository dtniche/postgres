#!/usr/bin/env python3
"""
Oracle ALL_* visibility probe

Goals:
- Determine which privileges cause tables to appear in ALL_TABLES for the current session
- Inspect privileges sources: direct grants, PUBLIC grants, role grants, system privileges (e.g., SELECT ANY TABLE)

Connection parameters mirror oracle_field_analysis.py
"""

import cx_Oracle
from datetime import datetime


def connect_oracle():
    dsn = cx_Oracle.makedsn('172.23.160.1', 1521, service_name='XEPDB1')
    return cx_Oracle.connect('sys', '111111', dsn, mode=cx_Oracle.SYSDBA)


def fetchall(cur, sql, params=None):
    cur.execute(sql, params or {})
    cols = [d[0] for d in cur.description]
    return cols, cur.fetchall()


def main():
    print('=== Oracle ALL_* visibility probe ===')
    conn = connect_oracle()
    cur = conn.cursor()

    # Session basics
    cols, rows = fetchall(cur, "SELECT USER FROM dual")
    session_user = rows[0][0]
    print(f"Session user: {session_user}")

    # Session roles and privileges
    _, session_roles = fetchall(cur, "SELECT role FROM session_roles ORDER BY role")
    _, session_privs = fetchall(cur, "SELECT privilege FROM session_privs ORDER BY privilege")
    role_list = [r[0] for r in session_roles]
    priv_list = [p[0] for p in session_privs]
    print(f"Enabled roles ({len(role_list)}): {', '.join(role_list) if role_list else '(none)'}")
    key_sys_privs = [
        'SELECT ANY TABLE', 'INSERT ANY TABLE', 'UPDATE ANY TABLE', 'DELETE ANY TABLE',
        'READ ANY TABLE', 'ALTER ANY TABLE', 'REFERENCES ANY TABLE'
    ]
    held_key_privs = [p for p in key_sys_privs if p in priv_list]
    print(f"Key system privileges held: {', '.join(held_key_privs) if held_key_privs else '(none)'}")

    # Count own vs others in ALL_TABLES
    sql_counts = (
        "SELECT SUM(CASE WHEN owner = USER THEN 1 ELSE 0 END) own_tables, "
        "       SUM(CASE WHEN owner <> USER THEN 1 ELSE 0 END) others_tables "
        "FROM all_tables"
    )
    _, counts = fetchall(cur, sql_counts)
    print(f"ALL_TABLES counts: own={counts[0][0]} others={counts[0][1]}")

    # Inspect sample of rows owned by others, with privilege sources
    sql_sample = f"""
    WITH roles AS (
      SELECT role FROM session_roles
    ),
    sys_priv AS (
      SELECT privilege FROM session_privs
      WHERE privilege IN ('SELECT ANY TABLE','INSERT ANY TABLE','UPDATE ANY TABLE','DELETE ANY TABLE','READ ANY TABLE','REFERENCES ANY TABLE')
    )
    SELECT /*+ gather_plan_statistics */
      t.owner,
      t.table_name,
      LISTAGG(DISTINCT atp.privilege, ',') WITHIN GROUP (ORDER BY atp.privilege) AS obj_privs,
      MAX(CASE WHEN atp.grantee = USER THEN 1 ELSE 0 END) AS direct_grant,
      MAX(CASE WHEN atp.grantee = 'PUBLIC' THEN 1 ELSE 0 END) AS public_grant,
      MAX(CASE WHEN atp.grantee IN (SELECT role FROM roles) THEN 1 ELSE 0 END) AS via_role,
      MAX(CASE WHEN sp.privilege IS NOT NULL THEN 1 ELSE 0 END) AS has_sys_any
    FROM all_tables t
    LEFT JOIN all_tab_privs atp
      ON atp.owner = t.owner AND atp.table_name = t.table_name
    LEFT JOIN sys_priv sp
      ON 1=1
    WHERE t.owner <> USER
    GROUP BY t.owner, t.table_name
    ORDER BY t.owner, t.table_name FETCH FIRST 50 ROWS ONLY
    """
    cols, rows = fetchall(cur, sql_sample)
    print("\nSample ALL_TABLES visibility (others' tables):")
    print("owner | table_name | obj_privs | direct | public | via_role | sys_any")
    for r in rows:
        owner, table_name, obj_privs, direct, public, via_role, sys_any = r
        print(f"{owner} | {table_name} | {obj_privs or ''} | {direct} | {public} | {via_role} | {sys_any}")

    # Check ALL_COL_PRIVS similarly (first 50)
    sql_cols = """
    WITH roles AS (SELECT role FROM session_roles)
    SELECT owner, table_name, column_name,
           LISTAGG(DISTINCT privilege, ',') WITHIN GROUP (ORDER BY privilege) AS col_privs,
           MAX(CASE WHEN grantee = USER THEN 1 ELSE 0 END) AS direct_grant,
           MAX(CASE WHEN grantee = 'PUBLIC' THEN 1 ELSE 0 END) AS public_grant,
           MAX(CASE WHEN grantee IN (SELECT role FROM roles) THEN 1 ELSE 0 END) AS via_role
    FROM all_col_privs
    WHERE owner <> USER
    GROUP BY owner, table_name, column_name
    ORDER BY owner, table_name, column_name FETCH FIRST 50 ROWS ONLY
    """
    cols, rows = fetchall(cur, sql_cols)
    print("\nSample ALL_COL_PRIVS visibility (others' columns):")
    print("owner | table_name | column_name | col_privs | direct | public | via_role")
    for r in rows:
        owner, table_name, column_name, col_privs, direct, public, via_role = r
        print(f"{owner} | {table_name} | {column_name} | {col_privs or ''} | {direct} | {public} | {via_role}")

    # Heuristics summary
    print("\nHeuristic summary:")
    print("- Tables in ALL_TABLES owned by others typically appear if:")
    print("  (a) you hold object privileges on the table (direct/PUBLIC/role), and/or")
    print("  (b) you hold system privileges like SELECT ANY TABLE.")
    print("- Columns in ALL_COL_PRIVS reflect object column privileges (direct/PUBLIC/role).")

    cur.close()
    conn.close()
    print("\nDone.")


if __name__ == '__main__':
    main()


