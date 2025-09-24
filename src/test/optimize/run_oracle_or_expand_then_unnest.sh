#!/bin/bash
set -euo pipefail

ORACLE_CONN=${ORACLE_CONN:-"sys/111111@172.23.160.1:1521/XEPDB1 as sysdba"}

echo "Running Oracle OR expansion -> unnest demo on: $ORACLE_CONN"
sqlplus -s "$ORACLE_CONN" @src/test/optimize/oracle_or_expand_then_unnest.sql | cat

echo "Done. Review the DBMS_XPLAN outputs above."


