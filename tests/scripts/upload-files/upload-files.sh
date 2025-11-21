#!/usr/bin/env bash
# cd /Users/mbogomaz/shared/fishbox/bff-graphql-service/.cursor/tests/scripts/upload-files && ./upload-files.sh prod > run_full.log 2>&1

set -euo pipefail

# ===== Environment Configuration =====
ENV="${1:-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$ENV" != "dev" ] && [ "$ENV" != "prod" ]; then
  echo "Usage: $0 [dev|prod]" >&2
  # Load both env files to show API_GRAPHQL_URL
  if [ -f "$SCRIPT_DIR/../../env.dev.sh" ]; then
    source "$SCRIPT_DIR/../../env.dev.sh"
    echo "  dev  - $API_GRAPHQL_URL" >&2
  fi
  if [ -f "$SCRIPT_DIR/../../env.prod.sh" ]; then
    source "$SCRIPT_DIR/../../env.prod.sh"
    echo "  prod - $API_GRAPHQL_URL" >&2
  fi
  exit 1
fi

# Load environment-specific variables
ENV_FILE="$SCRIPT_DIR/../../env.$ENV.sh"
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: Environment file not found: $ENV_FILE" >&2
  exit 1
fi
source "$ENV_FILE"

DIR="$(cd "$(dirname "$0")" && pwd)"
FILES_DIR="$DIR/files"
CSV_FILE="$DIR/$UPLOADED_FILES_LIST_CSV"

# Login and get access token
echo "Logging in..."
ACCESS_TOKEN=$(curl -s -X POST "$API_LOGIN_URL" \
  -H "Content-Type: application/json" \
  -H "client-id: $CLIENT_ID" \
  -d "{
    \"email\": \"$EMAIL\",
    \"password\": \"$PASSWORD\"
  }" | jq -r '.payload.access_token')

if [ "$ACCESS_TOKEN" == "null" ] || [ -z "$ACCESS_TOKEN" ]; then
  echo "ERROR: Failed to get access token"
  exit 1
fi

echo "Access token obtained successfully"
echo ""

# Initialize CSV file (append if exists to preserve used files)
if [ ! -f "$CSV_FILE" ]; then
  echo "id,status,url" > "$CSV_FILE"
fi

