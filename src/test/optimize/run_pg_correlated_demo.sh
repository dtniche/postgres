#!/bin/bash
set -euo pipefail

DB_NAME=${PGDATABASE:-postgres}

echo "Running PostgreSQL correlated subquery decorrelation demo on database: $DB_NAME"
psql "$DB_NAME" -f src/test/optimize/pg_correlated_subquery_decorrelation.sql | cat

echo "Done. Review the EXPLAIN outputs above."


