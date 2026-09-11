#!/usr/bin/env bash
# Imports the pinned Apple Distribution and Apple Development certificates (DISTRIBUTION_/
# DEVELOPMENT_CERTIFICATE_P12_BASE64 + _PASSWORD secrets) into a fresh, unlocked keychain so
# xcodebuild finds matching local signing identities and reuses them instead of asking Apple to
# mint new ones on every run — GitHub-hosted runners are ephemeral, so without this every build
# burns one of the account's limited certificate slots. Both identities are needed: archiving the
# Release configuration still makes -allowProvisioningUpdates sync every signing style referenced
# in the project, including the Development one used by the Debug configuration. See docs/release.md.
set -euo pipefail
: "${DISTRIBUTION_CERTIFICATE_P12_BASE64:?DISTRIBUTION_CERTIFICATE_P12_BASE64 secret is empty}"
: "${DISTRIBUTION_CERTIFICATE_PASSWORD:?DISTRIBUTION_CERTIFICATE_PASSWORD secret is empty}"
: "${DEVELOPMENT_CERTIFICATE_P12_BASE64:?DEVELOPMENT_CERTIFICATE_P12_BASE64 secret is empty}"
: "${DEVELOPMENT_CERTIFICATE_PASSWORD:?DEVELOPMENT_CERTIFICATE_PASSWORD secret is empty}"

keychain_path="$RUNNER_TEMP/signing.keychain-db"
keychain_password=$(openssl rand -base64 24)

security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"

import_certificate() {
  local label="$1" b64_var="$2" password_var="$3" identity_label="$4"
  local cert_path="$RUNNER_TEMP/${label}_certificate.p12"

  printf '%s' "${!b64_var}" | tr -d '\n\r ' | base64 --decode >"$cert_path" || {
    echo "::error::$b64_var is not valid base64. Re-create it with: base64 -i ${label^}Certificate.p12 | pbcopy" >&2
    exit 1
  }

  security import "$cert_path" -P "${!password_var}" -A -t cert -f pkcs12 -k "$keychain_path"
  rm -f "$cert_path"

  local identity_count
  identity_count=$(security find-identity -v -p codesigning "$keychain_path" | grep -c "$identity_label" || true)
  if [ "$identity_count" -eq 0 ]; then
    echo "::error::No '$identity_label' identity found after import — check $b64_var and $password_var." >&2
    exit 1
  fi
  echo "Imported $identity_count $identity_label identity/identities into $keychain_path."
}

import_certificate distribution DISTRIBUTION_CERTIFICATE_P12_BASE64 DISTRIBUTION_CERTIFICATE_PASSWORD "Apple Distribution"
import_certificate development DEVELOPMENT_CERTIFICATE_P12_BASE64 DEVELOPMENT_CERTIFICATE_PASSWORD "Apple Development"

security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$keychain_password" "$keychain_path" >/dev/null

existing_keychains=$(security list-keychains -d user | sed 's/[[:space:]]*"\(.*\)"/\1/')
# shellcheck disable=SC2086
security list-keychains -d user -s "$keychain_path" $existing_keychains