# Function to create upload intent
create_upload_intent() {
  local file_name="$1"
  local file_path="$2"
  
  # Calculate all file parameters
  local file_size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null)
  # Calculate SHA-256 file hash in base64 format (as per documentation)
  local file_hash=$(shasum -a 256 "$file_path" | cut -d " " -f1 | xxd -r -p | base64)
  
  # Get image dimensions if it's an image
  local image_width=""
  local image_height=""
  
  # Try sips first (macOS)
  if command -v sips &> /dev/null; then
    image_width=$(sips -g pixelWidth "$file_path" 2>/dev/null | grep "pixelWidth" | awk '{print $2}')
    image_height=$(sips -g pixelHeight "$file_path" 2>/dev/null | grep "pixelHeight" | awk '{print $2}')
  # Try identify (ImageMagick)
  elif command -v identify &> /dev/null; then
    local dimensions=$(identify -format "%wx%h" "$file_path" 2>/dev/null || echo "")
    if [ -n "$dimensions" ]; then
      image_width=$(echo "$dimensions" | cut -d'x' -f1)
      image_height=$(echo "$dimensions" | cut -d'x' -f2)
    fi
  # Try to extract from file command output
  elif command -v file &> /dev/null; then
    local file_info=$(file "$file_path" 2>/dev/null)
    if echo "$file_info" | grep -qE '[0-9]+x[0-9]+'; then
      local dimensions=$(echo "$file_info" | grep -oE '[0-9]+x[0-9]+' | head -1)
      if [ -n "$dimensions" ]; then
        image_width=$(echo "$dimensions" | cut -d'x' -f1)
        image_height=$(echo "$dimensions" | cut -d'x' -f2)
      fi
    fi
  fi
  
  # Determine mime type
  local file_mime_type=""
  if command -v file &> /dev/null; then
    file_mime_type=$(file -b --mime-type "$file_path")
  else
    case "$file_name" in
      *.jpeg|*.jpg)
        file_mime_type="image/jpeg"
        ;;
      *.png)
        file_mime_type="image/png"
        ;;
      *.gif)
        file_mime_type="image/gif"
        ;;
      *)
        file_mime_type="application/octet-stream"
        ;;
    esac
  fi
  
  local query='mutation CreateImageUploadIntentMutation($input: CreateImageUploadIntentMutationInput!) {
    createImageUploadIntent(input: $input) {
      presignedForm {
        fields
        formActionUrl
        expires
      }
      image {
        id
        previewUrl(width: 200, height: 200, quality: 85)
      }
      errors {
        ... on MutationError {
          code
          message
        }
      }
    }
  }'
  
  # Build variables JSON with proper handling of optional image dimensions
  local variables_json
  if [ -n "$image_width" ] && [ -n "$image_height" ]; then
    variables_json=$(jq -n \
      --arg fileName "$file_name" \
      --arg fileMimeType "$file_mime_type" \
      --arg fileSize "$file_size" \
      --arg fileHash "$file_hash" \
      --arg intent "catch.create" \
      --argjson imageWidth "$image_width" \
      --argjson imageHeight "$image_height" \
      '{
        input: {
          fileName: $fileName,
          fileMimeType: $fileMimeType,
          fileSize: ($fileSize | tonumber),
          fileHash: $fileHash,
          intent: $intent,
          imageWidth: $imageWidth,
          imageHeight: $imageHeight
        }
      }')
  else
    variables_json=$(jq -n \
      --arg fileName "$file_name" \
      --arg fileMimeType "$file_mime_type" \
      --arg fileSize "$file_size" \
      --arg fileHash "$file_hash" \
      --arg intent "catch.create" \
      '{
        input: {
          fileName: $fileName,
          fileMimeType: $fileMimeType,
          fileSize: ($fileSize | tonumber),
          fileHash: $fileHash,
          intent: $intent
        }
      }')
  fi
  
  curl -s -X POST "$API_GRAPHQL_URL" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -H "User-Agent: insomnia/11.1.0" \
    -H "x-viewer-id: $VIEWER_ID" \
    -d "{
      \"query\": $(echo "$query" | jq -Rs .),
      \"operationName\": \"CreateImageUploadIntentMutation\",
      \"variables\": $variables_json
    }"
}

# Function to upload file using presigned form
upload_file() {
  local form_action_url="$1"
  local fields_json="$2"
  local file_path="$3"
  
  # Build curl command with all form fields
  # Use array to properly handle spaces and special characters
  local curl_args=()
  curl_args+=("-X" "POST")
  curl_args+=("-s")
  curl_args+=("-w" "\n%{http_code}")
  curl_args+=("$form_action_url")
  
  # Add all form fields from presigned form
  # fields_json is an object with key-value pairs
  while IFS=$'\t' read -r key value; do
    curl_args+=("-F" "$key=$value")
  done < <(echo "$fields_json" | jq -r 'to_entries[] | "\(.key)\t\(.value)"')
  
  # Add file - must be last field in the form
  curl_args+=("-F" "file=@$file_path")
  
  # Execute curl command
  curl "${curl_args[@]}"
}

# Process 100 files
echo "Starting file upload process..."
echo ""

