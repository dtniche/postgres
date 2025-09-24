#!/bin/bash
set -euo pipefail

ORACLE_CONN=${ORACLE_CONN:-"sys/111111@172.23.160.1:1521/XEPDB1 as sysdba"}

echo "Running Oracle correlated subquery unnesting demo on: $ORACLE_CONN"
sqlplus -s "$ORACLE_CONN" @src/test/optimize/oracle_correlated_subquery_unnesting.sql | cat

echo "Done. Review the DBMS_XPLAN outputs above."


