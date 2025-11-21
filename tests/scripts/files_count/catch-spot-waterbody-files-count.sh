#!/usr/bin/env bash
# This script tests file count interactions between catch, spot, and waterbody
# When catch is created with coordinates matching a spot, files should appear in catch, spot, and related waterbody
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
SPOT1_LAT="59.542"
SPOT1_LON="-155.144"
SPOT2_LAT="46.2"
SPOT2_LON="-93.7"
CANADA_LAT="56.1304"
CANADA_LON="-106.3468"
SYNC_DELAY_SECONDS=5
UPLOADED_CSV="../upload-files/$UPLOADED_FILES_LIST_CSV"
OUT_DIR="./out"
CATCHES_FILE="$OUT_DIR/catches_to_cleanup.txt"
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
mutation_create_catch() {
  local lat="$1"
  local lon="$2"
  local filesIdsJson="$3"
  local public="${4:-true}"
  local payload
  payload=$(jq -n \
    --argjson lat "$lat" \
    --argjson lon "$lon" \
    --argjson files "$filesIdsJson" \
    --argjson pub "$public" '{
      query: "mutation CreateCatch($input: CreateCatchMutationInput!) { createCatch(input: $input) { catch { id lat lon public } errors { ... on MutationError { code message } } } }",
      operationName: "CreateCatch",
      variables: { input: { lat: $lat, lon: $lon, filesIds: $files, public: $pub } }
    }')
  curl -s -S -X POST "$API_GRAPHQL_URL" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -H "User-Agent: tests/files_count" \
    -H "x-viewer-id: $VIEWER_ID" \
    -d "$payload"
}

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

mutation_update_catch_public() {
  local catchId="$1"
  local isPublic="$2"
  local payload
  payload=$(jq -n \
    --arg id "$catchId" \
    --argjson pub "$isPublic" \
    '{
      query: "mutation UpdateCatch($input: UpdateCatchMutationInput!) { updateCatch(input: $input) { catch { id public } errors { ... on MutationError { code message } } } }",
      operationName: "UpdateCatch",
      variables: { input: { id: $id, public: $pub } }
    }')
  curl -s -S -X POST "$API_GRAPHQL_URL" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -H "User-Agent: tests/files_count" \
    -H "x-viewer-id: $VIEWER_ID" \
    -d "$payload"
}

mutation_update_catch_coords() {
  local catchId="$1"
  local lat="$2"
  local lon="$3"
  local payload
  payload=$(jq -n \
    --arg id "$catchId" \
    --arg lat_str "$lat" \
    --arg lon_str "$lon" \
    '{
      query: "mutation UpdateCatch($input: UpdateCatchMutationInput!) { updateCatch(input: $input) { catch { id lat lon } errors { ... on MutationError { code message } } } }",
      operationName: "UpdateCatch",
      variables: { input: { id: $id, lat: ($lat_str | tonumber), lon: ($lon_str | tonumber) } }
    }')
  curl -s -S -X POST "$API_GRAPHQL_URL" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -H "User-Agent: tests/files_count" \
    -H "x-viewer-id: $VIEWER_ID" \
    -d "$payload"
}

mutation_update_catch_files() {
  local catchId="$1"
  local filesIdsJson="$2"
  local payload
  payload=$(jq -n \
    --arg id "$catchId" \
    --argjson filesIds "$filesIdsJson" \
    '{
      query: "mutation UpdateCatch($input: UpdateCatchMutationInput!) { updateCatch(input: $input) { catch { id } errors { ... on MutationError { code message } } } }",
      operationName: "UpdateCatch",
      variables: { input: { id: $id, filesIds: $filesIds } }
    }')
  curl -s -S -X POST "$API_GRAPHQL_URL" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -H "User-Agent: tests/files_count" \
    -H "x-viewer-id: $VIEWER_ID" \
    -d "$payload"
}

