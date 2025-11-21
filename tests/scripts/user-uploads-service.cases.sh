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

FILE_NAME="fish173.jpeg"
FILE_TYPE="image/jpeg"
FILE_SIZE=522095
IMAGE_WIDTH=560
IMAGE_HEIGHT=854
FILE_HASH="M1rtl5oLjoBumqsRtRTNPywXDrJuPG//OgYuxZdh0AI="

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

# Test 1: Create Image Upload Intent
function test_create_image_upload_intent() {
  log_test "Create image upload intent (intent: catch.create)"
  local payload='{"query":"mutation CreateImageUploadIntentMutation($input: CreateImageUploadIntentMutationInput!) { createImageUploadIntent(input: $input) { presignedForm { fields formActionUrl expires } image { id previewUrl(width: 200, height: 200, quality: 85) } errors { ... on MutationError { code message } } } }","operationName":"CreateImageUploadIntentMutation","variables":{"input":{"fileName":"'"$FILE_NAME"'","fileMimeType":"'"$FILE_TYPE"'","fileSize":'"$FILE_SIZE"',"imageWidth":'"$IMAGE_WIDTH"',"imageHeight":'"$IMAGE_HEIGHT"',"fileHash":"'"$FILE_HASH"'","intent":"catch.create"}}}'
  local result
  result=$(post_gql "$payload")
  
  if echo "$result" | jq -e '.data.createImageUploadIntent.image.id' > /dev/null 2>&1; then
    local imageId
    imageId=$(echo "$result" | jq -r '.data.createImageUploadIntent.image.id')
    log_pass "Created image upload intent, image ID: $imageId"
    echo "$imageId"
  else
    log_fail "Failed to create image upload intent"
    echo "$result" | jq .
    echo ""
  fi
}

# Test 2: Delete Uploaded Files
function test_delete_uploaded_files() {
  log_test "Delete uploaded files"
  local fileIdsJson='["0199e6de-f93f-74a7-8641-33533892cdb5","0199e6df-0211-7714-b47c-a94813c12aae"]'
  local payload='{"query":"mutation DeleteUploadedFiles($input: DeleteUploadedFilesMutationInput!) { deleteUploadedFiles(input: $input) { deletedIds errors { ... on MutationError { code message } } } }","operationName":"DeleteUploadedFiles","variables":{"input":{"ids":'"$fileIdsJson"'}}}'
  local result
  result=$(post_gql "$payload")
  
  if echo "$result" | jq -e '.data.deleteUploadedFiles.deletedIds' > /dev/null 2>&1; then
    local deletedCount
    deletedCount=$(echo "$result" | jq -r '.data.deleteUploadedFiles.deletedIds | length')
    log_pass "Deleted $deletedCount files"
  else
    log_fail "Failed to delete uploaded files"
    echo "$result" | jq .
    echo ""
  fi
}

function run_all() {
  echo "=========================================="
  echo "TESTING USER-UPLOADS-SERVICE"
  echo "=========================================="
  echo ""
  
  # Test 1: Create image upload intent
  test_create_image_upload_intent
  echo ""
  
  # Test 2: Delete uploaded files (commented out as it deletes real data)
  # test_delete_uploaded_files
  # echo ""
  
  echo "=========================================="
  echo "RESULTS: PASSED=$PASSED, FAILED=$FAILED"
  echo "=========================================="
  
  if [[ $FAILED -gt 0 ]]; then
    exit 1
  fi
}

"${@:-run_all}"
