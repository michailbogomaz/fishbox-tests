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

WATERBODY_ID_SAMPLE="01985af6-667e-7abc-9c63-00ce1051408d"
FILE_IDS=(
  "0199e6de-f93f-74a7-8641-33533892cdb5"
  "0199e6df-0211-7714-b47c-a94813c12aae"
)

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

# Test 1: Add files to waterbody
function test_add_files_to_waterbody() {
  log_test "Add files to waterbody"
  local fileIdsJson='["'"${FILE_IDS[0]}"'","'"${FILE_IDS[1]}"'"]'
  local payload='{"query":"mutation AddFilesToWaterbody($input: AddFilesToWaterbodyMutationInput!) { addFilesToWaterbody(input: $input) { errors { ... on MutationError { code message } } } }","operationName":"AddFilesToWaterbody","variables":{"input":{"id":"'"$WATERBODY_ID_SAMPLE"'","fileIds":'"$fileIdsJson"'}}}'
  local result
  result=$(post_gql "$payload")
  
  if echo "$result" | jq -e '.data.addFilesToWaterbody.errors == null' > /dev/null 2>&1; then
    log_pass "Added files to waterbody $WATERBODY_ID_SAMPLE"
  else
    log_fail "Failed to add files to waterbody"
    echo "$result" | jq .
    echo ""
  fi
}

# Test 2: Check waterbody files count after adding files
function test_check_waterbody_files_count_after_add() {
  log_test "Check waterbody files count after adding files"
  local waterbodyId="${1:-$WATERBODY_ID_SAMPLE}"
  
  local payload='{"query":"query GetWaterbodyFiles($ids: [ID!]) { waterbodies(ids: $ids, first: 1) { edges { node { id title files { filesCount(type: Image) connection(first: 5) { edges { node { id } } } } } } } }","operationName":"GetWaterbodyFiles","variables":{"ids":["'"$waterbodyId"'"]}}'
  local result
  result=$(post_gql "$payload")
  
  if echo "$result" | jq -e '.data.waterbodies.edges[0].node.id' > /dev/null 2>&1; then
    local filesCount
    filesCount=$(echo "$result" | jq -r '.data.waterbodies.edges[0].node.files.filesCount // 0')
    local title
    title=$(echo "$result" | jq -r '.data.waterbodies.edges[0].node.title')
    local edgesCount
    edgesCount=$(echo "$result" | jq -r '.data.waterbodies.edges[0].node.files.connection.edges | length')
    log_pass "Waterbody '$title' files count: $filesCount, connection edges: $edgesCount"
  else
    log_fail "Failed to get waterbody files count"
    echo "$result" | jq .
    echo ""
  fi
}

function run_all() {
  echo "=========================================="
  echo "TESTING ENTITY-FILES-SERVICE"
  echo "=========================================="
  echo ""
  
  # Test 1: Add files to waterbody
  test_add_files_to_waterbody
  echo ""
  
  # Test 2: Check files count
  test_check_waterbody_files_count_after_add
  echo ""
  
  echo "=========================================="
  echo "RESULTS: PASSED=$PASSED, FAILED=$FAILED"
  echo "=========================================="
  
  if [[ $FAILED -gt 0 ]]; then
    exit 1
  fi
}

"${@:-run_all}"
