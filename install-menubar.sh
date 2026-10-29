#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
app_path="$HOME/Applications/T300 Mac Fix.app"
app_contents="$app_path/Contents"
app_executable="$app_contents/MacOS/T300MenuBar"
helper_label="com.lazd.thrustmaster-t300-helper"
helper_path="/Library/PrivilegedHelperTools/$helper_label"
daemon_path="/Library/LaunchDaemons/$helper_label.plist"
system_state_directory="/Library/Application Support/T300 Mac Fix"
user_request_directory="$HOME/Library/Application Support/T300 Mac Fix"
agent_path="$HOME/Library/LaunchAgents/com.lazd.thrustmaster-t300-menubar.plist"
agent_label="com.lazd.thrustmaster-t300-menubar"
launch_domain="gui/$(id -u)"

if [ "${1:-}" = "--uninstall" ]; then
  sudo -v
  sudo launchctl bootout system "$daemon_path" >/dev/null 2>&1 || true
  sudo rm -f "$daemon_path" "$helper_path"
  launchctl bootout "$launch_domain" "$agent_path" >/dev/null 2>&1 || true
  rm -f "$agent_path"
  rm -rf "$app_path"
  rm -f "$user_request_directory/initialize.request"
  printf 'Removed the T300 menu-bar app, privileged helper, and both login services.\n'
  exit 0
fi

if ! command -v swiftc >/dev/null 2>&1; then
  printf 'Swift was not found. Install the Xcode Command Line Tools first.\n' >&2
  exit 1
fi
if ! command -v clang >/dev/null 2>&1; then
  printf 'Clang was not found. Install the Xcode Command Line Tools first.\n' >&2
  exit 1
fi

build_directory=$(mktemp -d)
trap 'rm -rf "$build_directory"' EXIT
mkdir -p "$app_contents/MacOS" "$app_contents/Resources" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs" "$user_request_directory"
cp "$project_dir/scripts/dmg/uninstall.command" "$project_dir/scripts/dmg/uninstall-root.sh" "$app_contents/Resources/"
chmod 755 "$app_contents/Resources/uninstall.command" "$app_contents/Resources/uninstall-root.sh"
chmod 700 "$user_request_directory"
clang -O -c "$project_dir/T300USB.c" -o "$build_directory/T300USB.o"
swiftc -swift-version 5 -parse-as-library -O -framework AppKit -framework IOKit \
  "$project_dir/T300MenuBar.swift" -o "$app_executable"
swiftc -swift-version 5 -parse-as-library -O -framework IOKit \
  -import-objc-header "$project_dir/T300USB.h" \
  "$project_dir/T300PrivilegedHelper.swift" "$build_directory/T300USB.o" \
  -o "$build_directory/T300PrivilegedHelper"

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
log_path_xml=$(xml_escape "$HOME/Library/Logs/T300 Mac Fix.log")
helper_path_xml=$(xml_escape "$helper_path")
system_state_directory_xml=$(xml_escape "$system_state_directory")
user_request_directory_xml=$(xml_escape "$user_request_directory")
helper_log_xml=$(xml_escape "/var/log/T300MacFixHelper.log")

cat > "$build_directory/$helper_label.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$helper_label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$helper_path_xml</string>
    <string>$system_state_directory_xml</string>
    <string>$user_request_directory_xml</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>5</integer>
  <key>StandardOutPath</key><string>$helper_log_xml</string>
  <key>StandardErrorPath</key><string>$helper_log_xml</string>
</dict>
</plist>
PLIST

cat > "$agent_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$agent_label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$app_executable_xml</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$log_path_xml</string>
  <key>StandardErrorPath</key><string>$log_path_xml</string>
</dict>
</plist>
PLIST

plutil -lint "$app_contents/Info.plist" "$build_directory/$helper_label.plist" "$agent_path" >/dev/null

sudo -v
sudo install -d -o root -g wheel -m 755 "/Library/PrivilegedHelperTools" "$system_state_directory"
sudo install -o root -g wheel -m 755 "$build_directory/T300PrivilegedHelper" "$helper_path"
sudo install -o root -g wheel -m 644 "$build_directory/$helper_label.plist" "$daemon_path"
sudo launchctl bootout system "$daemon_path" >/dev/null 2>&1 || true
sudo launchctl bootstrap system "$daemon_path"
sudo launchctl kickstart -k "system/$helper_label"

launchctl bootout "$launch_domain" "$agent_path" >/dev/null 2>&1 || true
launchctl bootstrap "$launch_domain" "$agent_path"
launchctl kickstart -k "$launch_domain/$agent_label"
printf 'Installed both T300 services. Administrator approval was required for installation only; initialization runs automatically without prompts after that.\n'