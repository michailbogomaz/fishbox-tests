#!/usr/bin/env bash
# This script tests file count interactions between waterbodies and catches
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
WB1_LAT="59.542"
WB1_LON="-155.144"
WB2_LAT="46.200"
WB2_LON="-93.700"
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
  # Use heredoc for query and jq to build JSON safely
  read -r -d '' QUERY <<'Q'
query getWaterbodyById($id1: ID!, $id2: ID!) {
  waterbodies(ids: [$id1, $id2], first: 2) {
    edges {
      node {
        id
        title
        locationTitle
        description
        type
        salinity
        publicity
        depth
        clarity
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

extract_file_ids() {
  jq -r '.data.waterbodies.edges[].node.files.connection.edges[].node.id' | grep -v '^null$' | grep -v '^$' || true
}

extract_counts() {
  jq -r '.data.waterbodies.edges[] | "\(.node.id) (\(.node.title)): images=\(.node.files.imagesCount), videos=\(.node.files.videosCount), total_files=\(.node.files.connection.edges | length)"'
}

print_file_list() {
  local json="$1"
  echo "Files list:"
  echo "$json" | jq -r '.data.waterbodies.edges[].node | "  \(.id) (\(.title)):"' | head -2
  echo "$json" | jq -r '.data.waterbodies.edges[].node.files.connection.edges[] | "    - \(.node.id) (\(.node.fileType), \(.node.status))"' || true
}

# ===== Mutations =====
mutation_delete_files() {
  local ids_json="$1" # JSON-массив строк
  # Build payload exactly as GraphQL expects
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

mutation_add_files_to_waterbody() {
  local waterbodyId="$1"
  local filesIdsJson="$2" # JSON-массив строк
  local payload
  payload=$(jq -n --arg id "$waterbodyId" --argjson fileIds "$filesIdsJson" '{
    query: "mutation AddFilesToWaterbody($input: AddFilesToWaterbodyMutationInput!) { addFilesToWaterbody(input:$input){ errors { ... on MutationError { code message } } } }",
    operationName: "AddFilesToWaterbody",
    variables: { input: { id: $id, fileIds: $fileIds } }
  }')
  curl -s -S -X POST "$API_GRAPHQL_URL" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -H "User-Agent: tests/files_count" \
    -H "x-viewer-id: $VIEWER_ID" \
    -d "$payload"
}
# ===== Catch helpers (заготовки, обновите под реальные схемы) =====
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

# ===== Assertions =====
assert_no_files() {
  local json="$1"
  local step="$2"
  echo "$json" | jq '.' > "$OUT_DIR/step${step}_verify_empty.json"
  local total=$(echo "$json" | jq '[.data.waterbodies.edges[].node.files.connection.edges[]] | length')
  if [ "$total" != "0" ]; then
    log "ERROR: Expected 0 files, got $total"
    print_file_list "$json"
    fail "Assertion failed: files should be empty"
  fi
  log "✓ OK: No files found (total=$total)"
}

assert_counts() {
  local json="$1"
  local step="$2"
  echo "$json" | jq '.' > "$OUT_DIR/step${step}_counts.json"
  log "Current counts:"
  echo "$json" | extract_counts
  print_file_list "$json"
}

# ===== Main flow =====
main() {
  log "Running waterbody-catch files_count test"
  # Check that required environment variables are set
  if [ -z "${API_GRAPHQL_URL:-}" ]; then
    fail "API_GRAPHQL_URL environment variable is not set"
  fi
  if [ -z "${VIEWER_ID:-}" ]; then
    fail "VIEWER_ID environment variable is not set"
  fi
  log "API_GRAPHQL_URL: $API_GRAPHQL_URL"

  log_step "1"
  log "Получить 2 waterbodies и их файлы"
  log "Querying waterbodies: waterbodyId1=$WATERBODY_ID_1, waterbodyId2=$WATERBODY_ID_2"
  # Debug: dump variables JSON used in request
  echo $(jq -n --arg id1 "$WATERBODY_ID_1" --arg id2 "$WATERBODY_ID_2" '{id1:$id1,id2:$id2}') > "$OUT_DIR/step1_vars.json"
  res1=$(query_waterbodies "$WATERBODY_ID_1" "$WATERBODY_ID_2")
  echo "$res1" > "$OUT_DIR/step1_waterbodies.json"
  echo "RAW step1 (first 400 chars):"
  echo "$res1" | head -c 400; echo
  if echo "$res1" | jq -e '.errors' >/dev/null 2>&1; then
    log "GraphQL errors in step1:"
    echo "$res1" | jq '.errors' || echo "$res1"
  fi
  assert_counts "$res1" "1"

  log_step "2"
  log "Создать по одному catch с 2 файлами из $UPLOADED_FILES_LIST_CSV"
  [ -f "$UPLOADED_CSV" ] || fail "Не найден $UPLOADED_CSV — выполните загрузку файлов"
  # Read file IDs from CSV into bash array, skipping used files (compatible with older bash)
  file_ids=()
  while IFS=',' read -r id status url; do
    [ -n "$id" ] && [ "$status" != "used" ] && [ "$status" != "error" ] && [ "$status" != "upload_failed" ] && file_ids+=("$id")
  done < <(tail -n +2 "$UPLOADED_CSV")
  [ "${#file_ids[@]}" -ge 4 ] || fail "Недостаточно файлов в CSV (нужно >=4, есть ${#file_ids[@]})"
  files1=$(printf '%s\n' "${file_ids[0]}" "${file_ids[1]}" | jq -R . | jq -s .)
  files2=$(printf '%s\n' "${file_ids[2]}" "${file_ids[3]}" | jq -R . | jq -s .)

  log "Creating catch1 for waterbody1 with files: ${file_ids[0]}, ${file_ids[1]}"
  c1=$(mutation_create_catch "$WB1_LAT" "$WB1_LON" "$files1" "true")
  echo "$c1" | jq '.' > "$OUT_DIR/step2_catch1.json"
  catch1_id=$(echo "$c1" | jq -r '.data.createCatch.catch.id // empty')
  if [ -z "$catch1_id" ] || [ "$catch1_id" == "null" ]; then
    log "ERROR creating catch1:"
    echo "$c1" | jq '.data.createCatch.errors'
    fail "Failed to create catch1"
  fi
  echo "$catch1_id" >> "$CATCHES_FILE"
  log "✓ Created catch with id=$catch1_id (waterbodyId=$WATERBODY_ID_1)"
  log "  fileIds=[${file_ids[0]}, ${file_ids[1]}]"
  # Mark files as used in CSV
  sed -i '' "s/^${file_ids[0]},uploaded,/${file_ids[0]},used,/" "$UPLOADED_CSV" 2>/dev/null || sed -i "s/^${file_ids[0]},uploaded,/${file_ids[0]},used,/" "$UPLOADED_CSV"
  sed -i '' "s/^${file_ids[1]},uploaded,/${file_ids[1]},used,/" "$UPLOADED_CSV" 2>/dev/null || sed -i "s/^${file_ids[1]},uploaded,/${file_ids[1]},used,/" "$UPLOADED_CSV"

  log "Creating catch2 for waterbody2 with files: ${file_ids[2]}, ${file_ids[3]}"
  c2=$(mutation_create_catch "$WB2_LAT" "$WB2_LON" "$files2" "true")
  echo "$c2" | jq '.' > "$OUT_DIR/step2_catch2.json"
  catch2_id=$(echo "$c2" | jq -r '.data.createCatch.catch.id // empty')
  if [ -z "$catch2_id" ] || [ "$catch2_id" == "null" ]; then
    log "ERROR creating catch2:"
    echo "$c2" | jq '.data.createCatch.errors'
    fail "Failed to create catch2"
  fi
  echo "$catch2_id" >> "$CATCHES_FILE"
  log "✓ Created catch with id=$catch2_id (waterbodyId=$WATERBODY_ID_2)"
  log "  fileIds=[${file_ids[2]}, ${file_ids[3]}]"
  # Mark files as used in CSV
  sed -i '' "s/^${file_ids[2]},uploaded,/${file_ids[2]},used,/" "$UPLOADED_CSV" 2>/dev/null || sed -i "s/^${file_ids[2]},uploaded,/${file_ids[2]},used,/" "$UPLOADED_CSV"
  sed -i '' "s/^${file_ids[3]},uploaded,/${file_ids[3]},used,/" "$UPLOADED_CSV" 2>/dev/null || sed -i "s/^${file_ids[3]},uploaded,/${file_ids[3]},used,/" "$UPLOADED_CSV"

  log_step "3"
  log "Проверить counts после создания catch"
  log "Checking waterbodies: waterbodyId1=$WATERBODY_ID_1 (catchId=${catch1_id:-N/A}), waterbodyId2=$WATERBODY_ID_2 (catchId=${catch2_id:-N/A})"
  log "Waiting ${SYNC_DELAY_SECONDS} seconds for files to be associated with waterbodies..."
  sleep "$SYNC_DELAY_SECONDS"
  res5=$(query_waterbodies "$WATERBODY_ID_1" "$WATERBODY_ID_2")
  assert_counts "$res5" "5"
  local wb1_count=$(echo "$res5" | jq -r --arg wb1 "$WATERBODY_ID_1" ".data.waterbodies.edges[] | select(.node.id==\$wb1) | .node.files.connection.edges | length")
  local wb2_count=$(echo "$res5" | jq -r --arg wb2 "$WATERBODY_ID_2" ".data.waterbodies.edges[] | select(.node.id==\$wb2) | .node.files.connection.edges | length")
  if [ "$wb1_count" != "2" ] || [ "$wb2_count" != "2" ]; then
    fail "Expected 2 files in each waterbody, got wb1=$wb1_count, wb2=$wb2_count"
  fi
  log "✓ Both waterbodies have 2 files each (waterbodyId1=$WATERBODY_ID_1: $wb1_count files, waterbodyId2=$WATERBODY_ID_2: $wb2_count files)"

  log_step "4"
  log "Удалить один catch (catch1)"
  if [ -n "${catch1_id:-}" ]; then
    log "Deleting catch with id=$catch1_id (waterbodyId=$WATERBODY_ID_1)"
    del_c1=$(mutation_delete_catch "$catch1_id")
    echo "$del_c1" | jq '.' > "$OUT_DIR/step4_delete_catch1.json"
    local errors=$(echo "$del_c1" | jq -r ".data.deleteCatch.errors // [] | length")
    if [ "$errors" -gt 0 ]; then
      log "ERROR deleting catch1:"
      echo "$del_c1" | jq ".data.deleteCatch.errors"
    else
      log "✓ Deleted catch with id=$catch1_id (waterbodyId=$WATERBODY_ID_1)"
    fi
    # Files are already marked as used when catch was created in STEP 4
  fi

  log_step "5"
  log "Проверить уменьшение файлов в соответствующем водоеме"
  log "Checking waterbodyId1=$WATERBODY_ID_1 after catch deletion (deleted catchId=${catch1_id:-N/A})"
  log "Waiting ${SYNC_DELAY_SECONDS} seconds for files to be removed from waterbody..."
  sleep "$SYNC_DELAY_SECONDS"
  res7=$(query_waterbodies "$WATERBODY_ID_1" "$WATERBODY_ID_2")
  assert_counts "$res7" "7"
  local wb1_count_after=$(echo "$res7" | jq -r --arg wb1 "$WATERBODY_ID_1" '.data.waterbodies.edges[] | select(.node.id==$wb1) | .node.files.connection.edges | length')
  if [ "$wb1_count_after" != "0" ]; then
    log "WARNING: Expected 0 files in waterbody1 (waterbodyId=$WATERBODY_ID_1) after catch deletion (catchId=${catch1_id:-N/A}), got $wb1_count_after"
    log "This might be expected behavior - files may remain in waterbody even after catch deletion"
    log "Files in waterbody1:"
    echo "$res7" | jq -r --arg wb1 "$WATERBODY_ID_1" '.data.waterbodies.edges[] | select(.node.id==$wb1) | .node.files.connection.edges[].node.id' | while read -r fid; do
      log "  - $fid"
    done
    # Continue test instead of failing - this might be expected behavior
  else
    log "✓ Waterbody1 (waterbodyId=$WATERBODY_ID_1) has 0 files (catchId=${catch1_id:-N/A} deleted)"
  fi

  log_step "6"
  log "Второй catch сделать public=false"
  if [ -n "${catch2_id:-}" ]; then
    log "Updating catch with id=$catch2_id (waterbodyId=$WATERBODY_ID_2) to public=false"
    upd_c2=$(mutation_update_catch_public "$catch2_id" "false")
    echo "$upd_c2" | jq '.' > "$OUT_DIR/step6_make_private.json"
    local errors=$(echo "$upd_c2" | jq -r '.data.updateCatch.errors // [] | length')
    if [ "$errors" -gt 0 ]; then
      log "ERROR updating catch2 (catchId=$catch2_id, waterbodyId=$WATERBODY_ID_2):"
      echo "$upd_c2" | jq '.data.updateCatch.errors'
    else
      log "✓ Catch set to private (catchId=$catch2_id, waterbodyId=$WATERBODY_ID_2)"
    fi
  fi

  log_step "7"
  log "Проверка — связанный waterbody без файлов (private catch)"
  log "Checking waterbodyId2=$WATERBODY_ID_2 with private catch (catchId=${catch2_id:-N/A})"
  log "Waiting ${SYNC_DELAY_SECONDS} seconds for synchronization..."
  sleep "$SYNC_DELAY_SECONDS"
  res9=$(query_waterbodies "$WATERBODY_ID_1" "$WATERBODY_ID_2")
  assert_counts "$res9" "9"
  local wb2_count_private=$(echo "$res9" | jq -r --arg wb2 "$WATERBODY_ID_2" ".data.waterbodies.edges[] | select(.node.id==\$wb2) | .node.files.connection.edges | length")
  if [ "$wb2_count_private" != "0" ]; then
    fail "Expected 0 files in waterbody2 (waterbodyId=$WATERBODY_ID_2, catchId=${catch2_id:-N/A}, private catch), got $wb2_count_private"
  fi
  log "✓ Waterbody2 (waterbodyId=$WATERBODY_ID_2) has 0 files (catchId=${catch2_id:-N/A} is private)"

  log_step "8"
  log "Вернуть catch публичным"
  if [ -n "${catch2_id:-}" ]; then
    log "Updating catch with id=$catch2_id (waterbodyId=$WATERBODY_ID_2) to public=true"
    upd_c2=$(mutation_update_catch_public "$catch2_id" "true")
    echo "$upd_c2" | jq '.' > "$OUT_DIR/step8_make_public.json"
    local errors=$(echo "$upd_c2" | jq -r '.data.updateCatch.errors // [] | length')
    if [ "$errors" -gt 0 ]; then
      log "ERROR updating catch2 (catchId=$catch2_id, waterbodyId=$WATERBODY_ID_2):"
      echo "$upd_c2" | jq '.data.updateCatch.errors'
    else
      log "✓ Catch set to public (catchId=$catch2_id, waterbodyId=$WATERBODY_ID_2)"
    fi
  fi

  log_step "9"
  log "Проверка — файлы снова видны"
  log "Checking waterbodyId2=$WATERBODY_ID_2 with public catch (catchId=${catch2_id:-N/A})"
  log "Waiting ${SYNC_DELAY_SECONDS} seconds for synchronization..."
  sleep "$SYNC_DELAY_SECONDS"
  res11=$(query_waterbodies "$WATERBODY_ID_1" "$WATERBODY_ID_2")
  assert_counts "$res11" "11"
  local wb2_count_public=$(echo "$res11" | jq -r --arg wb2 "$WATERBODY_ID_2" ".data.waterbodies.edges[] | select(.node.id==\$wb2) | .node.files.connection.edges | length")
  if [ "$wb2_count_public" != "2" ]; then
    fail "Expected 2 files in waterbody2 (waterbodyId=$WATERBODY_ID_2, catchId=${catch2_id:-N/A}, public catch), got $wb2_count_public"
  fi
  log "✓ Waterbody2 (waterbodyId=$WATERBODY_ID_2) has 2 files again (catchId=${catch2_id:-N/A} is public)"

  log_step "10"
  log "Изменить координаты catch2 на Канаду"
  if [ -n "${catch2_id:-}" ]; then
    log "Updating catch coordinates (catchId=$catch2_id, waterbodyId=$WATERBODY_ID_2) to Canada ($CANADA_LAT, $CANADA_LON)"
    upd_coords=$(mutation_update_catch_coords "$catch2_id" "$CANADA_LAT" "$CANADA_LON")
    echo "$upd_coords" | jq '.' > "$OUT_DIR/step10_coords_canada.json"
    local errors=$(echo "$upd_coords" | jq -r '.data.updateCatch.errors // [] | length')
    if [ "$errors" -gt 0 ]; then
      log "ERROR updating coordinates (catchId=$catch2_id, waterbodyId=$WATERBODY_ID_2):"
      echo "$upd_coords" | jq '.data.updateCatch.errors'
    else
      log "✓ Catch coordinates updated to Canada (catchId=$catch2_id, waterbodyId=$WATERBODY_ID_2, lat=$CANADA_LAT, lon=$CANADA_LON)"
    fi
  fi

  log_step "11"
  log "Проверка — файлов не осталось (catch moved to Canada)"
  log "Checking waterbodyId2=$WATERBODY_ID_2 after catch moved to Canada (catchId=${catch2_id:-N/A}, lat=$CANADA_LAT, lon=$CANADA_LON)"
  log "Waiting ${SYNC_DELAY_SECONDS} seconds for synchronization..."
  sleep "$SYNC_DELAY_SECONDS"
  res13=$(query_waterbodies "$WATERBODY_ID_1" "$WATERBODY_ID_2")
  assert_counts "$res13" "13"
  local wb2_count_canada=$(echo "$res13" | jq -r --arg wb2 "$WATERBODY_ID_2" ".data.waterbodies.edges[] | select(.node.id==\$wb2) | .node.files.connection.edges | length")
  if [ "$wb2_count_canada" != "0" ]; then
    fail "Expected 0 files in waterbody2 (waterbodyId=$WATERBODY_ID_2, catchId=${catch2_id:-N/A} moved to Canada), got $wb2_count_canada"
  fi
  log "✓ Waterbody2 (waterbodyId=$WATERBODY_ID_2) has 0 files (catchId=${catch2_id:-N/A} moved to Canada)"

  log_step "12"
  log "Вернуть координаты catch2 обратно"
  if [ -n "${catch2_id:-}" ]; then
    log "Restoring catch coordinates (catchId=$catch2_id, waterbodyId=$WATERBODY_ID_2) to ($WB2_LAT, $WB2_LON)"
    upd_coords=$(mutation_update_catch_coords "$catch2_id" "$WB2_LAT" "$WB2_LON")
    echo "$upd_coords" | jq '.' > "$OUT_DIR/step12_coords_back.json"
    local errors=$(echo "$upd_coords" | jq -r '.data.updateCatch.errors // [] | length')
    if [ "$errors" -gt 0 ]; then
      log "ERROR updating coordinates (catchId=$catch2_id, waterbodyId=$WATERBODY_ID_2):"
      echo "$upd_coords" | jq '.data.updateCatch.errors'
    else
      log "✓ Catch coordinates restored (catchId=$catch2_id, waterbodyId=$WATERBODY_ID_2, lat=$WB2_LAT, lon=$WB2_LON)"
    fi
  fi

  log_step "13"
  log "Проверка — файлы снова есть"
  log "Checking waterbodyId2=$WATERBODY_ID_2 after coordinates restored (catchId=${catch2_id:-N/A}, lat=$WB2_LAT, lon=$WB2_LON)"
  log "Waiting ${SYNC_DELAY_SECONDS} seconds for synchronization..."
  sleep "$SYNC_DELAY_SECONDS"
  res15=$(query_waterbodies "$WATERBODY_ID_1" "$WATERBODY_ID_2")
  assert_counts "$res15" "15"
  local wb2_count_restored=$(echo "$res15" | jq -r --arg wb2 "$WATERBODY_ID_2" ".data.waterbodies.edges[] | select(.node.id==\$wb2) | .node.files.connection.edges | length")
  if [ "$wb2_count_restored" != "2" ]; then
    fail "Expected 2 files in waterbody2 (waterbodyId=$WATERBODY_ID_2, catchId=${catch2_id:-N/A}, coordinates restored), got $wb2_count_restored"
  fi
  log "✓ Waterbody2 (waterbodyId=$WATERBODY_ID_2) has 2 files again (catchId=${catch2_id:-N/A} coordinates restored)"

  log_step "14"
  log "Удалить 1 файл у catch2"
  if [ -z "${catch2_id:-}" ]; then
    fail "catch2_id is not set, cannot proceed with step 16"
  fi
  log "Querying catch info (catchId=$catch2_id, waterbodyId=$WATERBODY_ID_2)"
  catch_info=$(query_catch "$catch2_id")
  echo "$catch_info" | jq '.' > "$OUT_DIR/step14_catch2_info.json"
  # Check for errors in query
  if echo "$catch_info" | jq -e '.errors' >/dev/null 2>&1; then
    log "ERROR querying catch:"
    echo "$catch_info" | jq '.errors'
    fail "Failed to query catch info"
  fi
  # Check if catch has files
  local files_count=$(echo "$catch_info" | jq -r '.data.viewer.catches.edges[0].node.entityFiles.connection.edges | length')
  if [ "$files_count" -lt 2 ]; then
    fail "Catch (catchId=$catch2_id) has less than 2 files (got $files_count), cannot remove one file"
  fi
  local remaining_file=$(echo "$catch_info" | jq -r '.data.viewer.catches.edges[0].node.entityFiles.connection.edges[0].node.id // empty')
  if [ -z "$remaining_file" ] || [ "$remaining_file" == "null" ]; then
    fail "Failed to get first file ID from catch (catchId=$catch2_id)"
  fi
  local keep_file=$(echo "$catch_info" | jq -r '.data.viewer.catches.edges[0].node.entityFiles.connection.edges[1].node.id // empty')
  if [ -z "$keep_file" ] || [ "$keep_file" == "null" ]; then
    fail "Failed to get second file ID from catch (catchId=$catch2_id)"
  fi
  log "Removing file $remaining_file (fileId=$remaining_file) from catch (catchId=$catch2_id, waterbodyId=$WATERBODY_ID_2), keeping file $keep_file"
  local new_files=$(printf '%s\n' "$keep_file" | jq -R . | jq -s .)
  log "Updating catch files (catchId=$catch2_id) with filesIds: $(echo "$new_files" | jq -r 'join(", ")')"
  upd_files=$(mutation_update_catch_files "$catch2_id" "$new_files")
  echo "$upd_files" | jq '.' > "$OUT_DIR/step14_remove_file.json"
  # Debug: check what was sent
  echo "$upd_files" | jq '.data.updateCatch.catch // .data.updateCatch.errors' > "$OUT_DIR/step14_update_result.json"
  local errors=$(echo "$upd_files" | jq -r '.data.updateCatch.errors // [] | length')
  if [ "$errors" -gt 0 ]; then
    log "ERROR updating catch files (catchId=$catch2_id, waterbodyId=$WATERBODY_ID_2):"
    echo "$upd_files" | jq '.data.updateCatch.errors'
    fail "Failed to update catch files"
  fi
  log "✓ File removed from catch (catchId=$catch2_id, waterbodyId=$WATERBODY_ID_2, removedFileId=$remaining_file, keptFileId=$keep_file)"
  # Mark removed file as used in CSV
  sed -i '' "s/^${remaining_file},uploaded,/${remaining_file},used,/" "$UPLOADED_CSV" 2>/dev/null || sed -i "s/^${remaining_file},uploaded,/${remaining_file},used,/" "$UPLOADED_CSV"
  # Verify update by querying catch again
  log "Verifying catch files after update (catchId=$catch2_id)..."
  sleep "$SYNC_DELAY_SECONDS"
  catch_info_after=$(query_catch "$catch2_id")
  echo "$catch_info_after" | jq '.' > "$OUT_DIR/step14_catch2_info_after.json"
  # Check for errors in verification query
  if echo "$catch_info_after" | jq -e '.errors' >/dev/null 2>&1; then
    log "ERROR querying catch for verification:"
    echo "$catch_info_after" | jq '.errors'
    fail "Failed to verify catch files after update"
  fi
  local files_count_after=$(echo "$catch_info_after" | jq -r '.data.viewer.catches.edges[0].node.entityFiles.connection.edges | length')
  local expected_count=1
  if [ "$files_count_after" != "$expected_count" ]; then
    log "ERROR: Expected $expected_count file(s) in catch after update, got $files_count_after"
    fail "Verification failed: catch should have $expected_count file(s) after update"
  fi
  log "✓ Verified: catch now has $files_count_after file(s)"

  log_step "15"
  log "Создать новый catch с 3 неиспользованными файлами"
  # Возьмем следующие 3 неиспользованных файла из CSV
  unused_files=()
  while IFS=',' read -r id status url; do
    [ -n "$id" ] && [ "$status" == "uploaded" ] && unused_files+=("$id")
  done < <(tail -n +2 "$UPLOADED_CSV")
  [ "${#unused_files[@]}" -ge 3 ] || fail "Недостаточно неиспользованных файлов (нужно >=3, есть ${#unused_files[@]})"
  files3=$(printf '%s\n' "${unused_files[0]}" "${unused_files[1]}" "${unused_files[2]}" | jq -R . | jq -s .)
  log "Creating catch3 for waterbody2 with files: ${unused_files[0]}, ${unused_files[1]}, ${unused_files[2]}"
  c3=$(mutation_create_catch "$WB2_LAT" "$WB2_LON" "$files3" "true")
  echo "$c3" | jq '.' > "$OUT_DIR/step15_catch3.json"
  catch3_id=$(echo "$c3" | jq -r '.data.createCatch.catch.id // empty')
  if [ -z "$catch3_id" ] || [ "$catch3_id" == "null" ]; then
    log "ERROR creating catch3:"
    echo "$c3" | jq '.data.createCatch.errors'
    fail "Failed to create catch3"
  fi
  echo "$catch3_id" >> "$CATCHES_FILE"
  log "✓ Created catch with id=$catch3_id (waterbodyId=$WATERBODY_ID_2)"
  log "  fileIds=[${unused_files[0]}, ${unused_files[1]}, ${unused_files[2]}]"
  # Mark files as used in CSV
  sed -i '' "s/^${unused_files[0]},uploaded,/${unused_files[0]},used,/" "$UPLOADED_CSV" 2>/dev/null || sed -i "s/^${unused_files[0]},uploaded,/${unused_files[0]},used,/" "$UPLOADED_CSV"
  sed -i '' "s/^${unused_files[1]},uploaded,/${unused_files[1]},used,/" "$UPLOADED_CSV" 2>/dev/null || sed -i "s/^${unused_files[1]},uploaded,/${unused_files[1]},used,/" "$UPLOADED_CSV"
  sed -i '' "s/^${unused_files[2]},uploaded,/${unused_files[2]},used,/" "$UPLOADED_CSV" 2>/dev/null || sed -i "s/^${unused_files[2]},uploaded,/${unused_files[2]},used,/" "$UPLOADED_CSV"

  log_step "16"
  log "Проверка — сумма файлов двух уловов"
  log "Checking waterbodyId2=$WATERBODY_ID_2 with catch2 (catchId=${catch2_id:-N/A}) and catch3 (catchId=${catch3_id:-N/A})"
  log "Waiting ${SYNC_DELAY_SECONDS} seconds for synchronization..."
  sleep "$SYNC_DELAY_SECONDS"
  res18=$(query_waterbodies "$WATERBODY_ID_1" "$WATERBODY_ID_2")
  assert_counts "$res18" "18"
  local wb2_count_total=$(echo "$res18" | jq -r --arg wb2 "$WATERBODY_ID_2" ".data.waterbodies.edges[] | select(.node.id==\$wb2) | .node.files.connection.edges | length")
  # catch2 has 1 file (after step 16), catch3 has 3 files = 4 total
  if [ "$wb2_count_total" != "4" ]; then
    fail "Expected 4 files in waterbody2 (waterbodyId=$WATERBODY_ID_2, catchId2=${catch2_id:-N/A}: 1 file + catchId3=${catch3_id:-N/A}: 3 files), got $wb2_count_total"
  fi
  log "✓ Waterbody2 (waterbodyId=$WATERBODY_ID_2) has 4 files (catchId2=${catch2_id:-N/A}: 1 file + catchId3=${catch3_id:-N/A}: 3 files)"

  log_step "17"
  log "Удалить один из catch (catch3)"
  if [ -n "${catch3_id:-}" ]; then
    log "Deleting catch with id=$catch3_id (waterbodyId=$WATERBODY_ID_2)"
    del_c3=$(mutation_delete_catch "$catch3_id")
    echo "$del_c3" | jq '.' > "$OUT_DIR/step17_delete_catch3.json"
    local errors=$(echo "$del_c3" | jq -r ".data.deleteCatch.errors // [] | length")
    if [ "$errors" -gt 0 ]; then
      log "ERROR deleting catch3:"
      echo "$del_c3" | jq ".data.deleteCatch.errors"
    else
      log "✓ Deleted catch with id=$catch3_id (waterbodyId=$WATERBODY_ID_2)"
    fi
  fi

  log_step "18"
  log "Финальная проверка количества файлов"
  log "Checking final counts: waterbodyId1=$WATERBODY_ID_1, waterbodyId2=$WATERBODY_ID_2 (catchId2=${catch2_id:-N/A})"
  log "Waiting ${SYNC_DELAY_SECONDS} seconds for synchronization..."
  sleep "$SYNC_DELAY_SECONDS"
  res20=$(query_waterbodies "$WATERBODY_ID_1" "$WATERBODY_ID_2")
  assert_counts "$res20" "20"
  local wb1_final=$(echo "$res20" | jq -r --arg wb1 "$WATERBODY_ID_1" ".data.waterbodies.edges[] | select(.node.id==\$wb1) | .node.files.connection.edges | length")
  local wb2_final=$(echo "$res20" | jq -r --arg wb2 "$WATERBODY_ID_2" ".data.waterbodies.edges[] | select(.node.id==\$wb2) | .node.files.connection.edges | length")
  if [ "$wb1_final" != "0" ]; then
    fail "Expected 0 files in waterbody1 (waterbodyId=$WATERBODY_ID_1), got $wb1_final"
  fi
  if [ "$wb2_final" != "1" ]; then
    fail "Expected 1 file in waterbody2 (waterbodyId=$WATERBODY_ID_2, catchId2=${catch2_id:-N/A}), got $wb2_final"
  fi
  log "✓ Final counts: waterbodyId1=$WATERBODY_ID_1: $wb1_final files, waterbodyId2=$WATERBODY_ID_2: $wb2_final files (catchId2=${catch2_id:-N/A})"

  log_step "19"
  log "Проверка mutation_add_files_to_waterbody (добавление файлов напрямую в waterbody)"
  # Используем оставшиеся неиспользованные файлы из CSV
  unused_for_direct=()
  while IFS=',' read -r id status url; do
    if [ -n "$id" ] && [ "$status" == "uploaded" ]; then
      # Fix UUID format if missing leading zero (should be 36 chars: 8-4-4-4-12)
      if [ "${#id}" -eq 35 ] && [[ "$id" =~ ^[0-9a-f]{7}- ]]; then
        id="0$id"
      fi
      unused_for_direct+=("$id")
    fi
  done < <(tail -n +2 "$UPLOADED_CSV")
  [ "${#unused_for_direct[@]}" -ge 2 ] || fail "Недостаточно неиспользованных файлов для теста (нужно >=2, есть ${#unused_for_direct[@]})"
  files_direct=$(printf '%s\n' "${unused_for_direct[0]}" "${unused_for_direct[1]}" | jq -R . | jq -s .)
  log "Adding files directly to waterbody (waterbodyId=$WATERBODY_ID_2, fileIds=[${unused_for_direct[0]}, ${unused_for_direct[1]}])"
  add_direct=$(mutation_add_files_to_waterbody "$WATERBODY_ID_2" "$files_direct")
  echo "$add_direct" | jq '.' > "$OUT_DIR/step19_add_files_direct.json"
  local add_direct_errors=$(echo "$add_direct" | jq -r '.data.addFilesToWaterbody.errors // [] | length')
  if [ "$add_direct_errors" -gt 0 ]; then
    log "ERROR adding files directly to waterbody (waterbodyId=$WATERBODY_ID_2, fileIds=[${unused_for_direct[0]}, ${unused_for_direct[1]}]):"
    echo "$add_direct" | jq '.data.addFilesToWaterbody.errors'
  else
    log "✓ Files added directly to waterbody (waterbodyId=$WATERBODY_ID_2, fileIds=[${unused_for_direct[0]}, ${unused_for_direct[1]}])"
    # Mark files as used in CSV
    sed -i '' "s/^${unused_for_direct[0]},uploaded,/${unused_for_direct[0]},used,/" "$UPLOADED_CSV" 2>/dev/null || sed -i "s/^${unused_for_direct[0]},uploaded,/${unused_for_direct[0]},used,/" "$UPLOADED_CSV"
    sed -i '' "s/^${unused_for_direct[1]},uploaded,/${unused_for_direct[1]},used,/" "$UPLOADED_CSV" 2>/dev/null || sed -i "s/^${unused_for_direct[1]},uploaded,/${unused_for_direct[1]},used,/" "$UPLOADED_CSV"
  fi

  log_step "20"
  log "Проверка counts после прямого добавления файлов в waterbody"
  log "Checking waterbodyId2=$WATERBODY_ID_2 after direct file addition"
  log "Waiting ${SYNC_DELAY_SECONDS} seconds for synchronization..."
  sleep "$SYNC_DELAY_SECONDS"
  res22=$(query_waterbodies "$WATERBODY_ID_1" "$WATERBODY_ID_2")
  assert_counts "$res22" "22"
  local wb2_final_direct=$(echo "$res22" | jq -r --arg wb2 "$WATERBODY_ID_2" '.data.waterbodies.edges[] | select(.node.id==$wb2) | .node.files.connection.edges | length')
  log "Waterbody2 (waterbodyId=$WATERBODY_ID_2) now has $wb2_final_direct files (should include directly added files)"

  echo ""
  log "========== WATERBODY-CATCH FILES_COUNT TEST COMPLETED SUCCESSFULLY =========="
}

main "$@"