for i in {1..100}; do
  file_name="fish_catch_test${i}.jpeg"
  file_path="$FILES_DIR/fish_catch_test${i}.jpeg"
  
  if [ ! -f "$file_path" ]; then
    echo "ERROR: File not found: $file_path"
    echo ",error,File not found" >> "$CSV_FILE"
    continue
  fi
  
  echo "Processing file $i/100: $file_name"
  
  # Calculate file hash for upload (will be used in upload function)
  # Calculate SHA-256 file hash in base64 format (as per documentation)
  file_hash=$(shasum -a 256 "$file_path" | cut -d " " -f1 | xxd -r -p | base64)
  
  # Debug: show file info
  file_size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null)
  echo "  File size: $file_size bytes"
  echo "  File hash: $file_hash"
  
  # Create upload intent (all parameters calculated inside function)
  intent_response=$(create_upload_intent "$file_name" "$file_path")
  
  # Check for errors
  if [ -z "$intent_response" ] || [ "$(echo "$intent_response" | jq -r '.data // empty')" == "" ]; then
    error_msg=$(echo "$intent_response" | jq -r '.errors[0].message // "Unknown error"')
    echo "ERROR: Failed to create upload intent: $error_msg"
    echo "$file_name,error,$error_msg" >> "$CSV_FILE"
    continue
  fi

  errors=$(echo "$intent_response" | jq -r '.data.createImageUploadIntent.errors // []')
  if [ "$(echo "$errors" | jq 'length')" -gt 0 ]; then
    error_msg=$(echo "$errors" | jq -r '.[0].message // "Unknown error"')
    echo "ERROR: Failed to create upload intent: $error_msg"
    echo "$file_name,error,$error_msg" >> "$CSV_FILE"
    continue
  fi
  
  # Extract presigned form data
  presigned_form=$(echo "$intent_response" | jq -r '.data.createImageUploadIntent.presignedForm')
  form_action_url=$(echo "$presigned_form" | jq -r '.formActionUrl')
  fields=$(echo "$presigned_form" | jq -r '.fields')
  image_id=$(echo "$intent_response" | jq -r '.data.createImageUploadIntent.image.id')
  
  if [ -z "$form_action_url" ] || [ "$form_action_url" == "null" ]; then
    echo "ERROR: No presigned form URL received"
    echo "$file_name,error,No presigned URL" >> "$CSV_FILE"
    continue
  fi
  
  # Build original file URL from formActionUrl and key
  # formActionUrl is like: https://fishbox-user-uploads.s3.us-east-1.amazonaws.com/
  # key is in fields like: 2025-11-06/0198f4e0-4442-70cb-81b6-2cc80d2689b1/019a5841-630c-77c8-af6f-a6fae9f5ba91.jpeg
  key=$(echo "$fields" | jq -r '.key // empty')
  if [ -n "$key" ] && [ "$key" != "null" ]; then
    # Remove trailing slash from formActionUrl if present
    base_url="${form_action_url%/}"
    original_url="${base_url}/${key}"
  else
    original_url=""
  fi
  
  # Debug: check hash in presigned form
  presigned_hash=$(echo "$fields" | jq -r '.["x-amz-checksum-sha256"] // empty')
  if [ -n "$presigned_hash" ] && [ "$presigned_hash" != "null" ]; then
    echo "  Presigned form hash: $presigned_hash"
    if [ "$presigned_hash" != "$file_hash" ]; then
      echo "  WARNING: Hash mismatch! Computed: $file_hash, Presigned: $presigned_hash"
    else
      echo "  Hash matches ✓"
    fi
  fi
  
  # Upload file
  echo "  Uploading file to presigned URL..."
  # Use fields exactly as provided - hash should already be in fields
  upload_response=$(upload_file "$form_action_url" "$fields" "$file_path")
  http_code=$(echo "$upload_response" | tail -n1)
  response_body=$(echo "$upload_response" | sed '$d')
  
  # Check upload status (204 No Content or 200 OK indicates success)
  if [ "$http_code" == "204" ] || [ "$http_code" == "200" ]; then
    echo "  File uploaded successfully (HTTP $http_code)"
    echo "$image_id,uploaded,$original_url" >> "$CSV_FILE"
  else
    echo "  ERROR: File upload failed (HTTP $http_code)"
    echo "  Response: $response_body"
    echo "$image_id,upload_failed,HTTP $http_code" >> "$CSV_FILE"
  fi
  
  echo ""
done

echo "Upload process completed!"
echo "Results saved to: $CSV_FILE"
echo ""
echo "Summary:"
tail -n +2 "$CSV_FILE" | cut -d',' -f2 | sort | uniq -c

