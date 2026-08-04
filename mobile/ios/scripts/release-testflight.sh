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
xcodebuild archive \
  -scheme Findly \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CODE_SIGNING_ALLOWED=NO \
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

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$OUT" \
  -exportOptionsPlist "$PLIST" \
  -allowProvisioningUpdates \
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
