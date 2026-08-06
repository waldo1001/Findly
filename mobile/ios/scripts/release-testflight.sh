#!/usr/bin/env bash
# Archive, sign, and upload Findly to TestFlight in one command (H6 step 7).
#
# Usage:
#   mobile/ios/scripts/release-testflight.sh              # archive + export + upload
#   mobile/ios/scripts/release-testflight.sh --no-upload  # archive + export only
#
# Credentials: none are stored here or passed on the command line. Upload uses an App Store
# Connect API key, read from the environment:
#   ASC_KEY_ID      the 10-char Key ID
#   ASC_ISSUER_ID   the issuer UUID
# and the private key itself at ~/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8 —
# the location `xcrun altool` looks in by default. That .p8 is a secret: keep it out of the repo
# (docs/security-review-checklist.md §1) and out of shell history.
#
# BUILD_NUMBER (optional, H10): Apple rejects a reused build number, same as Play rejects a
# reused versionCode. When set, this overrides project.yml/project.pbxproj's checked-in
# CURRENT_PROJECT_VERSION for this archive only, via an xcodebuild command-line build setting —
# project.yml itself is never touched, so a plain local run of this script (or an Xcode GUI
# archive) with BUILD_NUMBER unset still produces the same build number it always did. CI
# (.github/workflows/ios.yml) sets it, derived from that workflow's own `github.run_number`.
#
# WHY THE ARCHIVE IS BUILT UNSIGNED (learned the hard way 2026-08-04, do not "fix" this):
# With automatic signing, `xcodebuild archive` asks Apple for a *development* provisioning
# profile, and Apple refuses to issue one to a team with no registered devices:
#   "Your team has no devices from which to generate a provisioning profile"
# Forcing CODE_SIGN_IDENTITY=Apple Distribution does not help — it conflicts with automatic
# signing outright ("automatically signed for development, but a conflicting code signing
# identity ... has been manually specified"). The path that works is to archive with
# CODE_SIGNING_ALLOWED=NO and let `-exportArchive` sign, because App Store distribution
# profiles ("iOS Team Store Provisioning Profile") need no registered device at all.
#
# Prerequisite on a fresh Mac: Xcode signed in to the Dynex team (92A2K3Q7NH) with Apple
# Development + Apple Distribution certificates, AND the WWDR **G3** intermediate installed —
# certificates chain through G3, and a machine carrying only the expired G1 fails with
# `errSecInternalComponent`. See docs/h6-apple-portal-runbook.md step 7a.

set -euo pipefail

IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEAM_ID="92A2K3Q7NH"
STAMP="$(date +%Y-%m-%d-%H%M%S)"
ARCHIVE="$HOME/Library/Developer/Xcode/Archives/${STAMP%%-*}-$(date +%m-%d)/Findly $STAMP.xcarchive"
OUT="$(mktemp -d)/export"
UPLOAD=1
[[ "${1:-}" == "--no-upload" ]] && UPLOAD=0

cd "$IOS_DIR"

echo "==> Regenerating the Xcode project from project.yml"
xcodegen generate >/dev/null

echo "==> Archiving (unsigned — see header)"
# H10: deliberately unquoted below — it is either empty (zero words, nothing appended to the
# xcodebuild invocation) or a single KEY=VALUE token with no internal whitespace, and this needs
# to work under bash 3.2 (macOS's default /bin/bash), where `"${arr[@]}"` on an empty array
# raises "unbound variable" under `set -u` (fixed only in bash 4.4+) — an array would be the more
# conventional way to build up an optional argument list, but it is not 3.2-safe here.
BUILD_NUMBER_SETTING=""
[[ -n "${BUILD_NUMBER:-}" ]] && BUILD_NUMBER_SETTING="CURRENT_PROJECT_VERSION=$BUILD_NUMBER"
xcodebuild archive \
  -scheme Findly \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CODE_SIGNING_ALLOWED=NO \
  $BUILD_NUMBER_SETTING \
  | grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)" || true

