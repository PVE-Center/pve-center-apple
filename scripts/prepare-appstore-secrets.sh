#!/usr/bin/env bash
set -euo pipefail

# Validate, encode, and optionally upload Apple Developer & App Store Connect
# secrets required by `.github/workflows/ios-appstore.yml` without storing
# certificates, provisioning profiles, or .p8 keys inside the repository.

TEAM_ID=""
P12_PATH=""
P12_PASSWORD=""
PROFILE_PATH=""
PROFILE_NAME=""
KEY_ID=""
ISSUER_ID=""
P8_PATH=""
APPLY_REPO=""
PRINT_ENV="0"

usage() {
  cat <<'EOF'
Usage: ./scripts/prepare-appstore-secrets.sh [OPTIONS]

Validates and Base64-encodes Apple Developer signing assets (.p12, .mobileprovision,
AuthKey_<KEY_ID>.p8) for `.github/workflows/ios-appstore.yml` without committing secrets.

Options:
  --team-id <ID>           Apple Developer Team ID (10 chars)
  --p12 <PATH>             Path to Apple Distribution .p12 certificate
  --p12-password <PASS>    Password protecting the .p12 file
  --profile <PATH>         Path to App Store .mobileprovision file
  --profile-name <NAME>    Exact Provisioning Profile Name (defaults to parsed Name)
  --key-id <ID>            App Store Connect API Key ID
  --issuer-id <UUID>       App Store Connect API Issuer ID
  --p8 <PATH>              Path to AuthKey_<KEY_ID>.p8 file
  --apply-gh <OWNER/REPO>  Upload secrets directly via `gh secret set`
  --print-env              Print Base64/env exports to stdout (handle output carefully!)
  -h, --help               Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --team-id) TEAM_ID="$2"; shift 2 ;;
    --p12) P12_PATH="$2"; shift 2 ;;
    --p12-password) P12_PASSWORD="$2"; shift 2 ;;
    --profile) PROFILE_PATH="$2"; shift 2 ;;
    --profile-name) PROFILE_NAME="$2"; shift 2 ;;
    --key-id) KEY_ID="$2"; shift 2 ;;
    --issuer-id) ISSUER_ID="$2"; shift 2 ;;
    --p8) P8_PATH="$2"; shift 2 ;;
    --apply-gh) APPLY_REPO="$2"; shift 2 ;;
    --print-env) PRINT_ENV="1"; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_file() {
  local label="$1"
  local file_path="$2"
  if [[ -z "${file_path}" || ! -f "${file_path}" ]]; then
    echo "Error: missing or unreadable ${label}: '${file_path}'" >&2
    exit 1
  fi
}

require_value() {
  local label="$1"
  local val="$2"
  if [[ -z "${val}" ]]; then
    echo "Error: ${label} is required." >&2
    usage >&2
    exit 1
  fi
}

require_value "--team-id" "${TEAM_ID}"
require_file ".p12 certificate" "${P12_PATH}"
require_file ".mobileprovision profile" "${PROFILE_PATH}"
require_value "--key-id" "${KEY_ID}"
require_value "--issuer-id" "${ISSUER_ID}"
require_file ".p8 API key" "${P8_PATH}"

if command -v openssl >/dev/null 2>&1; then
  if ! openssl pkcs12 -info -in "${P12_PATH}" -noout -passin "pass:${P12_PASSWORD}" >/dev/null 2>&1; then
    echo "Error: unable to decrypt ${P12_PATH} with the provided --p12-password." >&2
    exit 1
  fi
fi

if ! grep -q "BEGIN PRIVATE KEY" "${P8_PATH}"; then
  echo "Error: ${P8_PATH} does not look like a PEM PKCS#8 .p8 private key." >&2
  exit 1
fi

if [[ -z "${PROFILE_NAME}" ]] && command -v security >/dev/null 2>&1 && command -v plutil >/dev/null 2>&1; then
  PROFILE_NAME="$(security cms -D -i "${PROFILE_PATH}" 2>/dev/null | plutil -extract Name raw - 2>/dev/null || true)"
fi
require_value "--profile-name (could not auto-detect)" "${PROFILE_NAME}"

CERT_B64="$(base64 < "${P12_PATH}" | tr -d '\r\n')"
PROFILE_B64="$(base64 < "${PROFILE_PATH}" | tr -d '\r\n')"

echo "Validated Apple signing assets:"
echo "  - APPLE_TEAM_ID:                   ${TEAM_ID}"
echo "  - APPLE_PROVISIONING_PROFILE_NAME: ${PROFILE_NAME}"
echo "  - APPLE_CERTIFICATE_BASE64:        (${#CERT_B64} chars)"
echo "  - APPLE_PROVISIONING_PROFILE_BASE64: (${#PROFILE_B64} chars)"
echo "  - APPSTORE_KEY_ID:                 ${KEY_ID}"
echo "  - APPSTORE_ISSUER_ID:              ${ISSUER_ID}"
echo "  - APPSTORE_PRIVATE_KEY:            validated PEM (${P8_PATH##*/})"

if [[ -n "${APPLY_REPO}" ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "Error: GitHub CLI (gh) is required for --apply-gh." >&2
    exit 1
  fi
  printf '%s' "${TEAM_ID}" | gh secret set APPLE_TEAM_ID --repo "${APPLY_REPO}"
  printf '%s' "${CERT_B64}" | gh secret set APPLE_CERTIFICATE_BASE64 --repo "${APPLY_REPO}"
  printf '%s' "${P12_PASSWORD}" | gh secret set APPLE_P12_PASSWORD --repo "${APPLY_REPO}"
  printf '%s' "${PROFILE_NAME}" | gh secret set APPLE_PROVISIONING_PROFILE_NAME --repo "${APPLY_REPO}"
  printf '%s' "${PROFILE_B64}" | gh secret set APPLE_PROVISIONING_PROFILE_BASE64 --repo "${APPLY_REPO}"
  printf '%s' "${KEY_ID}" | gh secret set APPSTORE_KEY_ID --repo "${APPLY_REPO}"
  printf '%s' "${ISSUER_ID}" | gh secret set APPSTORE_ISSUER_ID --repo "${APPLY_REPO}"
  gh secret set APPSTORE_PRIVATE_KEY --repo "${APPLY_REPO}" < "${P8_PATH}"
  echo "Successfully uploaded all 8 TestFlight / App Store Connect secrets to ${APPLY_REPO}."
elif [[ "${PRINT_ENV}" == "1" ]]; then
  cat <<EOF
APPLE_TEAM_ID='${TEAM_ID}'
APPLE_PROVISIONING_PROFILE_NAME='${PROFILE_NAME}'
APPLE_CERTIFICATE_BASE64='${CERT_B64}'
APPLE_PROVISIONING_PROFILE_BASE64='${PROFILE_B64}'
APPSTORE_KEY_ID='${KEY_ID}'
APPSTORE_ISSUER_ID='${ISSUER_ID}'
EOF
else
  echo
  echo "Re-run with --apply-gh PVE-Center/pve-center-apple to upload directly via GitHub CLI."
fi
