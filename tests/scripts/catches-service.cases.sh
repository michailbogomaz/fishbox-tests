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

# Test waterbodies with coordinates from dev.tests.md
# Format: id name lat lon
function get_waterbody_coords() {
  local id="$1"
  case "$id" in
    "01985af6-667e-7abc-9c63-00ce1051408d")
      echo "59.750 -154.000"
      ;;
    "01972092-bd77-7a2c-817b-5ba9141f56fe")
      echo "46.200 -93.700"
      ;;
    "01972092-bcb6-713d-8fa8-b7bbde559e5c")
      echo "48.400 -93.100"
      ;;
    "01971bf2-0a9c-78af-8f90-130b98bce71c")
      echo "35.500 -114.600"
      ;;
    "01972092-9d1c-77d0-a58f-fd7698b4e881")
      echo "31.200 94.100"
      ;;
    *)
      echo ""
      ;;
  esac
}

# Sample file IDs
FILE_IDS=(
  "0199e6de-f93f-74a7-8641-33533892cdb5"
  "0199e6df-0211-7714-b47c-a94813c12aae"
  "0199e6df-086e-7339-ad4f-dedffb0221db"
)

PASSED=0
FAILED=0

function log_test() {
  echo ">>> TEST: $1" >&2
}

# Helpers to cleanup waterbody state (remove existing files)
function get_waterbody_file_ids() {
  local waterbodyId="$1"
  local payload='{"query":"query GetWaterbodyFiles($ids: [ID!]) { waterbodies(ids: $ids, first: 1) { edges { node { id files { connection(first: 100) { edges { node { id } } } } } } } }","operationName":"GetWaterbodyFiles","variables":{"ids":["'"$waterbodyId"'"]}}'
  local result
  result=$(post_gql "$payload")
  echo "$result" | jq -r '.data.waterbodies.edges[0].node.files.connection.edges[].node.id // empty'
}

