#!/usr/bin/env bash
# This script tests file count interactions between waterbodies and spots
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
SPOT_ID_1="018e5cc0-72e0-71e7-b728-8830612b6b2a" # Iliamna Lake (same as WB1)
SPOT_ID_2="018e0de5-1220-7244-b198-c08b7b7475bd" # Lake Mille Lacs (same as WB2)
SYNC_DELAY_SECONDS=5
UPLOADED_CSV="../upload-files/$UPLOADED_FILES_LIST_CSV"
OUT_DIR="./out"
mkdir -p "$OUT_DIR"

# ===== Helpers =====
log() { echo "[$(date +%H:%M:%S)] $*"; }
log_step() { echo ""; log "========== STEP $1 =========="; }
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
        title
        files {
          imagesCount: filesCount(type: Image)
          videosCount: filesCount(type: Video)
          connection(
            first: 20
            fileType: [Image, Video]
          ) {
            edges {
              cursor
              node {
                id
                status
                createdAt
                fileType
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
        name
        files {
          imagesCount: filesCount(type: Image)
          videosCount: filesCount(type: Video)
          connection(
            first: 20
            fileType: [Image, Video]
          ) {
            edges {
              cursor
              node {
                id
                status
                createdAt
                fileType
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

extract_waterbody_counts() {
  jq -r '.data.waterbodies.edges[] | "\(.node.id) (\(.node.title)): images=\(.node.files.imagesCount), videos=\(.node.files.videosCount), total_files=\(.node.files.connection.edges | length)"'
}

extract_spot_counts() {
  jq -r '.data.spots.edges[] | "\(.node.id) (\(.node.name)): images=\(.node.files.imagesCount), videos=\(.node.files.videosCount), total_files=\(.node.files.connection.edges | length)"'
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

mutation_add_files_to_spot() {
  local spotId="$1"
  local filesIdsJson="$2" # JSON-массив строк
  local payload
  payload=$(jq -n --arg id "$spotId" --argjson fileIds "$filesIdsJson" '{
    query: "mutation AddFilesToSpot($input: AddFilesToSpotMutationInput!) { addFilesToSpot(input:$input){ errors { ... on MutationError { code message } } } }",
    operationName: "AddFilesToSpot",
    variables: { input: { id: $id, fileIds: $fileIds } }
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
  log "Running waterbody-spot files_count test"
  # Check that required environment variables are set
  if [ -z "${API_GRAPHQL_URL:-}" ]; then
    fail "API_GRAPHQL_URL environment variable is not set"
  fi
  if [ -z "${VIEWER_ID:-}" ]; then
    fail "VIEWER_ID environment variable is not set"
  fi
  log "API_GRAPHQL_URL: $API_GRAPHQL_URL"

  log_step "1"
  log "Получить начальное состояние spots и waterbodies"
  log "Querying spots: spotId1=$SPOT_ID_1 (waterbodyId=$WATERBODY_ID_1), spotId2=$SPOT_ID_2 (waterbodyId=$WATERBODY_ID_2)"
  res1_spots=$(query_spots "$SPOT_ID_1" "$SPOT_ID_2")
  res1_wb=$(query_waterbodies "$WATERBODY_ID_1" "$WATERBODY_ID_2")
  echo "$res1_spots" > "$OUT_DIR/step1_spots.json"
  echo "$res1_wb" > "$OUT_DIR/step1_waterbodies.json"
  log "Initial spot counts:"
  echo "$res1_spots" | extract_spot_counts
  log "Initial waterbody counts:"
  echo "$res1_wb" | extract_waterbody_counts

  log_step "2"
  log "Удалить все файлы из spots (и проверить влияние на waterbodies)"
  log "Deleting files from spots: spotId1=$SPOT_ID_1, spotId2=$SPOT_ID_2"
  res_for_delete_spots=$(query_spots "$SPOT_ID_1" "$SPOT_ID_2")
  all_spot_ids=$(echo "$res_for_delete_spots" | extract_spot_file_ids | tr '\n' ' ' | xargs -n1 echo | jq -R . | jq -s . 2>/dev/null || echo '[]')
  local spot_ids_count=$(echo "$all_spot_ids" | jq 'length')
  if [ "$spot_ids_count" -gt 0 ]; then
    log "Deleting $spot_ids_count files from spots (spotId1=$SPOT_ID_1, spotId2=$SPOT_ID_2)..."
    log "  fileIds: $(echo "$all_spot_ids" | jq -r 'join(", ")')"
    del_res_spots=$(mutation_delete_files "$all_spot_ids")
    echo "$del_res_spots" | jq '.' > "$OUT_DIR/step2_delete_spot_files.json"
    local errors=$(echo "$del_res_spots" | jq -r '.data.deleteUploadedFiles.errors // [] | length')
    if [ "$errors" -gt 0 ]; then
      log "WARNING: Errors during deletion:"
      echo "$del_res_spots" | jq '.data.deleteUploadedFiles.errors'
    else
      log "✓ Files deleted successfully from spots"
    fi
  else
    log "No files to delete from spots"
  fi

  log_step "3"
  log "Проверить, что файлы удалились из spots и связанных waterbodies"
  log "Checking spots and waterbodies after file deletion from spots"
  log "Waiting ${SYNC_DELAY_SECONDS} seconds for synchronization..."
  sleep "$SYNC_DELAY_SECONDS"
  res3_spots=$(query_spots "$SPOT_ID_1" "$SPOT_ID_2")
  res3_wb=$(query_waterbodies "$WATERBODY_ID_1" "$WATERBODY_ID_2")
  echo "$res3_spots" | jq '.' > "$OUT_DIR/step3_spots.json"
  echo "$res3_wb" | jq '.' > "$OUT_DIR/step3_waterbodies.json"
  local spot1_count=$(echo "$res3_spots" | jq -r --arg s1 "$SPOT_ID_1" '.data.spots.edges[] | select(.node.id==$s1) | .node.files.connection.edges | length')
  local spot2_count=$(echo "$res3_spots" | jq -r --arg s2 "$SPOT_ID_2" '.data.spots.edges[] | select(.node.id==$s2) | .node.files.connection.edges | length')
  local wb1_count=$(echo "$res3_wb" | jq -r --arg wb1 "$WATERBODY_ID_1" '.data.waterbodies.edges[] | select(.node.id==$wb1) | .node.files.connection.edges | length')
  local wb2_count=$(echo "$res3_wb" | jq -r --arg wb2 "$WATERBODY_ID_2" '.data.waterbodies.edges[] | select(.node.id==$wb2) | .node.files.connection.edges | length')
  log "Spot1 (spotId=$SPOT_ID_1) has $spot1_count files"
  log "Spot2 (spotId=$SPOT_ID_2) has $spot2_count files"
  log "Waterbody1 (waterbodyId=$WATERBODY_ID_1, spotId=$SPOT_ID_1) has $wb1_count files"
  log "Waterbody2 (waterbodyId=$WATERBODY_ID_2, spotId=$SPOT_ID_2) has $wb2_count files"

  log_step "4"
  log "Добавить файлы в spot и проверить влияние на связанный waterbody"
  [ -f "$UPLOADED_CSV" ] || fail "Не найден $UPLOADED_CSV — выполните загрузку файлов"
  unused_for_spot=()
  while IFS=',' read -r id status url; do
    if [ -n "$id" ] && [ "$status" == "uploaded" ]; then
      if [ "${#id}" -eq 35 ] && [[ "$id" =~ ^[0-9a-f]{7}- ]]; then
        id="0$id"
      fi
      unused_for_spot+=("$id")
    fi
  done < <(tail -n +2 "$UPLOADED_CSV")
  [ "${#unused_for_spot[@]}" -ge 2 ] || fail "Недостаточно неиспользованных файлов для теста (нужно >=2, есть ${#unused_for_spot[@]})"
  files_spot=$(printf '%s\n' "${unused_for_spot[0]}" "${unused_for_spot[1]}" | jq -R . | jq -s .)
  log "Adding files directly to spot (spotId=$SPOT_ID_2, fileIds=[${unused_for_spot[0]}, ${unused_for_spot[1]}])"
  add_spot=$(mutation_add_files_to_spot "$SPOT_ID_2" "$files_spot")
  echo "$add_spot" | jq '.' > "$OUT_DIR/step4_add_files_to_spot.json"
  local add_spot_errors=$(echo "$add_spot" | jq -r '.data.addFilesToSpot.errors // [] | length')
  if [ "$add_spot_errors" -gt 0 ]; then
    log "ERROR adding files directly to spot (spotId=$SPOT_ID_2, fileIds=[${unused_for_spot[0]}, ${unused_for_spot[1]}]):"
    echo "$add_spot" | jq '.data.addFilesToSpot.errors'
  else
    log "✓ Files added directly to spot (spotId=$SPOT_ID_2, fileIds=[${unused_for_spot[0]}, ${unused_for_spot[1]}])"
    sed -i '' "s/^${unused_for_spot[0]},uploaded,/${unused_for_spot[0]},used,/" "$UPLOADED_CSV" 2>/dev/null || sed -i "s/^${unused_for_spot[0]},uploaded,/${unused_for_spot[0]},used,/" "$UPLOADED_CSV"
    sed -i '' "s/^${unused_for_spot[1]},uploaded,/${unused_for_spot[1]},used,/" "$UPLOADED_CSV" 2>/dev/null || sed -i "s/^${unused_for_spot[1]},uploaded,/${unused_for_spot[1]},used,/" "$UPLOADED_CSV"
  fi

  log_step "5"
  log "Проверка counts после добавления файлов в spot (spot и связанный waterbody)"
  log "Checking spotId2=$SPOT_ID_2 and waterbodyId2=$WATERBODY_ID_2 after direct file addition to spot"
  log "Waiting ${SYNC_DELAY_SECONDS} seconds for synchronization..."
  sleep "$SYNC_DELAY_SECONDS"
  res5_spots=$(query_spots "$SPOT_ID_1" "$SPOT_ID_2")
  res5_wb=$(query_waterbodies "$WATERBODY_ID_1" "$WATERBODY_ID_2")
  echo "$res5_spots" | jq '.' > "$OUT_DIR/step5_spots.json"
  echo "$res5_wb" | jq '.' > "$OUT_DIR/step5_waterbodies.json"
  log "Spot counts:"
  echo "$res5_spots" | extract_spot_counts
  log "Waterbody counts:"
  echo "$res5_wb" | extract_waterbody_counts
  local spot2_final=$(echo "$res5_spots" | jq -r --arg spot2 "$SPOT_ID_2" '.data.spots.edges[] | select(.node.id==$spot2) | .node.files.connection.edges | length')
  local wb2_final=$(echo "$res5_wb" | jq -r --arg wb2 "$WATERBODY_ID_2" '.data.waterbodies.edges[] | select(.node.id==$wb2) | .node.files.connection.edges | length')
  log "Spot2 (spotId=$SPOT_ID_2) now has $spot2_final files"
  log "Waterbody2 (waterbodyId=$WATERBODY_ID_2) now has $wb2_final files (should include files from spot)"

  log_step "6"
  log "Удаление файлов из spot и проверка влияния на waterbody"
  res_for_delete_spot=$(query_spots "$SPOT_ID_1" "$SPOT_ID_2")
  all_spot_file_ids=$(echo "$res_for_delete_spot" | extract_spot_file_ids | tr '\n' ' ' | xargs -n1 echo | jq -R . | jq -s . 2>/dev/null || echo '[]')
  local spot_file_ids_count=$(echo "$all_spot_file_ids" | jq 'length')
  if [ "$spot_file_ids_count" -gt 0 ]; then
    log "Deleting $spot_file_ids_count files from spot (spotId=$SPOT_ID_2)..."
    log "  fileIds: $(echo "$all_spot_file_ids" | jq -r 'join(", ")')"
    del_res_spot=$(mutation_delete_files "$all_spot_file_ids")
    echo "$del_res_spot" | jq '.' > "$OUT_DIR/step6_delete_spot_files.json"
    local errors=$(echo "$del_res_spot" | jq -r '.data.deleteUploadedFiles.errors // [] | length')
    if [ "$errors" -gt 0 ]; then
      log "WARNING: Errors during deletion:"
      echo "$del_res_spot" | jq '.data.deleteUploadedFiles.errors'
    else
      log "✓ Files deleted successfully from spot"
    fi
  else
    log "No files to delete from spot"
  fi
  log "Waiting ${SYNC_DELAY_SECONDS} seconds for synchronization..."
  sleep "$SYNC_DELAY_SECONDS"
  res6_spots=$(query_spots "$SPOT_ID_1" "$SPOT_ID_2")
  res6_wb=$(query_waterbodies "$WATERBODY_ID_1" "$WATERBODY_ID_2")
  echo "$res6_spots" | jq '.' > "$OUT_DIR/step6_spots.json"
  echo "$res6_wb" | jq '.' > "$OUT_DIR/step6_waterbodies.json"
  log "Final spot counts:"
  echo "$res6_spots" | extract_spot_counts
  log "Final waterbody counts:"
  echo "$res6_wb" | extract_waterbody_counts
  local spot2_after_delete=$(echo "$res6_spots" | jq -r --arg spot2 "$SPOT_ID_2" '.data.spots.edges[] | select(.node.id==$spot2) | .node.files.connection.edges | length')
  local wb2_after_delete=$(echo "$res6_wb" | jq -r --arg wb2 "$WATERBODY_ID_2" '.data.waterbodies.edges[] | select(.node.id==$wb2) | .node.files.connection.edges | length')
  log "Spot2 (spotId=$SPOT_ID_2) now has $spot2_after_delete files"
  log "Waterbody2 (waterbodyId=$WATERBODY_ID_2) now has $wb2_after_delete files (should reflect file deletion from spot)"

  echo ""
  log "========== WATERBODY-SPOT FILES_COUNT TEST COMPLETED SUCCESSFULLY =========="
}

main "$@"
