#!/bin/bash
set -euo pipefail

DB_NAME=${PGDATABASE:-postgres}

echo "Running PostgreSQL OR expansion -> decorrelation demo on database: $DB_NAME"
psql "$DB_NAME" -f src/test/optimize/pg_or_expand_then_decorrelate.sql | cat

echo "Done. Review the EXPLAIN outputs above."







