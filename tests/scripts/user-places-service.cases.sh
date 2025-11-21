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

# Test 1: Create User Place
function test_create_user_place() {
  log_test "Create user place"
  local payload='{"query":"mutation CreateUserPlace($input: CreateUserPlaceMutationInput!) { createUserPlace(input: $input) { userPlace { id name lat lon public } errors { ... on MutationError { code message } } } }","operationName":"CreateUserPlace","variables":{"input":{"name":"My Secret Spot","lat":46.2,"lon":-93.7,"public":true}}}'
  local result
  result=$(post_gql "$payload")
  
  if echo "$result" | jq -e '.data.createUserPlace.userPlace.id' > /dev/null 2>&1; then
    local placeId
    placeId=$(echo "$result" | jq -r '.data.createUserPlace.userPlace.id')
    log_pass "Created user place ID: $placeId"
    echo "$placeId"
  else
    log_fail "Failed to create user place"
    echo "$result" | jq .
    echo ""
  fi
}

# Test 2: Update User Place
function test_update_user_place() {
  log_test "Update user place"
  local placeId="$1"
  if [[ -z "$placeId" ]]; then
    log_fail "Missing placeId parameter"
    return
  fi
  
  local payload='{"query":"mutation UpdateUserPlace($input: UpdateUserPlaceMutationInput!) { updateUserPlace(input: $input) { userPlace { id name } errors { ... on MutationError { code message } } } }","operationName":"UpdateUserPlace","variables":{"input":{"id":"'"$placeId"'","name":"Renamed Place"}}}'
  local result
  result=$(post_gql "$payload")
  
  if echo "$result" | jq -e '.data.updateUserPlace.userPlace.id' > /dev/null 2>&1; then
    local name
    name=$(echo "$result" | jq -r '.data.updateUserPlace.userPlace.name')
    log_pass "Updated user place $placeId, name: $name"
  else
    log_fail "Failed to update user place"
    echo "$result" | jq .
    echo ""
  fi
}

# Test 3: Delete User Place
function test_delete_user_place() {
  log_test "Delete user place"
  local placeId="$1"
  if [[ -z "$placeId" ]]; then
    log_fail "Missing placeId parameter"
    return
  fi
  
  local payload='{"query":"mutation DeleteUserPlace($input: DeleteUserPlaceMutationInput!) { deleteUserPlace(input: $input) { errors { ... on MutationError { code message } } } }","operationName":"DeleteUserPlace","variables":{"input":{"id":"'"$placeId"'"}}}'
  local result
  result=$(post_gql "$payload")
  
  if echo "$result" | jq -e '.data.deleteUserPlace.errors == null' > /dev/null 2>&1; then
    log_pass "Deleted user place $placeId"
  else
    log_fail "Failed to delete user place"
    echo "$result" | jq .
    echo ""
  fi
}

function run_all() {
  echo "=========================================="
  echo "TESTING USER-PLACES-SERVICE"
  echo "=========================================="
  echo ""
  
  # Test 1: Create user place
  local placeId
  placeId=$(test_create_user_place)
  echo ""
  
  # Test 2: Update user place
  if [[ -n "$placeId" ]]; then
    test_update_user_place "$placeId"
    echo ""
  fi
  
  # Test 3: Delete user place
  if [[ -n "$placeId" ]]; then
    test_delete_user_place "$placeId"
    echo ""
  fi
  
  echo "=========================================="
  echo "RESULTS: PASSED=$PASSED, FAILED=$FAILED"
  echo "=========================================="
  
  if [[ $FAILED -gt 0 ]]; then
    exit 1
  fi
}

"${@:-run_all}"
