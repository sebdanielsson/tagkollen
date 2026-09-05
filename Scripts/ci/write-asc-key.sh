#!/usr/bin/env bash
# Writes the App Store Connect API key from the ASC_KEY secret to a file xcodebuild and fastlane
# can use, and fails early with a readable message when the secret is not what Apple issued.
# Accepts the .p8 either base64-encoded (recommended: `base64 -i AuthKey_XXXX.p8`) or as-is.
set -euo pipefail
: "${ASC_KEY:?APP_STORE_CONNECT_KEY_BASE64 secret is empty}"
: "${ASC_KEY_ID:?APP_STORE_CONNECT_KEY_ID secret is empty}"

dir="$RUNNER_TEMP/private_keys"
mkdir -p "$dir"
path="$dir/AuthKey_${ASC_KEY_ID}.p8"

if printf '%s' "$ASC_KEY" | grep -q "BEGIN PRIVATE KEY"; then
  printf '%s\n' "$ASC_KEY" > "$path"
else
  printf '%s' "$ASC_KEY" | tr -d '\n\r ' | base64 --decode > "$path" || {
    echo "::error::APP_STORE_CONNECT_KEY_BASE64 is neither a PEM key nor valid base64." >&2
    exit 1
  }
fi

if ! grep -q "BEGIN PRIVATE KEY" "$path"; then
  echo "::error::Decoded key does not look like an App Store Connect .p8 file (missing 'BEGIN PRIVATE KEY'). Re-create the secret with: base64 -i AuthKey_${ASC_KEY_ID}.p8 | pbcopy" >&2
  exit 1
fi
chmod 600 "$path"
echo "ASC_KEY_PATH=$path" >> "$GITHUB_ENV"
echo "API key AuthKey_${ASC_KEY_ID}.p8 written ($(wc -c < "$path") bytes)."
