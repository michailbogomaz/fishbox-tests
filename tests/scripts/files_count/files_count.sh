#!/usr/bin/env bash
# Index script for running all files count tests
# cd /Users/mbogomaz/shared/fishbox/bff-graphql-service/.cursor/tests/scripts/files_count && ./files_count.sh prod
#cd /Users/mbogomaz/shared/fishbox/bff-graphql-service/.cursor/tests/scripts/files_count && ./files_count.sh prod > run_full.log 2>&1
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

# ===== Helpers =====
log() { echo "[$(date +%H:%M:%S)] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

# ===== Authentication =====
get_token() {
  log "Login to get token..."
  ACCESS_TOKEN=$(curl -s -X POST "$LOGIN_URL" \
    -H "Content-Type: application/json" \
    -H "client-id: $CLIENT_ID" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" | jq -r '.payload.access_token')
  [ -n "$ACCESS_TOKEN" ] && [ "$ACCESS_TOKEN" != "null" ] || fail "Cannot obtain access token"
  log "Token received"
  export ACCESS_TOKEN
}

# ===== Main flow =====
main() {
  log "Running files_count tests for environment: $ENV"
  log "API_GRAPHQL_URL: $API_GRAPHQL_URL"
  log "LOGIN_URL: $LOGIN_URL"
  log "EMAIL: $EMAIL"
  
  # Authenticate once for all tests
  get_token
  
  # Export environment variables for child scripts
  export API_GRAPHQL_URL
  export VIEWER_ID
  
  log ""
  log "========== Initial cleanup =========="
  "$SCRIPT_DIR/cleanup-files.sh"

  log ""
  log "========== Cleanup catches =========="
  "$SCRIPT_DIR/cleanup-catches.sh"
  
  log ""
  log "========== Waterbody ↔ Catch =========="
  "$SCRIPT_DIR/waterbody-catch-files-count.sh"

  log ""
  log "========== Initial cleanup =========="
  "$SCRIPT_DIR/cleanup-files.sh"

  log ""
  log "========== Cleanup catches =========="
  "$SCRIPT_DIR/cleanup-catches.sh"

    log ""
  log "========== Spot ↔ Catch =========="
  "$SCRIPT_DIR/spot-catch-files-count.sh"

    log ""
  log "========== Initial cleanup =========="
  "$SCRIPT_DIR/cleanup-files.sh"

  log ""
  log "========== Cleanup catches =========="
  "$SCRIPT_DIR/cleanup-catches.sh"

  log ""
  log "========== Spot ↔ Catch ↔ Waterbody =========="
  "$SCRIPT_DIR/catch-spot-waterbody-files-count.sh"

    log ""
  log "========== Initial cleanup =========="
  "$SCRIPT_DIR/cleanup-files.sh"

  log ""
  log "========== Cleanup catches =========="
  "$SCRIPT_DIR/cleanup-catches.sh"
  
  echo ""
  log "========== ALL FILES_COUNT TESTS COMPLETED SUCCESSFULLY =========="
}

main "$@"
