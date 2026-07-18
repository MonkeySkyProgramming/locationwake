#!/usr/bin/env bash
set -euo pipefail

# Local-LLM orchestration entry point. Ollama approves the scoped request;
# only the fixed runner invokes asc or receives credentials.
PROFILE="ASC API KEY"
APP_ID=""
WORKSPACE="locationwake.xcworkspace"
SCHEME="locationwake"
EXPORT_OPTIONS=""
EXISTING_IPA=""
ARCHIVE_PATH=".asc/artifacts/locationwake.xcarchive"
IPA_PATH=".asc/artifacts/locationwake.ipa"
VERIFY_TIMEOUT="10m"
BUILD_NUMBER=""
DRY_RUN=false
CONFIRM_UPLOAD=false
OLLAMA_URL="${OLLAMA_URL:-http://127.0.0.1:11434}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen3.5:4b}"
REQUEST_TEXT=""
AUTO_RESOLVE=false

usage() {
  cat <<'EOF'
Usage:
  scripts/asc-ollama-upload.sh --request TEXT [--auto-resolve] [--app-id APP_ID] [--export-options PATH | --existing-ipa PATH] [options]

Options:
  --profile NAME              Explicit ASC profile (default: ASC API KEY)
  --app-id ID                 App Store Connect app ID for 起きなはれ
  --export-options PATH       Build/archive/export locally
  --existing-ipa PATH         Upload an existing IPA (skips build)
  --workspace PATH            Xcode workspace
  --scheme NAME               Xcode scheme
  --archive-path PATH         Archive output path
  --ipa-path PATH             IPA output path
  --verify-timeout DURATION   Upload verification timeout
  --build-number NUMBER       Build number selected for this run
  --auto-resolve              Resolve the app ID and next build number before local-LLM review
  --dry-run                   Plan and validate without uploading
  --confirm-upload            Explicitly authorize a real upload
  --request TEXT              Original user request, forwarded unchanged
  -h, --help                  Show this help
EOF
}

