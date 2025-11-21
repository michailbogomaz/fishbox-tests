#!/usr/bin/env bash
# This script deletes all catches created during tests
# It expects ACCESS_TOKEN to be set as environment variable
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check that ACCESS_TOKEN is set
if [ -z "${ACCESS_TOKEN:-}" ]; then
  echo "ERROR: ACCESS_TOKEN environment variable is not set" >&2
  exit 1
fi

# ===== Constants =====
OUT_DIR="./out"
CATCHES_FILE="$OUT_DIR/catches_to_cleanup.txt"

# ===== Helpers =====
log() { echo "[$(date +%H:%M:%S)] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

# ===== Mutations =====
mutation_delete_catch() {
  local catchId="$1"
  local payload
  payload=$(jq -n --arg id "$catchId" '{
    query: "mutation DeleteCatch($input: DeleteCatchMutationInput!) { deleteCatch(input: $input) { errors { ... on MutationError { code message } } } }",
    operationName: "DeleteCatch",
    variables: { input: { id: $id } }
  }')
  curl -s -S -X POST "$API_GRAPHQL_URL" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -H "User-Agent: tests/files_count" \
    -H "x-viewer-id: $VIEWER_ID" \
    -d "$payload"
}

# ===== Main flow =====
main() {
  log "Cleaning up catches created during tests"
  # Check that required environment variables are set
  if [ -z "${API_GRAPHQL_URL:-}" ]; then
    fail "API_GRAPHQL_URL environment variable is not set"
  fi
  if [ -z "${VIEWER_ID:-}" ]; then
    fail "VIEWER_ID environment variable is not set"
  fi

  if [ ! -f "$CATCHES_FILE" ]; then
    log "No catches file found ($CATCHES_FILE), nothing to clean up"
    return 0
  fi

  # Read catch IDs from file (one per line, skip empty lines)
  local catches_to_delete=()
  while IFS= read -r catch_id || [ -n "$catch_id" ]; do
    [ -n "$catch_id" ] && [ "$catch_id" != "null" ] && catches_to_delete+=("$catch_id")
  done < "$CATCHES_FILE"

  if [ "${#catches_to_delete[@]}" -eq 0 ]; then
    log "No catches to delete"
    return 0
  fi

  log "Found ${#catches_to_delete[@]} catches to delete"
  local deleted_count=0
  local failed_count=0

  for catch_id in "${catches_to_delete[@]}"; do
    log "Deleting catch with id=$catch_id"
    del_res=$(mutation_delete_catch "$catch_id")
    local errors=$(echo "$del_res" | jq -r ".data.deleteCatch.errors // [] | length")
    if [ "$errors" -gt 0 ]; then
      log "WARNING: Errors deleting catch (catchId=$catch_id):"
      echo "$del_res" | jq ".data.deleteCatch.errors"
      failed_count=$((failed_count + 1))
    else
      log "✓ Deleted catch with id=$catch_id"
      deleted_count=$((deleted_count + 1))
    fi
  done

  log "✓ Cleanup completed: $deleted_count deleted, $failed_count failed"
  
  # Clear the catches file
  > "$CATCHES_FILE"
}

main "$@"
