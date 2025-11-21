#!/usr/bin/env bash

set -euo pipefail

# ===== Environment Configuration =====
ENV="${1:-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$ENV" != "dev" ] && [ "$ENV" != "prod" ]; then
  echo "Usage: $0 [dev|prod]" >&2
  # Load both env files to show API_GRAPHQL_URL
  if [ -f "$SCRIPT_DIR/../env.dev.sh" ]; then
    source "$SCRIPT_DIR/../env.dev.sh"
    echo "  dev  - $API_GRAPHQL_URL" >&2
  fi
  if [ -f "$SCRIPT_DIR/../env.prod.sh" ]; then
    source "$SCRIPT_DIR/../env.prod.sh"
    echo "  prod - $API_GRAPHQL_URL" >&2
  fi
  exit 1
fi

# Load environment-specific variables
ENV_FILE="$SCRIPT_DIR/../env.$ENV.sh"
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: Environment file not found: $ENV_FILE" >&2
  exit 1
fi
source "$ENV_FILE"

PASSED=0
FAILED=0

function log_test() {
  echo ">>> TEST: $1" >&2
}

function log_pass() {
  echo "✓ PASSED: $1" >&2
  ((PASSED++)) || true
}

function log_fail() {
  echo "✗ FAILED: $1" >&2
  ((FAILED++)) || true
}

function get_access_token() {
  if [[ -n "${ACCESS_TOKEN:-}" ]]; then
    echo "$ACCESS_TOKEN"
    return 0
  fi
  local token
  token=$(curl -s -X POST "$LOGIN_URL" \
    -H "Content-Type: application/json" \
    -H "client-id: ${CLIENT_ID}" \
    -d "{\"email\": \"${EMAIL}\", \"password\": \"${PASSWORD}\"}" | jq -r '.payload.access_token')
  if [[ -z "$token" || "$token" == "null" ]]; then
    echo "Failed to obtain ACCESS_TOKEN" >&2
    exit 1
  fi
  echo "$token"
}

function post_gql() {
  local payload="$1"
  local token
  token=$(get_access_token)
  curl -sS \
    --request POST \
    --url "$API_GRAPHQL_URL" \
    --header "Authorization: Bearer ${token}" \
    --header "Content-Type: application/json" \
    --header "User-Agent: insomnia/11.1.0" \
    --header "x-viewer-id: ${VIEWER_ID}" \
    --data "$payload"
}

# Placeholder: basic health/availability query via schema (adjust when exact operations known)
function test_schema_introspection_min() {
  log_test "Photo recognition: minimal introspection"
  local payload='{"query":"query __SchemaTypes { __schema { queryType { name } } }","operationName":"__SchemaTypes","variables":{}}'
  local result
  result=$(post_gql "$payload")
  if echo "$result" | jq -e '.data.__schema.queryType.name' > /dev/null 2>&1; then
    log_pass "Schema introspection works"
  else
    log_fail "Schema introspection failed"
    echo "$result" | jq .
    echo ""
  fi
}

function run_all() {
  echo "=========================================="
  echo "TESTING PHOTO-RECOGNITION-SERVICE"
  echo "=========================================="
  echo ""

  test_schema_introspection_min
  echo ""

  echo "=========================================="
  echo "RESULTS: PASSED=$PASSED, FAILED=$FAILED"
  echo "=========================================="

  if [[ $FAILED -gt 0 ]]; then
    exit 1
  fi
}

"${@:-run_all}"