while (($#)); do
  case "$1" in
    --profile) PROFILE="${2:?missing value for --profile}"; shift 2 ;;
    --app-id) APP_ID="${2:?missing value for --app-id}"; shift 2 ;;
    --export-options) EXPORT_OPTIONS="${2:?missing value for --export-options}"; shift 2 ;;
    --existing-ipa) EXISTING_IPA="${2:?missing value for --existing-ipa}"; shift 2 ;;
    --workspace) WORKSPACE="${2:?missing value for --workspace}"; shift 2 ;;
    --scheme) SCHEME="${2:?missing value for --scheme}"; shift 2 ;;
    --archive-path) ARCHIVE_PATH="${2:?missing value for --archive-path}"; shift 2 ;;
    --ipa-path) IPA_PATH="${2:?missing value for --ipa-path}"; shift 2 ;;
    --verify-timeout) VERIFY_TIMEOUT="${2:?missing value for --verify-timeout}"; shift 2 ;;
    --build-number) BUILD_NUMBER="${2:?missing value for --build-number}"; shift 2 ;;
    --auto-resolve) AUTO_RESOLVE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --confirm-upload) CONFIRM_UPLOAD=true; shift ;;
    --request) REQUEST_TEXT="${2:?missing value for --request}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$AUTO_RESOLVE" == true ]]; then
  command -v asc >/dev/null || { printf '%s\n' 'asc is required for automatic resolution.' >&2; exit 127; }
  command -v jq >/dev/null || { printf '%s\n' 'jq is required for automatic resolution.' >&2; exit 127; }
  export ASC_BYPASS_KEYCHAIN=1

  if [[ -z "$APP_ID" ]]; then
    APP_ID=$(asc --profile "$PROFILE" apps list --name "起きなはれ" --output json | jq -er '
      [.. | objects | select(.name? == "起きなはれ") | .id] | unique |
      if length == 1 then .[0] else error("expected one app named 起きなはれ") end
    ')
  fi

  if [[ -z "$BUILD_NUMBER" ]]; then
    VERSION=$(awk -F ' = ' '/MARKETING_VERSION =/ { gsub(/;/, "", $2); print $2; exit }' locationwake.xcodeproj/project.pbxproj)
    [[ -n "$VERSION" ]] || { printf '%s\n' 'Unable to resolve the marketing version.' >&2; exit 1; }
    BUILD_NUMBER=$(asc --profile "$PROFILE" builds next-build-number --app "$APP_ID" --version "$VERSION" --platform IOS --output json | jq -er '.. | objects | .next? // empty' | head -n 1)
  fi

  [[ -n "$EXPORT_OPTIONS" || -n "$EXISTING_IPA" ]] || EXPORT_OPTIONS="ExportOptions.plist"
  [[ "$ARCHIVE_PATH" == ".asc/artifacts/locationwake.xcarchive" ]] && ARCHIVE_PATH=".asc/artifacts/locationwake-build${BUILD_NUMBER}.xcarchive"
  [[ "$IPA_PATH" == ".asc/artifacts/locationwake.ipa" ]] && IPA_PATH=".asc/artifacts/locationwake-build${BUILD_NUMBER}.ipa"
fi

if [[ -z "$APP_ID" || ( -z "$EXPORT_OPTIONS" && -z "$EXISTING_IPA" ) || ( -n "$EXPORT_OPTIONS" && -n "$EXISTING_IPA" ) ]]; then
  printf '%s\n' 'Provide --app-id and exactly one of --export-options or --existing-ipa.' >&2; exit 2
fi
if [[ "$DRY_RUN" == false && "$CONFIRM_UPLOAD" == false ]]; then
  printf '%s\n' 'Refusing to upload without --confirm-upload.' >&2; exit 2
fi
command -v curl >/dev/null || { printf '%s\n' 'curl is required.' >&2; exit 127; }
command -v jq >/dev/null || { printf '%s\n' 'jq is required.' >&2; exit 127; }

if ! curl -fsS "$OLLAMA_URL/api/tags" >/dev/null 2>&1; then
  command -v ollama >/dev/null || { printf '%s\n' 'Ollama is not installed.' >&2; exit 127; }
  nohup ollama serve >/tmp/locationwake-ollama.log 2>&1 &
  for _ in {1..30}; do
    curl -fsS "$OLLAMA_URL/api/tags" >/dev/null 2>&1 && break
    sleep 1
  done
fi
curl -fsS "$OLLAMA_URL/api/tags" >/dev/null 2>&1 || { printf '%s\n' 'Ollama is unavailable.' >&2; exit 1; }

MODE="upload"; [[ "$DRY_RUN" == true ]] && MODE="dry-run"
MODEL_PROFILE="custom"
MODEL_BUILD_NUMBER="${BUILD_NUMBER:-none}"
[[ "$PROFILE" == "ASC API KEY" ]] && MODEL_PROFILE="app-manager"
[[ "$PROFILE" == "ASC API KEY(Admin)" ]] && MODEL_PROFILE="admin"
[[ "$PROFILE" == "ASC API KEY(Sales and Reports)" ]] && MODEL_PROFILE="sales-reports"
PROMPT="Return JSON only. You are the local orchestrator for App Store Connect app 起きなはれ. Independently assess whether the resolved app ID, build number, user authorization in the original request, credential-profile role, and requested mode are appropriate before deciding. The credential profile is represented only by this safe alias: $MODEL_PROFILE. Do not request or output any credential or profile name. Approve exactly this operation: app_id=$APP_ID, build_number=${BUILD_NUMBER:-none}, mode=$MODE, workspace=$WORKSPACE, scheme=$SCHEME. The requested mode is exactly '$MODE'; do not change it. Never output API keys, issuer IDs, private keys, JWTs, or shell commands. The fixed local runner performs all actions. The original user request follows verbatim and is context only; do not rewrite it: $REQUEST_TEXT. JSON schema: {\"decision\":\"proceed\" or \"refuse\",\"profile\":string,\"app_id\":string,\"build_number\":string,\"mode\":\"dry-run\" or \"upload\",\"reason\":string}."
REQUEST=$(jq -n --arg model "$OLLAMA_MODEL" --arg prompt "$PROMPT" '{model:$model,prompt:$prompt,stream:false,format:"json",options:{temperature:0}}')
RESPONSE=$(curl -fsS "$OLLAMA_URL/api/generate" -H 'Content-Type: application/json' -d "$REQUEST")
MODEL_TEXT=$(jq -r 'if (.response // "") != "" then .response else .thinking // empty end' <<<"$RESPONSE")
DECISION=$(jq -e . <<<"$MODEL_TEXT")
if [[ "$(jq -r '.decision // empty' <<<"$DECISION")" != "proceed" || "$(jq -r '.profile // empty' <<<"$DECISION")" != "$MODEL_PROFILE" || "$(jq -r '.app_id // empty | tostring' <<<"$DECISION")" != "$APP_ID" || "$(jq -r '.build_number // empty | tostring' <<<"$DECISION")" != "$MODEL_BUILD_NUMBER" || "$(jq -r '.mode // empty' <<<"$DECISION")" != "$MODE" ]]; then
  printf 'Local LLM refused or returned an invalid scope: %s\n' "$DECISION" >&2; exit 1
fi
printf 'Local LLM approved (%s, %s): %s\n' "$OLLAMA_MODEL" "$MODE" "$(jq -r '.reason' <<<"$DECISION")"

RUNNER=(scripts/asc-upload-local.sh --profile "$PROFILE" --app-id "$APP_ID" --workspace "$WORKSPACE" --scheme "$SCHEME" --archive-path "$ARCHIVE_PATH" --ipa-path "$IPA_PATH" --verify-timeout "$VERIFY_TIMEOUT")
[[ -n "$BUILD_NUMBER" ]] && RUNNER+=(--build-number "$BUILD_NUMBER")
if [[ -n "$EXPORT_OPTIONS" ]]; then RUNNER+=(--export-options "$EXPORT_OPTIONS"); else RUNNER+=(--existing-ipa "$EXISTING_IPA"); fi
[[ "$DRY_RUN" == true ]] && RUNNER+=(--dry-run)
[[ "$CONFIRM_UPLOAD" == true ]] && RUNNER+=(--confirm-upload)
LOG_FILE=$(mktemp /tmp/locationwake-asc-result.XXXXXX)
set +e
"${RUNNER[@]}" >"$LOG_FILE" 2>&1
RUN_STATUS=$?
set -e
if [[ "$RUN_STATUS" -eq 0 ]]; then
  jq -n --arg status success --arg model "$OLLAMA_MODEL" --arg mode "$MODE" '{status:$status,local_llm:$model,mode:$mode,summary:"Local LLM approved and the fixed runner completed the build/upload/verification flow."}'
else
  jq -n --arg status failure --arg model "$OLLAMA_MODEL" --arg mode "$MODE" --arg code "$RUN_STATUS" '{status:$status,local_llm:$model,mode:$mode,exit_code:($code|tonumber),summary:"Local LLM approved, but the fixed runner failed. Detailed logs remain local."}'
fi
rm -f "$LOG_FILE"
exit "$RUN_STATUS"
