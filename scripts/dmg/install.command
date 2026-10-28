#!/bin/bash
set +e
RESOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "📦 Installing T300 Mac Fix. macOS will ask for administrator approval once."
echo ""
echo "⚠️ WARNING: If your T300 is already connnected, it will spin! Keep your hands clear."

sudo /bin/sh "$RESOURCE_DIR/install-root.sh" "$RESOURCE_DIR/Payload"
result=$?
if [ "$result" -eq 0 ]; then
  echo "✅ Installation complete. The menu-bar app starts at login."
else
  echo "🛑 Installation failed with exit code $result."
fi
read -r -p "Press Return to close this window..."
exit "$result"