[[ -d "$ARCHIVE" ]] || { echo "!! archive not produced"; exit 1; }

echo "==> Exporting + signing for the App Store"
PLIST="$(mktemp)"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>destination</key><string>export</string>
</dict>
</plist>
PLISTEOF

# H10 review fix: `-allowProvisioningUpdates` has to authenticate to the Apple Developer Portal
# to resolve (or mint) a signing certificate/profile — on a developer's Mac that authentication
# comes from Xcode already being signed in (see the header's "Prerequisite on a fresh Mac"), but
# a CI runner is a fresh, ephemeral VM with no signed-in Apple ID and no keychain state, so
# without explicit API-key auth here the export fails before it ever reaches `altool` below.
# Only added when ASC_KEY_ID/ASC_ISSUER_ID are set (CI); a local run on a Mac with Xcode already
# signed in is unaffected and behaves exactly as before.
#
# CI cert-limit note: every CI run is a brand-new VM with no persisted keychain, so
# `-allowProvisioningUpdates` may mint a **new Apple Distribution certificate on every run**
# instead of reusing one — and Apple caps the number of Distribution certificates per team. This
# is fine at low CI-publish frequency; if uploads start failing with a certificate-limit error
# from Apple, this is why, and the fix is either revoking old auto-minted certs in the Developer
# Portal or moving to a persisted/cached signing identity instead of `-allowProvisioningUpdates`
# minting fresh each time.
#
# `"${arr[@]+"${arr[@]}"}"` (not a plain `"${arr[@]}"`) is deliberate: bash 3.2 (macOS's default
# /bin/bash, confirmed via `bash --version` — this repo's BUILD_NUMBER_SETTING comment above
# documents the same constraint) raises "unbound variable" under `set -u` when expanding an
# empty array, a bug fixed only in bash 4.4+; this idiom is the standard 3.2-safe workaround.
EXTRA_EXPORT_ARGS=()
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
  EXTRA_EXPORT_ARGS=(
    -authenticationKeyPath "$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
    -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
  )
fi

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$OUT" \
  -exportOptionsPlist "$PLIST" \
  -allowProvisioningUpdates \
  "${EXTRA_EXPORT_ARGS[@]+"${EXTRA_EXPORT_ARGS[@]}"}" \
  | grep -E "error:|EXPORT (SUCCEEDED|FAILED)|Exported" || true

IPA="$OUT/Findly.ipa"
[[ -f "$IPA" ]] || { echo "!! no .ipa produced"; exit 1; }
echo "==> Built $IPA ($(du -h "$IPA" | cut -f1))"

# Sanity check the extension really shipped inside the app (I15).
#
# NB: the listing is captured into a variable first, rather than piped straight into `grep -q`.
# Under `set -o pipefail` (on, above), `grep -q` exits at the first match, `unzip` then dies of
# SIGPIPE (141), and pipefail reports the *pipeline* as failed — so a perfectly good .ipa gets
# rejected. This bit us for real on 2026-08-05, and is the same SIGPIPE-under-pipefail trap that
# A17's review chased in the Android CI workflow.
LISTING="$(unzip -l "$IPA")"
if ! grep -q "PlugIns/FindlyNotificationService.appex/FindlyNotificationService" <<<"$LISTING"; then
  echo "!! FindlyNotificationService.appex missing from the .ipa — refusing to upload"
  exit 1
fi
echo "==> Verified: FindlyNotificationService.appex embedded"

if [[ "$UPLOAD" == "0" ]]; then
  echo "==> --no-upload given; stopping. IPA at: $IPA"
  exit 0
fi

: "${ASC_KEY_ID:?set ASC_KEY_ID (App Store Connect API Key ID)}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (App Store Connect issuer UUID)}"

echo "==> Uploading to App Store Connect"
xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

echo "==> Uploaded. TestFlight shows the build after 5-15 min of processing."
