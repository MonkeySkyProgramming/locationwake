#!/usr/bin/env bash
set -euo pipefail

# Deterministic App Store Connect upload runner for local automation/LLM agents.
# Every ASC command receives --profile explicitly; the current global default
# profile is never used for an upload.

PROFILE="ASC API KEY" # App Manager
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

usage() {
  cat <<'EOF'
Usage:
  scripts/asc-upload-local.sh --app-id APP_ID [--export-options PATH | --existing-ipa PATH] [options]

Required:
  --app-id ID                 App Store Connect app ID for 起きなはれ
  --export-options PATH       ExportOptions.plist path
  --existing-ipa PATH         Use an existing IPA and skip archive/export

Options:
  --profile NAME              Explicit ASC profile (default: ASC API KEY)
  --workspace PATH            Xcode workspace (default: locationwake.xcworkspace)
  --scheme NAME               Xcode scheme (default: locationwake)
  --archive-path PATH         Archive output path
  --ipa-path PATH             IPA output path
  --verify-timeout DURATION   Upload failure watch window (default: 10m)
  --build-number NUMBER       Set the project build number before archiving
  --dry-run                   Prepare upload operations without uploading
  --confirm-upload            Required for a real upload
  -h, --help                  Show this help

Profiles:
  ASC API KEY(Admin)              43YJ5784BN
  ASC API KEY(Sales and Reports)  6B3GZHRQ8Z
  ASC API KEY                    G4LKFBCTTH (App Manager)
EOF
}

while (($#)); do
  case "$1" in
    --app-id) APP_ID="${2:?missing value for --app-id}"; shift 2 ;;
    --export-options) EXPORT_OPTIONS="${2:?missing value for --export-options}"; shift 2 ;;
    --existing-ipa) EXISTING_IPA="${2:?missing value for --existing-ipa}"; shift 2 ;;
    --profile) PROFILE="${2:?missing value for --profile}"; shift 2 ;;
    --workspace) WORKSPACE="${2:?missing value for --workspace}"; shift 2 ;;
    --scheme) SCHEME="${2:?missing value for --scheme}"; shift 2 ;;
    --archive-path) ARCHIVE_PATH="${2:?missing value for --archive-path}"; shift 2 ;;
    --ipa-path) IPA_PATH="${2:?missing value for --ipa-path}"; shift 2 ;;
    --verify-timeout) VERIFY_TIMEOUT="${2:?missing value for --verify-timeout}"; shift 2 ;;
    --build-number) BUILD_NUMBER="${2:?missing value for --build-number}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --confirm-upload) CONFIRM_UPLOAD=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$APP_ID" || ( -z "$EXPORT_OPTIONS" && -z "$EXISTING_IPA" ) || ( -n "$EXPORT_OPTIONS" && -n "$EXISTING_IPA" ) ]]; then
  printf '%s\n' 'Provide --app-id and exactly one of --export-options or --existing-ipa.' >&2
  usage >&2
  exit 2
fi

if [[ "$DRY_RUN" == false && "$CONFIRM_UPLOAD" == false ]]; then
  printf '%s\n' 'Refusing to upload without --confirm-upload.' >&2
  exit 2
fi

command -v asc >/dev/null || { printf '%s\n' 'asc is not installed.' >&2; exit 127; }
[[ -d "$WORKSPACE" ]] || { printf 'Workspace not found: %s\n' "$WORKSPACE" >&2; exit 1; }
if [[ -n "$EXPORT_OPTIONS" ]]; then
  [[ -f "$EXPORT_OPTIONS" ]] || { printf 'ExportOptions.plist not found: %s\n' "$EXPORT_OPTIONS" >&2; exit 1; }
else
  [[ -f "$EXISTING_IPA" ]] || { printf 'IPA not found: %s\n' "$EXISTING_IPA" >&2; exit 1; }
  IPA_PATH="$EXISTING_IPA"
fi

mkdir -p "$(dirname "$ARCHIVE_PATH")" "$(dirname "$IPA_PATH")"

# The Keychain is currently unavailable on this machine. This environment
# variable forces asc to use the named profiles in ~/.asc/config.json.
export ASC_BYPASS_KEYCHAIN=1

asc_cmd() {
  # Do not print credentials or JWTs. The profile name is intentionally visible.
  asc --profile "$PROFILE" "$@"
}

printf 'Using ASC profile: %s\n' "$PROFILE"
printf 'Target app ID: %s\n' "$APP_ID"

# Fail early if this named profile is absent or cannot authenticate.
asc_cmd auth status --validate --output json --pretty

if [[ -n "$EXPORT_OPTIONS" ]]; then
  if [[ -n "$BUILD_NUMBER" ]]; then
    asc_cmd xcode version edit --build-number "$BUILD_NUMBER" --output json
  fi
  asc_cmd xcode archive \
    --workspace "$WORKSPACE" \
    --scheme "$SCHEME" \
    --configuration Release \
    --archive-path "$ARCHIVE_PATH" \
    --xcodebuild-flag=-destination \
    --xcodebuild-flag=generic/platform=iOS \
    --xcodebuild-flag=CODE_SIGN_STYLE=Manual \
    --xcodebuild-flag='CODE_SIGN_IDENTITY=iPhone Distribution' \
    --xcodebuild-flag=DEVELOPMENT_TEAM=A9Q2MN2H6M \
    --xcodebuild-flag=PROVISIONING_PROFILE_SPECIFIER=db11278e-23d3-40fc-bc0e-15d4d8957abb \
    --output json

  asc_cmd xcode export \
    --archive-path "$ARCHIVE_PATH" \
    --export-options "$EXPORT_OPTIONS" \
    --ipa-path "$IPA_PATH" \
    --output json
fi

if [[ "$DRY_RUN" == true ]]; then
  # Do not call builds upload --dry-run here: asc may reserve an upload record
  # even in dry-run mode. Read-only checks are safer for local agents.
  asc_cmd apps view --id "$APP_ID" --output json
  printf 'Dry-run passed: IPA is ready at %s; no upload record was created.\n' "$IPA_PATH"
else
  asc_cmd builds upload \
    --app "$APP_ID" \
    --ipa "$IPA_PATH" \
    --verify-timeout "$VERIFY_TIMEOUT" \
    --wait \
    --output json
fi

# Verify with the same explicit profile, never with whatever profile is global.
asc_cmd builds info --app "$APP_ID" --latest --platform IOS --output json
printf 'ASC upload and verification completed with profile: %s\n' "$PROFILE"
