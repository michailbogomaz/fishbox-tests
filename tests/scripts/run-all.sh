#!/usr/bin/env bash

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "=========================================="
echo "RUNNING ALL TESTS"
echo "=========================================="
echo ""

echo "== catches-service =="
"$DIR/catches-service.cases.sh" run_all || true
echo ""

echo "== user-places-service =="
"$DIR/user-places-service.cases.sh" run_all || true
echo ""

echo "== user-uploads-service =="
"$DIR/user-uploads-service.cases.sh" run_all || true
echo ""

echo "== entity-files-service =="
"$DIR/entity-files-service.cases.sh" run_all || true
echo ""

echo "== users-service =="
"$DIR/users-service.cases.sh" run_all || true
echo ""

echo "== waterbody-service =="
"$DIR/waterbody-service.cases.sh" run_all || true
echo ""

echo "== photo-recognition-service =="
bash "$DIR/photo-recognition-service.cases.sh" run_all || true
echo ""

echo "=========================================="
echo "ALL TESTS COMPLETED"
echo "=========================================="
