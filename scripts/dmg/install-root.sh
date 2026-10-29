#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
  printf '🛑  Run this installer with administrator privileges.\n' >&2
  exit 1
fi
payload_directory=${1:?Missing DMG payload directory}
target_user=${SUDO_USER:-}
if [ -z "$target_user" ] || [ "$target_user" = root ]; then
  printf '🛑  Launch the installer from a standard user account in Terminal.\n' >&2
  exit 1
fi
target_uid=$(id -u "$target_user")
target_group=$(id -gn "$target_user")
target_home=$(/usr/bin/dscl . -read "/Users/$target_user" NFSHomeDirectory | /usr/bin/awk '{print $2}')
app_source="$payload_directory/T300 Mac Fix.app"
helper_source="$payload_directory/T300PrivilegedHelper"
app_path="/Applications/T300 Mac Fix.app"
app_executable="$app_path/Contents/MacOS/T300MenuBar"
helper_label="com.lazd.thrustmaster-t300-helper"
helper_path="/Library/PrivilegedHelperTools/$helper_label"
daemon_path="/Library/LaunchDaemons/$helper_label.plist"
system_state_directory="/Library/Application Support/T300 Mac Fix"
user_request_directory="$target_home/Library/Application Support/T300 Mac Fix"
agent_label="com.lazd.thrustmaster-t300-menubar"
agent_path="$target_home/Library/LaunchAgents/$agent_label.plist"

if [ ! -d "$app_source" ] || [ ! -x "$helper_source" ]; then
  printf '🛑 The installer payload is incomplete.\n' >&2
  exit 1
fi

printf '\n🔄 Preparing the installation...\n\n'
launchctl bootout system "$daemon_path" >/dev/null 2>&1 || true
launchctl bootout "gui/$target_uid" "$agent_path" >/dev/null 2>&1 || true
rm -rf "$app_path"
printf '📥 Copying the app and privileged helper...\n'
ditto "$app_source" "$app_path"
install -d -o root -g wheel -m 755 "/Library/PrivilegedHelperTools" "$system_state_directory"
install -o root -g wheel -m 755 "$helper_source" "$helper_path"
rm -f "$system_state_directory/helper-state.json"
install -d -o "$target_user" -g "$target_group" -m 700 "$user_request_directory" "$target_home/Library/LaunchAgents"

printf '\n⚙️  Registering startup services...\n'
cat > "$daemon_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$helper_label</string>
  <key>ProgramArguments</key><array><string>$helper_path</string><string>$system_state_directory</string><string>$user_request_directory</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>5</integer>
  <key>StandardOutPath</key><string>/var/log/T300MacFixHelper.log</string>
  <key>StandardErrorPath</key><string>/var/log/T300MacFixHelper.log</string>
</dict>
</plist>
PLIST

cat > "$agent_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$agent_label</string>
  <key>ProgramArguments</key><array><string>$app_executable</string></array>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$target_home/Library/Logs/T300 Mac Fix.log</string>
  <key>StandardErrorPath</key><string>$target_home/Library/Logs/T300 Mac Fix.log</string>
</dict>
</plist>
PLIST

plutil -lint "$daemon_path" "$agent_path" >/dev/null
printf '   📄 %s\n' "$daemon_path"
printf '   📄 %s\n' "$agent_path"
chown root:wheel "$daemon_path"
chmod 644 "$daemon_path"
chown "$target_user:$target_group" "$agent_path"
chmod 644 "$agent_path"
printf '\n🚀 Starting the helper and menu-bar app...\n'
launchctl bootstrap system "$daemon_path"
launchctl kickstart -k "system/$helper_label"
launchctl bootstrap "gui/$target_uid" "$agent_path"
launchctl kickstart -k "gui/$target_uid/$agent_label"
printf '\n✅ T300 Mac Fix is installed.\n\n'
printf '   It starts at login and initializes the wheel when connected.\n'
printf '   You will not be asked for administrator approval when plugging in the wheel.\n\n'