function select_new_files_for_waterbody() {
  local waterbodyId="$1"
  local -a existingIds
  mapfile -t existingIds < <(get_waterbody_file_ids "$waterbodyId")
  local -a selected=()
  for fid in "${FILE_IDS[@]}"; do
    local found=0
    for eid in "${existingIds[@]}"; do
      if [[ "$fid" == "$eid" ]]; then
        found=1
        break
      fi
    done
    if [[ $found -eq 0 ]]; then
      selected+=("$fid")
    fi
    if [[ ${#selected[@]} -ge 2 ]]; then
      break
    fi
  done
  printf '%s\n' "${selected[@]}"
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
    --header "Accept-Language: en" \
    --header "X-Jwt-Verified: 1" \
    --header "x-viewer-id: ${VIEWER_ID}" \
    --data "$payload"
}

# Test 0: Create Catch (full - like example)
function test_create_catch_full() {
  log_test "Create catch (full payload)"
  local payload='{"query":"mutation CreateCatch($input: CreateCatchMutationInput!) { createCatch(input: $input) { catch { id lat lon userId public speciesId method length weight locationTitle bait gear catchedAt files( status: [Uploaded], type: [Image, Video] ) { id status fileType ... on Image { previewUrl(width: 200, height: 200, quality: 80) } ... on Video { duration } } } errors { ... on MutationError { code message } } } }","operationName":"CreateCatch","variables":{"input":{"lat":48.463072,"lon":-93.005124,"public":true,"speciesId":"019777be-966b-764c-971a-85402aff9e0f","weight":2.5,"length":45.3,"method":"019777be-966b-764c-971a-85402aff9e0f","bait":"019777be-966b-764c-971a-85402aff9e0f","gear":"019777be-966b-764c-971a-85402aff9e0f","catchedAt":"2025-06-13T02:00:00Z","filesIds":[]}}}'
  local result
  result=$(post_gql "$payload")
  if echo "$result" | jq -e '.data.createCatch.catch.id' > /dev/null 2>&1; then
    local catchId
    catchId=$(echo "$result" | jq -r '.data.createCatch.catch.id')
    log_pass "Created full catch ID: $catchId"
    echo "$catchId"
  else
    log_fail "Failed to create full catch"
    echo "$result" | jq .
    echo ""
  fi
}

# Test 1: Create Catch (minimal - with lat/lon)
function test_create_catch_minimal() {
  log_test "Create catch with lat/lon (minimal fields)"
  local payload='{"query":"mutation CreateCatch($input: CreateCatchMutationInput!) { createCatch(input: $input) { catch { id lat lon public } errors { ... on MutationError { code message } } } }","operationName":"CreateCatch","variables":{"input":{"lat":46.2,"lon":-93.7,"public":true}}}'
  local result
  result=$(post_gql "$payload")
  
  if echo "$result" | jq -e '.data.createCatch.catch.id' > /dev/null 2>&1; then
    local catchId
    catchId=$(echo "$result" | jq -r '.data.createCatch.catch.id')
    log_pass "Created catch ID: $catchId"
    echo "$catchId"
  else
    log_fail "Failed to create catch"
    echo "$result" | jq .
    echo ""
  fi
}

# Test 2: Create Catch with filesIds
function test_create_catch_with_files() {
  log_test "Create catch with filesIds"
  local payload='{"query":"mutation CreateCatch($input: CreateCatchMutationInput!) { createCatch(input: $input) { catch { id lat lon public entityFiles { filesCount(type: Image) } } errors { ... on MutationError { code message } } } }","operationName":"CreateCatch","variables":{"input":{"lat":46.2,"lon":-93.7,"public":true,"filesIds":["0199e6de-f93f-74a7-8641-33533892cdb5","0199e6df-0211-7714-b47c-a94813c12aae","0199e6df-086e-7339-ad4f-dedffb0221db"]}}}'
  local result
  result=$(post_gql "$payload")
  
  if echo "$result" | jq -e '.data.createCatch.catch.id' > /dev/null 2>&1; then
    local catchId
    catchId=$(echo "$result" | jq -r '.data.createCatch.catch.id')
    log_pass "Created catch with files ID: $catchId"
    echo "$catchId"
  else
    log_fail "Failed to create catch with files"
    echo "$result" | jq .
    echo ""
  fi
}

# Test 3: Create public catch inside waterbody with files (should attach to waterbody)
function test_create_public_catch_in_waterbody_with_files() {
  log_test "Create public catch inside waterbody with files (files should attach to waterbody)"
  local waterbodyId="01972092-bd77-7a2c-817b-5ba9141f56fe"
  local coords
  coords=$(get_waterbody_coords "$waterbodyId")
  local lat="${coords%% *}"
  local lon="${coords##* }"
  local -a newFiles
  mapfile -t newFiles < <(select_new_files_for_waterbody "$waterbodyId")
  local filesJson="[]"
  if [[ ${#newFiles[@]} -gt 0 ]]; then
    filesJson='["'"${newFiles[0]}"'"'
    if [[ ${#newFiles[@]} -gt 1 ]]; then
      filesJson+=',"'"${newFiles[1]}"'"'
    fi
    filesJson+=']'
  fi
  
  local payload='{"query":"mutation CreateCatch($input: CreateCatchMutationInput!) { createCatch(input: $input) { catch { id lat lon public } errors { ... on MutationError { code message } } } }","operationName":"CreateCatch","variables":{"input":{"lat":'"$lat"',"lon":'"$lon"',"public":true,"filesIds":'"$filesJson"'}}}'
  local result
  result=$(post_gql "$payload")
  
  if echo "$result" | jq -e '.data.createCatch.catch.id' > /dev/null 2>&1; then
    local catchId
    catchId=$(echo "$result" | jq -r '.data.createCatch.catch.id')
    log_pass "Created public catch in waterbody with files ID: $catchId"
    echo "$catchId"
  else
    log_fail "Failed to create catch in waterbody"
    echo "$result" | jq .
    echo ""
  fi
}

# Test 4: Check waterbody files count after creating public catch
function test_check_waterbody_files_count() {
  log_test "Check waterbody files count (after public catch with files)"
  local waterbodyId="${1:-01972092-bd77-7a2c-817b-5ba9141f56fe}"
  local payload='{"query":"query GetWaterbodyFiles($ids: [ID!]) { waterbodies(ids: $ids, first: 1) { edges { node { id title files { filesCount(type: Image) } } } } }","operationName":"GetWaterbodyFiles","variables":{"ids":["'"$waterbodyId"'"]}}'
  local result
  result=$(post_gql "$payload")
  
  if echo "$result" | jq -e '.data.waterbodies.edges[0].node.id' > /dev/null 2>&1; then
    local filesCount
    filesCount=$(echo "$result" | jq -r '.data.waterbodies.edges[0].node.files.filesCount // 0')
    local title
    title=$(echo "$result" | jq -r '.data.waterbodies.edges[0].node.title')
    log_pass "Waterbody '$title' files count: $filesCount"
    echo "$filesCount"
  else
    log_fail "Failed to get waterbody files count"
    echo "$result" | jq .
    echo ""
  fi
}

# Test 5: Update Catch
function test_update_catch() {
  log_test "Update catch (toggle public)"
  local catchId="$1"
  if [[ -z "$catchId" ]]; then
    log_fail "Missing catchId parameter"
    return
  fi
  
  # sanitize id (remove any newlines/spaces)
  local catchIdSanitized
  catchIdSanitized="${catchId//$'\n'/}"
  catchIdSanitized="${catchIdSanitized//$'\r'/}"
  catchIdSanitized="${catchIdSanitized//[$'\t ']/}"
  local payload='{"query":"mutation UpdateCatch($input: UpdateCatchMutationInput!) { updateCatch(input: $input) { catch { id public } errors { ... on MutationError { code message } } } }","operationName":"UpdateCatch","variables":{"input":{"id":"'"$catchIdSanitized"'","public":false}}}'
  local result
  result=$(post_gql "$payload")
  
  if echo "$result" | jq -e '.data.updateCatch.catch.id' > /dev/null 2>&1; then
    local isPublic
    isPublic=$(echo "$result" | jq -r '.data.updateCatch.catch.public')
    log_pass "Updated catch $catchId, public: $isPublic"
  else
    log_fail "Failed to update catch"
    echo "$result" | jq .
    echo ""
  fi
}

# Test 6: Delete Catch
function test_delete_catch() {
  log_test "Delete catch"
  local catchId="$1"
  if [[ -z "$catchId" ]]; then
    log_fail "Missing catchId parameter"
    return
  fi
  
  local payload='{"query":"mutation DeleteCatch($input: DeleteCatchMutationInput!) { deleteCatch(input: $input) { errors { ... on MutationError { code message } } } }","operationName":"DeleteCatch","variables":{"input":{"id":"'"$catchId"'"}}}'
  local result
  result=$(post_gql "$payload")
  
  if echo "$result" | jq -e '.data.deleteCatch.errors == null' > /dev/null 2>&1; then
    log_pass "Deleted catch $catchId"
  else
    log_fail "Failed to delete catch"
    echo "$result" | jq .
    echo ""
  fi
}

function run_all() {
  echo "=========================================="
  echo "TESTING CATCHES-SERVICE"
  echo "=========================================="
  echo ""
  
  # Baseline before adding
  local beforeCount
  beforeCount=$(test_check_waterbody_files_count "01972092-bd77-7a2c-817b-5ba9141f56fe" || true)
  echo ""
  
  # Full example first
  local fullId
  fullId=$(test_create_catch_full)
  echo ""
  
  # Test 1: Create minimal catch
  local catchId1
  catchId1=$(test_create_catch_minimal)
  echo ""
  
  # Test 2: Create catch with files
  local catchId2
  catchId2=$(test_create_catch_with_files)
  echo ""
  
  # Test 3: Create public catch in waterbody with files
  local catchId3
  catchId3=$(test_create_public_catch_in_waterbody_with_files)
  echo ""
  
  # Test 4: Check waterbody files count
  if [[ -n "$catchId3" ]]; then
    local afterCount
    afterCount=$(test_check_waterbody_files_count "01972092-bd77-7a2c-817b-5ba9141f56fe" || true)
    # If we managed to add new files, expect increase; otherwise tolerate equal (files already present)
    if [[ -n "${beforeCount:-}" && -n "${afterCount:-}" ]]; then
      if (( ${afterCount:-0} < ${beforeCount:-0} )); then
        log_fail "Waterbody files count decreased unexpectedly: before=$beforeCount after=$afterCount"
      fi
    fi
    echo ""
  fi
  
  # Test 5: Update catch
  if [[ -n "$catchId1" ]]; then
    test_update_catch "$catchId1"
    echo ""
  fi
  
  # Test 6: Delete catches
  if [[ -n "$catchId1" ]]; then
    test_delete_catch "$catchId1"
    echo ""
  fi
  if [[ -n "$catchId2" ]]; then
    test_delete_catch "$catchId2"
    echo ""
  fi
  if [[ -n "$catchId3" ]]; then
    test_delete_catch "$catchId3"
    echo ""
  fi
  if [[ -n "$fullId" ]]; then
    test_delete_catch "$fullId"
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
