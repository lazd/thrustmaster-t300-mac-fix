#!/bin/bash
set +e
RESOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "Uninstalling T300 Mac Fix. macOS will ask for administrator approval once."
sudo /bin/sh "$RESOURCE_DIR/uninstall-root.sh"
result=$?
if [ "$result" -eq 0 ]; then
  echo "Uninstallation complete."
else
  echo "Uninstallation failed with exit code $result."
fi
read -r -p "Press Return to close this window..."
exit "$result"