#!/bin/bash
# Rebuild + reinstall Nudge on iPhone + Mac (resets the free-team 7-day clock).
# Runs a readiness/connectivity check first. Pass --interactive for modal dialogs
# (the Dock button); without it, failures come as notifications (the auto-job).
PROJ="/Users/noahflouty/Claude/nudge/ios/Nudge"
DEV="73562BAB-DA59-5AB0-A722-8AACE1D8820C"
INTERACTIVE=0; [ "$1" = "--interactive" ] && INTERACTIVE=1

notify()  { /usr/bin/osascript -e "display notification \"$2\" with title \"$1\" sound name \"$3\"" >/dev/null 2>&1; }
report()  {  # modal dialog when launched from the button, else a notification
  if [ "$INTERACTIVE" = "1" ]; then
    /usr/bin/osascript -e "display dialog \"$2\" with title \"$1\" buttons {\"OK\"} default button 1 with icon caution" >/dev/null 2>&1
  else notify "$1" "$2" "Basso"; fi
}

# ---------- Preflight / connectivity check ----------
echo "[$(date '+%H:%M')] Checking everything's ready…"
P=""
if ! security find-identity -p codesigning -v 2>/dev/null | grep -q "Apple Development"; then
  P="${P}• Xcode isn't signed in — open Xcode, Settings, Accounts and add your Apple ID.
"
fi
# A network-paired iPhone shows as "available (paired)", a cabled one as "connected" —
# both are reachable and installable, so accept either.
if ! xcrun devicectl list devices 2>/dev/null | grep "$DEV" | grep -qiE "connected|available"; then
  P="${P}• iPhone not reachable — unlock it on the same Wi-Fi (or plug it in) and trust this Mac.
"
else
  if xcrun devicectl device info lockState --device "$DEV" 2>/dev/null | grep -qi "passcodeRequired: true"; then
    P="${P}• iPhone is locked — unlock it and keep the screen on.
"
  fi
fi
if [ -n "$P" ]; then
  report "Nudge — not ready yet" "Fix these, then click again:

$P"
  echo "Preflight failed:"; printf '%s' "$P"; exit 1
fi
[ "$INTERACTIVE" = "1" ] && notify "Nudge" "All set — rebuilding & reinstalling (~1 min)…" "Pop"
echo "Preflight OK."

# ---------- Force a fresh 7-day profile ----------
# Xcode reuses any still-valid cached profile, so reinstalling never reset the free-team
# 7-day clock. Move the cached Nudge profiles ASIDE so -allowProvisioningUpdates mints
# fresh ones (expiry = today + 7). We keep the old ones in a temp dir and RESTORE them if
# the build fails — otherwise a failure (e.g. Xcode signed out) would leave zero profiles.
# Profiles live in different folders across Xcode versions — handle both.
PROF_BK="$(mktemp -d)"
PRIMARY_PROF="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"   # modern Xcode location
for PROF_DIR in "$PRIMARY_PROF" "$HOME/Library/MobileDevice/Provisioning Profiles"; do
  [ -d "$PROF_DIR" ] || continue
  for p in "$PROF_DIR"/*.mobileprovision; do
    [ -f "$p" ] || continue
    if security cms -D -i "$p" 2>/dev/null | grep -qi "flouty"; then
      mv "$p" "$PROF_BK/"; echo "Set aside profile $(basename "$p")"   # UUID names, no collision
    fi
  done
done
restore_profiles() {  # put the old profiles back if a fresh build couldn't be made
  mkdir -p "$PRIMARY_PROF"
  cp "$PROF_BK"/*.mobileprovision "$PRIMARY_PROF/" 2>/dev/null
}

# ---------- iPhone ----------
cd "$PROJ" || { report "Nudge reinstall failed" "Project folder not found."; exit 1; }
# pipefail so a build failure isn't masked by the trailing `tail` (which previously let
# the script march on and install a STALE app).
if ! ( set -o pipefail; xcodebuild -project Nudge.xcodeproj -scheme Nudge -destination 'generic/platform=iOS' -allowProvisioningUpdates build 2>&1 | tail -6 ); then
  restore_profiles   # don't leave the user with no signing profiles
  report "Nudge reinstall failed" "iPhone build/signing failed. Open Xcode ▸ Settings ▸ Accounts and make sure your Apple ID is added, then click again."
  echo "iPhone build FAILED — not installing (would be a stale app). Check Xcode ▸ Settings ▸ Accounts."; exit 1
fi
rm -rf "$PROF_BK"   # fresh build succeeded; the old profiles aren't needed
APP=$(find "$HOME/Library/Developer/Xcode/DerivedData/Nudge-"*/Build/Products/Debug-iphoneos -maxdepth 1 -name Nudge.app 2>/dev/null | head -1)
[ -z "$APP" ] && { notify "Nudge reinstall failed" "No iPhone build output." "Basso"; exit 1; }
OUT=$(xcrun devicectl device install app --device "$DEV" "$APP" 2>&1); echo "$OUT" | tail -2
if echo "$OUT" | grep -qiE "installed|databaseUUID"; then
  xcrun devicectl device process launch --terminate-existing --device "$DEV" uk.flouty.Nudge >/dev/null 2>&1
  echo "iPhone reinstalled."
else
  notify "Nudge reinstall failed" "Install failed — unlock & reconnect your iPhone, then click again." "Basso"; exit 1
fi

# ---------- Mac (Catalyst) ----------
if xcodebuild -project Nudge.xcodeproj -scheme Nudge -destination 'platform=macOS,variant=Mac Catalyst' -allowProvisioningUpdates CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3; then
  MACAPP=$(find "$HOME/Library/Developer/Xcode/DerivedData/Nudge-"*/Build/Products/Debug-maccatalyst -maxdepth 1 -name Nudge.app 2>/dev/null | head -1)
  [ -n "$MACAPP" ] && { pkill -x Nudge >/dev/null 2>&1; sleep 1; /usr/bin/open "$MACAPP"; }
  echo "Mac refreshed."
else
  notify "Nudge Mac refresh failed" "The Mac app couldn't rebuild." "Basso"
fi
notify "Nudge" "✅ Reinstalled on iPhone + Mac — 7-day clock reset." "Glass"
echo "[$(date '+%H:%M')] Done."
