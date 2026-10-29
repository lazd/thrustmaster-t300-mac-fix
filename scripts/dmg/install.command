#!/bin/bash
set +e
RESOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
printf '\n📦 T300 Mac Fix Installer\n'
printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n'
printf '⚠️  WARNING: If your T300 is already connected, it will spin!\n'
printf '   Keep your hands clear.\n\n'
printf '🔐 macOS will ask for administrator approval once to install the helper.\n\n'

sudo /bin/sh "$RESOURCE_DIR/install-root.sh" "$RESOURCE_DIR/Payload"
result=$?
if [ "$result" -eq 0 ]; then
  printf '\n✅ Installation complete. The menu-bar app starts at login.\n\n'
else
  printf '\n🛑 Installation failed with exit code %s.\n\n' "$result"
fi
read -r -p "Press Return to close this window... "
exit "$result"