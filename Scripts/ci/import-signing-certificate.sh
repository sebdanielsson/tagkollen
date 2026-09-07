#!/usr/bin/env bash
# Imports the pinned Apple Distribution certificate (DISTRIBUTION_CERTIFICATE_P12_BASE64 /
# DISTRIBUTION_CERTIFICATE_PASSWORD secrets) into a fresh, unlocked keychain so xcodebuild finds a
# matching local signing identity and reuses it instead of asking Apple to mint a new certificate
# on every run — GitHub-hosted runners are ephemeral, so without this every build burns one of the
# account's limited "Apple Distribution" certificate slots. See docs/release.md.
set -euo pipefail
: "${DISTRIBUTION_CERTIFICATE_P12_BASE64:?DISTRIBUTION_CERTIFICATE_P12_BASE64 secret is empty}"
: "${DISTRIBUTION_CERTIFICATE_PASSWORD:?DISTRIBUTION_CERTIFICATE_PASSWORD secret is empty}"

cert_path="$RUNNER_TEMP/distribution_certificate.p12"
keychain_path="$RUNNER_TEMP/signing.keychain-db"
keychain_password=$(openssl rand -base64 24)

printf '%s' "$DISTRIBUTION_CERTIFICATE_P12_BASE64" | tr -d '\n\r ' | base64 --decode > "$cert_path" || {
  echo "::error::DISTRIBUTION_CERTIFICATE_P12_BASE64 is not valid base64. Re-create it with: base64 -i DistributionCertificate.p12 | pbcopy" >&2
  exit 1
}

security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"

security import "$cert_path" -P "$DISTRIBUTION_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$keychain_path"
security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$keychain_password" "$keychain_path" >/dev/null

existing_keychains=$(security list-keychains -d user | sed 's/[[:space:]]*"\(.*\)"/\1/')
# shellcheck disable=SC2086
security list-keychains -d user -s "$keychain_path" $existing_keychains

rm -f "$cert_path"
identity_count=$(security find-identity -v -p codesigning "$keychain_path" | grep -c "Apple Distribution" || true)
if [ "$identity_count" -eq 0 ]; then
  echo "::error::No 'Apple Distribution' identity found after import — check DISTRIBUTION_CERTIFICATE_P12_BASE64 and DISTRIBUTION_CERTIFICATE_PASSWORD." >&2
  exit 1
fi
echo "Imported $identity_count Apple Distribution identity/identities into $keychain_path."
