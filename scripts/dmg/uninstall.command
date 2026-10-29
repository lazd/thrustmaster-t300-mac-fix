#!/bin/bash
set +e
RESOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
printf '\n🧹 T300 Mac Fix Uninstaller\n'
printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n'
printf '🔐 macOS will ask for administrator approval once to remove the helper and startup services.\n\n'
sudo /bin/sh "$RESOURCE_DIR/uninstall-root.sh"
result=$?
if [ "$result" -eq 0 ]; then
  printf '\n✅ Uninstallation complete.\n\n'
else
  printf '\n🛑 Uninstallation failed with exit code %s.\n\n' "$result"
fi
read -r -p "Press Return to close this window... "
exit "$result"