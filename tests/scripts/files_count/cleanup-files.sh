#!/usr/bin/env bash
# This script cleans up files from waterbodies and spots
# It expects ACCESS_TOKEN to be set as environment variable
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check that ACCESS_TOKEN is set
if [ -z "${ACCESS_TOKEN:-}" ]; then
  echo "ERROR: ACCESS_TOKEN environment variable is not set" >&2
  exit 1
fi

# ===== Constants =====
WATERBODY_ID_1="01985af6-667e-7abc-9c63-00ce1051408d" # Iliamna Lake
WATERBODY_ID_2="01972092-bd77-7a2c-817b-5ba9141f56fe" # Lake Mille Lacs
SPOT_ID_1="018e5cc0-72e0-71e7-b728-8830612b6b2a" # Iliamna Lake
SPOT_ID_2="018e0de5-1220-7244-b198-c08b7b7475bd" # Lake Mille Lacs
SYNC_DELAY_SECONDS=5
OUT_DIR="./out"
mkdir -p "$OUT_DIR"

# ===== Helpers =====
log() { echo "[$(date +%H:%M:%S)] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

# ===== Query waterbodies =====
query_waterbodies() {
  local id1="$1"
  local id2="$2"
  read -r -d '' QUERY <<'Q'
query getWaterbodyById($id1: ID!, $id2: ID!) {
  waterbodies(ids: [$id1, $id2], first: 2) {
    edges {
      node {
        id
        files {
          connection(
            first: 20
            fileType: [Image, Video]
          ) {
            edges {
              node {
                id
              }
            }
          }
        }
      }
    }
  }
}
Q
  local payload
  payload=$(jq -n --arg q "$QUERY" --arg id1 "$id1" --arg id2 "$id2" '{query:$q, operationName:"getWaterbodyById", variables:{id1:$id1,id2:$id2}}')
  curl -s -S -X POST "$API_GRAPHQL_URL" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -H "User-Agent: tests/files_count" \
    -H "x-viewer-id: $VIEWER_ID" \
    -d "$payload"
}

# ===== Query spots =====
query_spots() {
  local id1="$1"
  local id2="$2"
  read -r -d '' QUERY <<'Q'
query getSpotsById($id1: ID!, $id2: ID!) {
  spots(ids: [$id1, $id2], first: 2) {
    edges {
      node {
        id
        files {
          connection(
            first: 20
            fileType: [Image, Video]
          ) {
            edges {
              node {
                id
              }
            }
          }
        }
      }
    }
  }
}
Q
  local payload
  payload=$(jq -n --arg q "$QUERY" --arg id1 "$id1" --arg id2 "$id2" '{query:$q, operationName:"getSpotsById", variables:{id1:$id1,id2:$id2}}')
  curl -s -S -X POST "$API_GRAPHQL_URL" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -H "User-Agent: tests/files_count" \
    -H "x-viewer-id: $VIEWER_ID" \
    -d "$payload"
}

extract_waterbody_file_ids() {
  jq -r '.data.waterbodies.edges[].node.files.connection.edges[].node.id' | grep -v '^null$' | grep -v '^$' || true
}

extract_spot_file_ids() {
  jq -r '.data.spots.edges[].node.files.connection.edges[].node.id' | grep -v '^null$' | grep -v '^$' || true
}

# ===== Mutations =====
mutation_delete_files() {
  local ids_json="$1" # JSON-массив строк
  local payload
  payload=$(jq -n --argjson fileIds "$ids_json" '{
    query: "mutation DeleteUploadedFiles($input: DeleteUploadedFilesMutationInput!) { deleteUploadedFiles(input: $input) { errors { ... on MutationError { code message } } } }",
    operationName: "DeleteUploadedFiles",
    variables: { input: { fileIds: $fileIds } }
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
  log "Cleaning up files from waterbodies and spots"
  # Check that required environment variables are set
  if [ -z "${API_GRAPHQL_URL:-}" ]; then
    fail "API_GRAPHQL_URL environment variable is not set"
  fi
  if [ -z "${VIEWER_ID:-}" ]; then
    fail "VIEWER_ID environment variable is not set"
  fi

  log "Querying waterbodies: waterbodyId1=$WATERBODY_ID_1, waterbodyId2=$WATERBODY_ID_2"
  res_wb=$(query_waterbodies "$WATERBODY_ID_1" "$WATERBODY_ID_2")
  all_wb_ids=$(echo "$res_wb" | extract_waterbody_file_ids | tr '\n' ' ' | xargs -n1 echo | jq -R . | jq -s . 2>/dev/null || echo '[]')
  local wb_ids_count=$(echo "$all_wb_ids" | jq 'length')

  log "Querying spots: spotId1=$SPOT_ID_1, spotId2=$SPOT_ID_2"
  res_spots=$(query_spots "$SPOT_ID_1" "$SPOT_ID_2")
  all_spot_ids=$(echo "$res_spots" | extract_spot_file_ids | tr '\n' ' ' | xargs -n1 echo | jq -R . | jq -s . 2>/dev/null || echo '[]')
  local spot_ids_count=$(echo "$all_spot_ids" | jq 'length')

  # Combine all file IDs (merge arrays and remove duplicates)
  all_file_ids=$(jq -n --argjson wb "$all_wb_ids" --argjson spots "$all_spot_ids" '$wb + $spots | unique')
  local total_count=$(echo "$all_file_ids" | jq 'length')

  if [ "$total_count" -gt 0 ]; then
    log "Deleting $total_count files from waterbodies ($wb_ids_count files) and spots ($spot_ids_count files)..."
    log "  fileIds: $(echo "$all_file_ids" | jq -r 'join(", ")')"
    del_res=$(mutation_delete_files "$all_file_ids")
    echo "$del_res" | jq '.' > "$OUT_DIR/cleanup_delete_files.json"
    local errors=$(echo "$del_res" | jq -r '.data.deleteUploadedFiles.errors // [] | length')
    if [ "$errors" -gt 0 ]; then
      log "WARNING: Errors during deletion:"
      echo "$del_res" | jq '.data.deleteUploadedFiles.errors'
    else
      log "✓ Files deleted successfully"
    fi
    log "Waiting ${SYNC_DELAY_SECONDS} seconds for synchronization..."
    sleep "$SYNC_DELAY_SECONDS"
  else
    log "No files to delete"
  fi

  log "✓ Cleanup completed"
}

main "$@"
