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

WATERBODY_ID_SAMPLE="01972092-bd77-7a2c-817b-5ba9141f56fe"

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

# Test 1: Query waterbody by id
function test_query_waterbody_by_id() {
  log_test "Query waterbody by id"
  local payload='{"query":"query GetWaterbody($ids: [ID!]) { waterbodies(ids: $ids, first: 1) { edges { node { id title type locationTitle files { filesCount(type: Image) } } } } }","operationName":"GetWaterbody","variables":{"ids":["'"$WATERBODY_ID_SAMPLE"'"]}}'
  local result
  result=$(post_gql "$payload")
  
  if echo "$result" | jq -e '.data.waterbodies.edges[0].node.id' > /dev/null 2>&1; then
    local title
    title=$(echo "$result" | jq -r '.data.waterbodies.edges[0].node.title')
    local filesCount
    filesCount=$(echo "$result" | jq -r '.data.waterbodies.edges[0].node.files.filesCount // 0')
    log_pass "Got waterbody '$title' with $filesCount image files"
  else
    log_fail "Failed to get waterbody by id"
    echo "$result" | jq .
    echo ""
  fi
}

# Test 2: Query waterbodies connection (list)
function test_query_waterbodies_connection() {
  log_test "Query waterbodies connection (first 5)"
  local payload='{"query":"query Waterbodies { waterbodies(first: 5) { edges { node { id title type } } pageInfo { hasNextPage endCursor } } }","operationName":"Waterbodies","variables":{}}'
  local result
  result=$(post_gql "$payload")
  
  if echo "$result" | jq -e '.data.waterbodies.edges' > /dev/null 2>&1; then
    local count
    count=$(echo "$result" | jq -r '.data.waterbodies.edges | length')
    local hasNext
    hasNext=$(echo "$result" | jq -r '.data.waterbodies.pageInfo.hasNextPage')
    log_pass "Got $count waterbodies, hasNextPage: $hasNext"
  else
    log_fail "Failed to get waterbodies connection"
    echo "$result" | jq .
    echo ""
  fi
}

# Test 3: Query waterbody files connection
function test_query_waterbody_files_connection() {
  log_test "Query waterbody files connection"
  local payload='{"query":"query GetWaterbodyFiles($ids: [ID!]) { waterbodies(ids: $ids, first: 1) { edges { node { id title files { filesCount(type: Image) connection(first: 10) { edges { node { id } } pageInfo { hasNextPage } } } } } } }","operationName":"GetWaterbodyFiles","variables":{"ids":["'"$WATERBODY_ID_SAMPLE"'"]}}'
  local result
  result=$(post_gql "$payload")
  
  if echo "$result" | jq -e '.data.waterbodies.edges[0].node.files.connection' > /dev/null 2>&1; then
    local filesCount
    filesCount=$(echo "$result" | jq -r '.data.waterbodies.edges[0].node.files.filesCount // 0')
    local edgesCount
    edgesCount=$(echo "$result" | jq -r '.data.waterbodies.edges[0].node.files.connection.edges | length')
    log_pass "Waterbody files count: $filesCount, connection edges: $edgesCount"
  else
    log_fail "Failed to get waterbody files connection"
    echo "$result" | jq .
    echo ""
  fi
}

function run_all() {
  echo "=========================================="
  echo "TESTING WATERBODY-SERVICE"
  echo "=========================================="
  echo ""
  
  # Test 1: Query waterbody by id
  test_query_waterbody_by_id
  echo ""
  
  # Test 2: Query waterbodies connection
  test_query_waterbodies_connection
  echo ""
  
  # Test 3: Query waterbody files connection
  test_query_waterbody_files_connection
  echo ""
  
  echo "=========================================="
  echo "RESULTS: PASSED=$PASSED, FAILED=$FAILED"
  echo "=========================================="
  
  if [[ $FAILED -gt 0 ]]; then
    exit 1
  fi
}

"${@:-run_all}"