# Query catch to get its files
query_catch() {
  local catchId="$1"
  local payload
  payload=$(jq -n --arg id "$catchId" '{
    query: "query GetCatch($id: ID!) { viewer { catches(ids: [$id]) { edges { node { id lat lon public entityFiles { connection(first: 50, fileType: [Image, Video]) { edges { node { id fileType status } } } } } } } } }",
    operationName: "GetCatch",
    variables: { id: $id }
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
  log "Running catch-spot-waterbody files_count test"
  # Check that required environment variables are set
  if [ -z "${API_GRAPHQL_URL:-}" ]; then
    fail "API_GRAPHQL_URL environment variable is not set"
  fi
  if [ -z "${VIEWER_ID:-}" ]; then
    fail "VIEWER_ID environment variable is not set"
  fi
  log "API_GRAPHQL_URL: $API_GRAPHQL_URL"

  log_step "1"
  log "Получить начальное состояние catch, spot и waterbody"
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
  log "Создать catch с координатами spot1 - файлы должны появиться в catch, spot1 и waterbody1"
  [ -f "$UPLOADED_CSV" ] || fail "Не найден $UPLOADED_CSV — выполните загрузку файлов"
  file_ids=()
  while IFS=',' read -r id status url; do
    [ -n "$id" ] && [ "$status" != "used" ] && [ "$status" != "error" ] && [ "$status" != "upload_failed" ] && file_ids+=("$id")
  done < <(tail -n +2 "$UPLOADED_CSV")
  [ "${#file_ids[@]}" -ge 2 ] || fail "Недостаточно файлов в CSV (нужно >=2, есть ${#file_ids[@]})"
  files1=$(printf '%s\n' "${file_ids[0]}" "${file_ids[1]}" | jq -R . | jq -s .)

  log "Creating catch for spot1/waterbody1 with files: ${file_ids[0]}, ${file_ids[1]}"
  log "  Coordinates: lat=$SPOT1_LAT, lon=$SPOT1_LON (same as spotId=$SPOT_ID_1, waterbodyId=$WATERBODY_ID_1)"
  c1=$(mutation_create_catch "$SPOT1_LAT" "$SPOT1_LON" "$files1" "true")
  echo "$c1" | jq '.' > "$OUT_DIR/step2_catch1.json"
  catch1_id=$(echo "$c1" | jq -r '.data.createCatch.catch.id // empty')
  if [ -z "$catch1_id" ] || [ "$catch1_id" == "null" ]; then
    log "ERROR creating catch1:"
    echo "$c1" | jq '.data.createCatch.errors'
    fail "Failed to create catch1"
  fi
  echo "$catch1_id" >> "$CATCHES_FILE"
  log "✓ Created catch with id=$catch1_id (coordinates match spotId=$SPOT_ID_1, waterbodyId=$WATERBODY_ID_1)"
  log "  fileIds=[${file_ids[0]}, ${file_ids[1]}]"
  sed -i '' "s/^${file_ids[0]},uploaded,/${file_ids[0]},used,/" "$UPLOADED_CSV" 2>/dev/null || sed -i "s/^${file_ids[0]},uploaded,/${file_ids[0]},used,/" "$UPLOADED_CSV"
  sed -i '' "s/^${file_ids[1]},uploaded,/${file_ids[1]},used,/" "$UPLOADED_CSV" 2>/dev/null || sed -i "s/^${file_ids[1]},uploaded,/${file_ids[1]},used,/" "$UPLOADED_CSV"

  log_step "3"
  log "Проверить, что файлы появились в catch, spot1 и waterbody1"
  log "Checking catch (catchId=${catch1_id:-N/A}), spot (spotId=$SPOT_ID_1), and waterbody (waterbodyId=$WATERBODY_ID_1)"
  log "Waiting ${SYNC_DELAY_SECONDS} seconds for files to be associated..."
  sleep "$SYNC_DELAY_SECONDS"
  
  # Check catch files
  catch_info=$(query_catch "$catch1_id")
  echo "$catch_info" | jq '.' > "$OUT_DIR/step3_catch1_info.json"
  local catch_files_count=$(echo "$catch_info" | jq -r '.data.viewer.catches.edges[0].node.entityFiles.connection.edges | length')
  log "Catch (catchId=$catch1_id) has $catch_files_count files"
  if [ "$catch_files_count" != "2" ]; then
    fail "Expected 2 files in catch (catchId=$catch1_id), got $catch_files_count"
  fi
  
  # Check spot files
  res3_spots=$(query_spots "$SPOT_ID_1" "$SPOT_ID_2")
  echo "$res3_spots" | jq '.' > "$OUT_DIR/step3_spots.json"
  local spot1_count=$(echo "$res3_spots" | jq -r --arg s1 "$SPOT_ID_1" '.data.spots.edges[] | select(.node.id==$s1) | .node.files.connection.edges | length')
  log "Spot1 (spotId=$SPOT_ID_1) has $spot1_count files"
  if [ "$spot1_count" != "2" ]; then
    fail "Expected 2 files in spot1 (spotId=$SPOT_ID_1, catchId=$catch1_id), got $spot1_count"
  fi
  
  # Check waterbody files
  res3_wb=$(query_waterbodies "$WATERBODY_ID_1" "$WATERBODY_ID_2")
  echo "$res3_wb" | jq '.' > "$OUT_DIR/step3_waterbodies.json"
  local wb1_count=$(echo "$res3_wb" | jq -r --arg wb1 "$WATERBODY_ID_1" '.data.waterbodies.edges[] | select(.node.id==$wb1) | .node.files.connection.edges | length')
  log "Waterbody1 (waterbodyId=$WATERBODY_ID_1, spotId=$SPOT_ID_1) has $wb1_count files"
  if [ "$wb1_count" != "2" ]; then
    fail "Expected 2 files in waterbody1 (waterbodyId=$WATERBODY_ID_1, spotId=$SPOT_ID_1, catchId=$catch1_id), got $wb1_count"
  fi
  log "✓ All three entities have 2 files each (catchId=$catch1_id, spotId=$SPOT_ID_1, waterbodyId=$WATERBODY_ID_1)"

  log_step "4"
  log "Создать catch с координатами spot2 - файлы должны появиться в catch, spot2 и waterbody2"
  [ "${#file_ids[@]}" -ge 4 ] || fail "Недостаточно файлов в CSV (нужно >=4, есть ${#file_ids[@]})"
  files2=$(printf '%s\n' "${file_ids[2]}" "${file_ids[3]}" | jq -R . | jq -s .)

  log "Creating catch for spot2/waterbody2 with files: ${file_ids[2]}, ${file_ids[3]}"
  log "  Coordinates: lat=$SPOT2_LAT, lon=$SPOT2_LON (same as spotId=$SPOT_ID_2, waterbodyId=$WATERBODY_ID_2)"
  c2=$(mutation_create_catch "$SPOT2_LAT" "$SPOT2_LON" "$files2" "true")
  echo "$c2" | jq '.' > "$OUT_DIR/step4_catch2.json"
  catch2_id=$(echo "$c2" | jq -r '.data.createCatch.catch.id // empty')
  if [ -z "$catch2_id" ] || [ "$catch2_id" == "null" ]; then
    log "ERROR creating catch2:"
    echo "$c2" | jq '.data.createCatch.errors'
    fail "Failed to create catch2"
  fi
  echo "$catch2_id" >> "$CATCHES_FILE"
  log "✓ Created catch with id=$catch2_id (coordinates match spotId=$SPOT_ID_2, waterbodyId=$WATERBODY_ID_2)"
  log "  fileIds=[${file_ids[2]}, ${file_ids[3]}]"
  sed -i '' "s/^${file_ids[2]},uploaded,/${file_ids[2]},used,/" "$UPLOADED_CSV" 2>/dev/null || sed -i "s/^${file_ids[2]},uploaded,/${file_ids[2]},used,/" "$UPLOADED_CSV"
  sed -i '' "s/^${file_ids[3]},uploaded,/${file_ids[3]},used,/" "$UPLOADED_CSV" 2>/dev/null || sed -i "s/^${file_ids[3]},uploaded,/${file_ids[3]},used,/" "$UPLOADED_CSV"

  log_step "5"
  log "Проверить, что файлы появились в catch, spot2 и waterbody2"
  log "Checking catch (catchId=${catch2_id:-N/A}), spot (spotId=$SPOT_ID_2), and waterbody (waterbodyId=$WATERBODY_ID_2)"
  log "Waiting ${SYNC_DELAY_SECONDS} seconds for files to be associated..."
  sleep "$SYNC_DELAY_SECONDS"
  
  # Check catch files
  catch2_info=$(query_catch "$catch2_id")
  echo "$catch2_info" | jq '.' > "$OUT_DIR/step5_catch2_info.json"
  local catch2_files_count=$(echo "$catch2_info" | jq -r '.data.viewer.catches.edges[0].node.entityFiles.connection.edges | length')
  log "Catch (catchId=$catch2_id) has $catch2_files_count files"
  if [ "$catch2_files_count" != "2" ]; then
    fail "Expected 2 files in catch (catchId=$catch2_id), got $catch2_files_count"
  fi
  
  # Check spot files
  res5_spots=$(query_spots "$SPOT_ID_1" "$SPOT_ID_2")
  echo "$res5_spots" | jq '.' > "$OUT_DIR/step5_spots.json"
  local spot2_count=$(echo "$res5_spots" | jq -r --arg s2 "$SPOT_ID_2" '.data.spots.edges[] | select(.node.id==$s2) | .node.files.connection.edges | length')
  log "Spot2 (spotId=$SPOT_ID_2) has $spot2_count files"
  if [ "$spot2_count" != "2" ]; then
    fail "Expected 2 files in spot2 (spotId=$SPOT_ID_2, catchId=$catch2_id), got $spot2_count"
  fi
  
  # Check waterbody files
  res5_wb=$(query_waterbodies "$WATERBODY_ID_1" "$WATERBODY_ID_2")
  echo "$res5_wb" | jq '.' > "$OUT_DIR/step5_waterbodies.json"
  local wb2_count=$(echo "$res5_wb" | jq -r --arg wb2 "$WATERBODY_ID_2" '.data.waterbodies.edges[] | select(.node.id==$wb2) | .node.files.connection.edges | length')
  log "Waterbody2 (waterbodyId=$WATERBODY_ID_2, spotId=$SPOT_ID_2) has $wb2_count files"
  if [ "$wb2_count" != "2" ]; then
    fail "Expected 2 files in waterbody2 (waterbodyId=$WATERBODY_ID_2, spotId=$SPOT_ID_2, catchId=$catch2_id), got $wb2_count"
  fi
  log "✓ All three entities have 2 files each (catchId=$catch2_id, spotId=$SPOT_ID_2, waterbodyId=$WATERBODY_ID_2)"

  log_step "6"
  log "Удалить один файл у catch1 - должно уменьшиться в catch, spot1 и waterbody1"
  if [ -z "${catch1_id:-}" ]; then
    fail "catch1_id is not set, cannot proceed with step 6"
  fi
  log "Querying catch info (catchId=$catch1_id)"
  catch1_info=$(query_catch "$catch1_id")
  echo "$catch1_info" | jq '.' > "$OUT_DIR/step6_catch1_info.json"
  local files_count=$(echo "$catch1_info" | jq -r '.data.viewer.catches.edges[0].node.entityFiles.connection.edges | length')
  if [ "$files_count" -lt 2 ]; then
    fail "Catch (catchId=$catch1_id) has less than 2 files (got $files_count), cannot remove one file"
  fi
  local remaining_file=$(echo "$catch1_info" | jq -r '.data.viewer.catches.edges[0].node.entityFiles.connection.edges[0].node.id // empty')
  if [ -z "$remaining_file" ] || [ "$remaining_file" == "null" ]; then
    fail "Failed to get first file ID from catch (catchId=$catch1_id)"
  fi
  local keep_file=$(echo "$catch1_info" | jq -r '.data.viewer.catches.edges[0].node.entityFiles.connection.edges[1].node.id // empty')
  if [ -z "$keep_file" ] || [ "$keep_file" == "null" ]; then
    fail "Failed to get second file ID from catch (catchId=$catch1_id)"
  fi
  log "Removing file $remaining_file from catch (catchId=$catch1_id), keeping file $keep_file"
  local new_files=$(printf '%s\n' "$keep_file" | jq -R . | jq -s .)
  log "Updating catch files (catchId=$catch1_id) with filesIds: $(echo "$new_files" | jq -r 'join(", ")')"
  upd_files=$(mutation_update_catch_files "$catch1_id" "$new_files")
  echo "$upd_files" | jq '.' > "$OUT_DIR/step6_remove_file.json"
  local errors=$(echo "$upd_files" | jq -r '.data.updateCatch.errors // [] | length')
  if [ "$errors" -gt 0 ]; then
    log "ERROR updating catch files (catchId=$catch1_id):"
    echo "$upd_files" | jq '.data.updateCatch.errors'
    fail "Failed to update catch files"
  fi
  log "✓ File removed from catch (catchId=$catch1_id, removedFileId=$remaining_file, keptFileId=$keep_file)"
  sed -i '' "s/^${remaining_file},uploaded,/${remaining_file},used,/" "$UPLOADED_CSV" 2>/dev/null || sed -i "s/^${remaining_file},uploaded,/${remaining_file},used,/" "$UPLOADED_CSV"

  log_step "7"
  log "Проверить уменьшение файлов в catch, spot1 и waterbody1"
  log "Checking catch (catchId=${catch1_id:-N/A}), spot (spotId=$SPOT_ID_1), and waterbody (waterbodyId=$WATERBODY_ID_1)"
  log "Waiting ${SYNC_DELAY_SECONDS} seconds for synchronization..."
  sleep "$SYNC_DELAY_SECONDS"
  
  # Check catch files
  catch1_info_after=$(query_catch "$catch1_id")
  echo "$catch1_info_after" | jq '.' > "$OUT_DIR/step7_catch1_info_after.json"
  local catch1_files_after=$(echo "$catch1_info_after" | jq -r '.data.viewer.catches.edges[0].node.entityFiles.connection.edges | length')
  if [ "$catch1_files_after" != "1" ]; then
    fail "Expected 1 file in catch (catchId=$catch1_id), got $catch1_files_after"
  fi
  
  # Check spot files
  res7_spots=$(query_spots "$SPOT_ID_1" "$SPOT_ID_2")
  echo "$res7_spots" | jq '.' > "$OUT_DIR/step7_spots.json"
  local spot1_count_after=$(echo "$res7_spots" | jq -r --arg s1 "$SPOT_ID_1" '.data.spots.edges[] | select(.node.id==$s1) | .node.files.connection.edges | length')
  if [ "$spot1_count_after" != "1" ]; then
    fail "Expected 1 file in spot1 (spotId=$SPOT_ID_1, catchId=$catch1_id), got $spot1_count_after"
  fi
  
  # Check waterbody files
  res7_wb=$(query_waterbodies "$WATERBODY_ID_1" "$WATERBODY_ID_2")
  echo "$res7_wb" | jq '.' > "$OUT_DIR/step7_waterbodies.json"
  local wb1_count_after=$(echo "$res7_wb" | jq -r --arg wb1 "$WATERBODY_ID_1" '.data.waterbodies.edges[] | select(.node.id==$wb1) | .node.files.connection.edges | length')
  if [ "$wb1_count_after" != "1" ]; then
    fail "Expected 1 file in waterbody1 (waterbodyId=$WATERBODY_ID_1, spotId=$SPOT_ID_1, catchId=$catch1_id), got $wb1_count_after"
  fi
  log "✓ All three entities have 1 file each (catchId=$catch1_id, spotId=$SPOT_ID_1, waterbodyId=$WATERBODY_ID_1)"

  log_step "8"
  log "Сделать catch2 private (public=false) - файлы должны исчезнуть из spot2 и waterbody2, но остаться в catch2"
  if [ -n "${catch2_id:-}" ]; then
    log "Updating catch with id=$catch2_id to public=false"
    upd_c2=$(mutation_update_catch_public "$catch2_id" "false")
    echo "$upd_c2" | jq '.' > "$OUT_DIR/step8_make_private.json"
    local errors=$(echo "$upd_c2" | jq -r '.data.updateCatch.errors // [] | length')
    if [ "$errors" -gt 0 ]; then
      log "ERROR updating catch2 (catchId=$catch2_id):"
      echo "$upd_c2" | jq '.data.updateCatch.errors'
    else
      log "✓ Catch set to private (catchId=$catch2_id)"
    fi
  fi

  log_step "9"
  log "Проверить, что файлы исчезли из spot2 и waterbody2, но остались в catch2"
  log "Checking catch (catchId=${catch2_id:-N/A}), spot (spotId=$SPOT_ID_2), and waterbody (waterbodyId=$WATERBODY_ID_2)"
  log "Waiting ${SYNC_DELAY_SECONDS} seconds for synchronization..."
  sleep "$SYNC_DELAY_SECONDS"
  
  # Check catch files (should still have files)
  catch2_info_private=$(query_catch "$catch2_id")
  echo "$catch2_info_private" | jq '.' > "$OUT_DIR/step9_catch2_info_private.json"
  local catch2_files_private=$(echo "$catch2_info_private" | jq -r '.data.viewer.catches.edges[0].node.entityFiles.connection.edges | length')
  log "Catch (catchId=$catch2_id, private) has $catch2_files_private files"
  if [ "$catch2_files_private" != "2" ]; then
    fail "Expected 2 files in catch (catchId=$catch2_id, private catch), got $catch2_files_private"
  fi
  
  # Check spot files (should have 0 files)
  res9_spots=$(query_spots "$SPOT_ID_1" "$SPOT_ID_2")
  echo "$res9_spots" | jq '.' > "$OUT_DIR/step9_spots.json"
  local spot2_count_private=$(echo "$res9_spots" | jq -r --arg s2 "$SPOT_ID_2" '.data.spots.edges[] | select(.node.id==$s2) | .node.files.connection.edges | length')
  if [ "$spot2_count_private" != "0" ]; then
    fail "Expected 0 files in spot2 (spotId=$SPOT_ID_2, catchId=$catch2_id, private catch), got $spot2_count_private"
  fi
  
  # Check waterbody files (should have 0 files)
  res9_wb=$(query_waterbodies "$WATERBODY_ID_1" "$WATERBODY_ID_2")
  echo "$res9_wb" | jq '.' > "$OUT_DIR/step9_waterbodies.json"
  local wb2_count_private=$(echo "$res9_wb" | jq -r --arg wb2 "$WATERBODY_ID_2" '.data.waterbodies.edges[] | select(.node.id==$wb2) | .node.files.connection.edges | length')
  if [ "$wb2_count_private" != "0" ]; then
    fail "Expected 0 files in waterbody2 (waterbodyId=$WATERBODY_ID_2, spotId=$SPOT_ID_2, catchId=$catch2_id, private catch), got $wb2_count_private"
  fi
  log "✓ Catch has 2 files, spot2 and waterbody2 have 0 files (catchId=$catch2_id is private)"

  log_step "10"
  log "Вернуть catch2 публичным (public=true) - файлы должны снова появиться в spot2 и waterbody2"
  if [ -n "${catch2_id:-}" ]; then
    log "Updating catch with id=$catch2_id to public=true"
    upd_c2=$(mutation_update_catch_public "$catch2_id" "true")
    echo "$upd_c2" | jq '.' > "$OUT_DIR/step10_make_public.json"
    local errors=$(echo "$upd_c2" | jq -r '.data.updateCatch.errors // [] | length')
    if [ "$errors" -gt 0 ]; then
      log "ERROR updating catch2 (catchId=$catch2_id):"
      echo "$upd_c2" | jq '.data.updateCatch.errors'
    else
      log "✓ Catch set to public (catchId=$catch2_id)"
    fi
  fi

  log_step "11"
  log "Проверить, что файлы снова появились в spot2 и waterbody2"
  log "Checking catch (catchId=${catch2_id:-N/A}), spot (spotId=$SPOT_ID_2), and waterbody (waterbodyId=$WATERBODY_ID_2)"
  log "Waiting ${SYNC_DELAY_SECONDS} seconds for synchronization..."
  sleep "$SYNC_DELAY_SECONDS"
  
  # Check spot files
  res11_spots=$(query_spots "$SPOT_ID_1" "$SPOT_ID_2")
  echo "$res11_spots" | jq '.' > "$OUT_DIR/step11_spots.json"
  local spot2_count_public=$(echo "$res11_spots" | jq -r --arg s2 "$SPOT_ID_2" '.data.spots.edges[] | select(.node.id==$s2) | .node.files.connection.edges | length')
  if [ "$spot2_count_public" != "2" ]; then
    fail "Expected 2 files in spot2 (spotId=$SPOT_ID_2, catchId=$catch2_id, public catch), got $spot2_count_public"
  fi
  
  # Check waterbody files
  res11_wb=$(query_waterbodies "$WATERBODY_ID_1" "$WATERBODY_ID_2")
  echo "$res11_wb" | jq '.' > "$OUT_DIR/step11_waterbodies.json"
  local wb2_count_public=$(echo "$res11_wb" | jq -r --arg wb2 "$WATERBODY_ID_2" '.data.waterbodies.edges[] | select(.node.id==$wb2) | .node.files.connection.edges | length')
  if [ "$wb2_count_public" != "2" ]; then
    fail "Expected 2 files in waterbody2 (waterbodyId=$WATERBODY_ID_2, spotId=$SPOT_ID_2, catchId=$catch2_id, public catch), got $wb2_count_public"
  fi
  log "✓ All three entities have 2 files each again (catchId=$catch2_id, spotId=$SPOT_ID_2, waterbodyId=$WATERBODY_ID_2)"

  log_step "12"
  log "Изменить координаты catch2 на Канаду - файлы должны исчезнуть из spot2 и waterbody2, но остаться в catch2"
  if [ -n "${catch2_id:-}" ]; then
    log "Updating catch coordinates (catchId=$catch2_id) to Canada ($CANADA_LAT, $CANADA_LON)"
    upd_coords=$(mutation_update_catch_coords "$catch2_id" "$CANADA_LAT" "$CANADA_LON")
    echo "$upd_coords" | jq '.' > "$OUT_DIR/step12_coords_canada.json"
    local errors=$(echo "$upd_coords" | jq -r '.data.updateCatch.errors // [] | length')
    if [ "$errors" -gt 0 ]; then
      log "ERROR updating coordinates (catchId=$catch2_id):"
      echo "$upd_coords" | jq '.data.updateCatch.errors'
    else
      log "✓ Catch coordinates updated to Canada (catchId=$catch2_id, lat=$CANADA_LAT, lon=$CANADA_LON)"
    fi
  fi

  log_step "13"
  log "Проверить, что файлы исчезли из spot2 и waterbody2, но остались в catch2"
  log "Checking catch (catchId=${catch2_id:-N/A}), spot (spotId=$SPOT_ID_2), and waterbody (waterbodyId=$WATERBODY_ID_2)"
  log "Waiting ${SYNC_DELAY_SECONDS} seconds for synchronization..."
  sleep "$SYNC_DELAY_SECONDS"
  
  # Check catch files (should still have files)
  catch2_info_canada=$(query_catch "$catch2_id")
  echo "$catch2_info_canada" | jq '.' > "$OUT_DIR/step13_catch2_info_canada.json"
  local catch2_files_canada=$(echo "$catch2_info_canada" | jq -r '.data.viewer.catches.edges[0].node.entityFiles.connection.edges | length')
  log "Catch (catchId=$catch2_id, moved to Canada) has $catch2_files_canada files"
  if [ "$catch2_files_canada" != "2" ]; then
    fail "Expected 2 files in catch (catchId=$catch2_id, moved to Canada), got $catch2_files_canada"
  fi
  
  # Check spot files (should have 0 files)
  res13_spots=$(query_spots "$SPOT_ID_1" "$SPOT_ID_2")
  echo "$res13_spots" | jq '.' > "$OUT_DIR/step13_spots.json"
  local spot2_count_canada=$(echo "$res13_spots" | jq -r --arg s2 "$SPOT_ID_2" '.data.spots.edges[] | select(.node.id==$s2) | .node.files.connection.edges | length')
  if [ "$spot2_count_canada" != "0" ]; then
    fail "Expected 0 files in spot2 (spotId=$SPOT_ID_2, catchId=$catch2_id moved to Canada), got $spot2_count_canada"
  fi
  
  # Check waterbody files (should have 0 files)
  res13_wb=$(query_waterbodies "$WATERBODY_ID_1" "$WATERBODY_ID_2")
  echo "$res13_wb" | jq '.' > "$OUT_DIR/step13_waterbodies.json"
  local wb2_count_canada=$(echo "$res13_wb" | jq -r --arg wb2 "$WATERBODY_ID_2" '.data.waterbodies.edges[] | select(.node.id==$wb2) | .node.files.connection.edges | length')
  if [ "$wb2_count_canada" != "0" ]; then
    fail "Expected 0 files in waterbody2 (waterbodyId=$WATERBODY_ID_2, spotId=$SPOT_ID_2, catchId=$catch2_id moved to Canada), got $wb2_count_canada"
  fi
  log "✓ Catch has 2 files, spot2 and waterbody2 have 0 files (catchId=$catch2_id moved to Canada)"

  log_step "14"
  log "Вернуть координаты catch2 обратно - файлы должны снова появиться в spot2 и waterbody2"
  if [ -n "${catch2_id:-}" ]; then
    log "Restoring catch coordinates (catchId=$catch2_id) to ($SPOT2_LAT, $SPOT2_LON)"
    upd_coords=$(mutation_update_catch_coords "$catch2_id" "$SPOT2_LAT" "$SPOT2_LON")
    echo "$upd_coords" | jq '.' > "$OUT_DIR/step14_coords_back.json"
    local errors=$(echo "$upd_coords" | jq -r '.data.updateCatch.errors // [] | length')
    if [ "$errors" -gt 0 ]; then
      log "ERROR updating coordinates (catchId=$catch2_id):"
      echo "$upd_coords" | jq '.data.updateCatch.errors'
    else
      log "✓ Catch coordinates restored (catchId=$catch2_id, lat=$SPOT2_LAT, lon=$SPOT2_LON)"
    fi
  fi

  log_step "15"
  log "Проверить, что файлы снова появились в spot2 и waterbody2"
  log "Checking catch (catchId=${catch2_id:-N/A}), spot (spotId=$SPOT_ID_2), and waterbody (waterbodyId=$WATERBODY_ID_2)"
  log "Waiting ${SYNC_DELAY_SECONDS} seconds for synchronization..."
  sleep "$SYNC_DELAY_SECONDS"
  
  # Check spot files
  res15_spots=$(query_spots "$SPOT_ID_1" "$SPOT_ID_2")
  echo "$res15_spots" | jq '.' > "$OUT_DIR/step15_spots.json"
  local spot2_count_restored=$(echo "$res15_spots" | jq -r --arg s2 "$SPOT_ID_2" '.data.spots.edges[] | select(.node.id==$s2) | .node.files.connection.edges | length')
  if [ "$spot2_count_restored" != "2" ]; then
    fail "Expected 2 files in spot2 (spotId=$SPOT_ID_2, catchId=$catch2_id, coordinates restored), got $spot2_count_restored"
  fi
  
  # Check waterbody files
  res15_wb=$(query_waterbodies "$WATERBODY_ID_1" "$WATERBODY_ID_2")
  echo "$res15_wb" | jq '.' > "$OUT_DIR/step15_waterbodies.json"
  local wb2_count_restored=$(echo "$res15_wb" | jq -r --arg wb2 "$WATERBODY_ID_2" '.data.waterbodies.edges[] | select(.node.id==$wb2) | .node.files.connection.edges | length')
  if [ "$wb2_count_restored" != "2" ]; then
    fail "Expected 2 files in waterbody2 (waterbodyId=$WATERBODY_ID_2, spotId=$SPOT_ID_2, catchId=$catch2_id, coordinates restored), got $wb2_count_restored"
  fi
  log "✓ All three entities have 2 files each again (catchId=$catch2_id, spotId=$SPOT_ID_2, waterbodyId=$WATERBODY_ID_2)"

  log_step "16"
  log "Удалить catch1 - файлы должны исчезнуть из catch, spot1 и waterbody1"
  if [ -n "${catch1_id:-}" ]; then
    log "Deleting catch with id=$catch1_id"
    del_c1=$(mutation_delete_catch "$catch1_id")
    echo "$del_c1" | jq '.' > "$OUT_DIR/step16_delete_catch1.json"
    local errors=$(echo "$del_c1" | jq -r ".data.deleteCatch.errors // [] | length")
    if [ "$errors" -gt 0 ]; then
      log "ERROR deleting catch1:"
      echo "$del_c1" | jq ".data.deleteCatch.errors"
    else
      log "✓ Deleted catch with id=$catch1_id"
    fi
  fi

  log_step "17"
  log "Проверить, что файлы исчезли из spot1 и waterbody1"
  log "Checking spot (spotId=$SPOT_ID_1) and waterbody (waterbodyId=$WATERBODY_ID_1)"
  log "Waiting ${SYNC_DELAY_SECONDS} seconds for synchronization..."
  sleep "$SYNC_DELAY_SECONDS"
  
  # Check spot files
  res17_spots=$(query_spots "$SPOT_ID_1" "$SPOT_ID_2")
  echo "$res17_spots" | jq '.' > "$OUT_DIR/step17_spots.json"
  local spot1_count_after_delete=$(echo "$res17_spots" | jq -r --arg s1 "$SPOT_ID_1" '.data.spots.edges[] | select(.node.id==$s1) | .node.files.connection.edges | length')
  if [ "$spot1_count_after_delete" != "0" ]; then
    fail "Expected 0 files in spot1 (spotId=$SPOT_ID_1, catchId=$catch1_id deleted), got $spot1_count_after_delete"
  fi
  
  # Check waterbody files
  res17_wb=$(query_waterbodies "$WATERBODY_ID_1" "$WATERBODY_ID_2")
  echo "$res17_wb" | jq '.' > "$OUT_DIR/step17_waterbodies.json"
  local wb1_count_after_delete=$(echo "$res17_wb" | jq -r --arg wb1 "$WATERBODY_ID_1" '.data.waterbodies.edges[] | select(.node.id==$wb1) | .node.files.connection.edges | length')
  if [ "$wb1_count_after_delete" != "0" ]; then
    fail "Expected 0 files in waterbody1 (waterbodyId=$WATERBODY_ID_1, spotId=$SPOT_ID_1, catchId=$catch1_id deleted), got $wb1_count_after_delete"
  fi
  log "✓ Spot1 and waterbody1 have 0 files (catchId=$catch1_id deleted)"

  echo ""
  log "========== CATCH-SPOT-WATERBODY FILES_COUNT TEST COMPLETED SUCCESSFULLY =========="
}

main "$@"
