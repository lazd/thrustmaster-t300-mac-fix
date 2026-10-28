#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
app_path="$HOME/Applications/T300 Mac Fix.app"
app_contents="$app_path/Contents"
app_executable="$app_contents/MacOS/T300MenuBar"
agent_path="$HOME/Library/LaunchAgents/com.lazd.thrustmaster-t300-menubar.plist"
agent_label="com.lazd.thrustmaster-t300-menubar"
launch_domain="gui/$(id -u)"

if [ "${1:-}" = "--uninstall" ]; then
  launchctl bootout "$launch_domain" "$agent_path" >/dev/null 2>&1 || true
  rm -f "$agent_path"
  rm -rf "$app_path"
  printf 'Removed the T300 menu-bar app and its login item.\n'
  exit 0
fi

node_path=${npm_node_execpath:-$(command -v node || true)}
if [ -z "$node_path" ]; then
  printf 'Node.js was not found. Run this with npm after installing Node.js.\n' >&2
  exit 1
fi
if ! command -v swiftc >/dev/null 2>&1; then
  printf 'Swift was not found. Install the Xcode Command Line Tools first.\n' >&2
  exit 1
fi

mkdir -p "$app_contents/MacOS" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
swiftc -swift-version 5 -parse-as-library -O -framework AppKit -framework IOKit \
  "$project_dir/T300MenuBar.swift" -o "$app_executable"

cat > "$app_contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>T300MenuBar</string>
  <key>CFBundleIdentifier</key><string>com.lazd.thrustmaster-t300-menubar</string>
  <key>CFBundleName</key><string>T300 Mac Fix</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

xml_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

app_executable_xml=$(xml_escape "$app_executable")
project_dir_xml=$(xml_escape "$project_dir")
node_path_xml=$(xml_escape "$node_path")
log_path_xml=$(xml_escape "$HOME/Library/Logs/T300 Mac Fix.log")

cat > "$agent_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$agent_label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$app_executable_xml</string>
    <string>$project_dir_xml</string>
    <string>$node_path_xml</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$log_path_xml</string>
  <key>StandardErrorPath</key><string>$log_path_xml</string>
</dict>
</plist>
PLIST

launchctl bootout "$launch_domain" "$agent_path" >/dev/null 2>&1 || true
launchctl bootstrap "$launch_domain" "$agent_path"
launchctl kickstart -k "$launch_domain/$agent_label"
printf 'Installed and started the T300 menu-bar app. It launches at login and stays hidden until a T300 is connected.\n'