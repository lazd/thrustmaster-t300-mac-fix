#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
  printf 'Run this uninstaller with administrator privileges.\n' >&2
  exit 1
fi
target_user=${SUDO_USER:-}
if [ -z "$target_user" ] || [ "$target_user" = root ]; then
  printf 'Launch the uninstaller from a standard user account in Terminal.\n' >&2
  exit 1
fi
target_uid=$(id -u "$target_user")
target_group=$(id -gn "$target_user")
target_home=$(/usr/bin/dscl . -read "/Users/$target_user" NFSHomeDirectory | /usr/bin/awk '{print $2}')
helper_label="com.lazd.thrustmaster-t300-helper"
agent_label="com.lazd.thrustmaster-t300-menubar"
daemon_path="/Library/LaunchDaemons/$helper_label.plist"
agent_path="$target_home/Library/LaunchAgents/$agent_label.plist"

launchctl bootout system "$daemon_path" >/dev/null 2>&1 || true
launchctl bootout "gui/$target_uid" "$agent_path" >/dev/null 2>&1 || true
rm -f "$daemon_path" "/Library/PrivilegedHelperTools/$helper_label"
rm -rf "/Library/Application Support/T300 Mac Fix" "$target_home/Library/Application Support/T300 Mac Fix"
rm -f "$agent_path"
rm -rf "/Applications/T300 Mac Fix.app"
printf 'T300 Mac Fix and its startup services have been removed.\n'