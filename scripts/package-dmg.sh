#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"
version=$(node -p 'require("./package.json").version')
output_directory="$project_dir/dist"
output_image="$output_directory/T300-Mac-Fix.dmg"
build_directory=$(mktemp -d "${TMPDIR:-/tmp}/t300-release.XXXXXX")
trap 'rm -rf "$build_directory"' EXIT

for tool in swiftc clang iconutil hdiutil ditto plutil node; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'Missing required build tool: %s\n' "$tool" >&2
    exit 1
  fi
done

mkdir -p "$output_directory"
clang -O -c "$project_dir/T300USB.c" -o "$build_directory/T300USB.o"
swiftc -swift-version 5 -parse-as-library -O -framework AppKit -framework IOKit \
  "$project_dir/T300MenuBar.swift" -o "$build_directory/T300MenuBar"
swiftc -swift-version 5 -parse-as-library -O -framework IOKit \
  -import-objc-header "$project_dir/T300USB.h" \
  "$project_dir/T300PrivilegedHelper.swift" "$build_directory/T300USB.o" \
  -o "$build_directory/T300PrivilegedHelper"
swiftc -swift-version 5 -parse-as-library -O -framework AppKit \
  "$project_dir/scripts/ActionLauncher.swift" -o "$build_directory/ActionLauncher"
swiftc -swift-version 5 -parse-as-library -O -framework AppKit \
  "$project_dir/scripts/BuildIcons.swift" -o "$build_directory/BuildIcons"
"$build_directory/BuildIcons" "$build_directory/icons"
for icon in Menu Install Uninstall; do
  iconutil -c icns -o "$build_directory/$icon.icns" "$build_directory/icons/$icon.iconset"
done

staging="$build_directory/dmg"
menu_app="$build_directory/T300 Mac Fix.app"
mkdir -p "$menu_app/Contents/MacOS" "$menu_app/Contents/Resources"
cp "$build_directory/T300MenuBar" "$menu_app/Contents/MacOS/T300MenuBar"
cp "$build_directory/Menu.icns" "$menu_app/Contents/Resources/AppIcon.icns"
cp "$project_dir/scripts/dmg/uninstall.command" "$project_dir/scripts/dmg/uninstall-root.sh" "$menu_app/Contents/Resources/"
chmod 755 "$menu_app/Contents/Resources/uninstall.command" "$menu_app/Contents/Resources/uninstall-root.sh"
cat > "$menu_app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>T300MenuBar</string>
  <key>CFBundleIdentifier</key><string>com.lazd.thrustmaster-t300-menubar</string>
  <key>CFBundleName</key><string>T300 Mac Fix</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleIconFile</key><string>AppIcon.icns</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

create_action_app() {
  app_name=$1
  bundle_id=$2
  action=$3
  icon_name=$4
  command_name=$5
  root_script=$6
  app="$staging/$app_name.app"
  resources="$app/Contents/Resources"
  mkdir -p "$app/Contents/MacOS" "$resources"
  cp "$build_directory/ActionLauncher" "$app/Contents/MacOS/ActionLauncher"
  cp "$build_directory/$icon_name.icns" "$resources/AppIcon.icns"
  cp "$project_dir/scripts/dmg/$command_name" "$resources/$command_name"
  cp "$project_dir/scripts/dmg/$root_script" "$resources/$root_script"
  chmod 755 "$app/Contents/MacOS/ActionLauncher" "$resources/$command_name" "$resources/$root_script"
  if [ "$action" = "install" ]; then
    mkdir -p "$resources/Payload"
    ditto "$menu_app" "$resources/Payload/T300 Mac Fix.app"
    cp "$build_directory/T300PrivilegedHelper" "$resources/Payload/T300PrivilegedHelper"
    chmod 755 "$resources/Payload/T300PrivilegedHelper"
  fi
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>ActionLauncher</string>
  <key>CFBundleIdentifier</key><string>$bundle_id</string>
  <key>CFBundleName</key><string>$app_name</string>
  <key>CFBundleDisplayName</key><string>$app_name</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleIconFile</key><string>AppIcon.icns</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>T300Action</key><string>$action</string>
</dict>
</plist>
PLIST
}

create_action_app "Install T300 Mac Fix" "com.lazd.thrustmaster-t300-installer" \
  install Install install.command install-root.sh
create_action_app "Uninstall T300 Mac Fix" "com.lazd.thrustmaster-t300-uninstaller" \
  uninstall Uninstall uninstall.command uninstall-root.sh

cat > "$staging/Read Me.txt" <<README
THRUSTMASTER T300 MAC FIX
VERSION $version

INSTALL
1. Open Install T300 Mac Fix.
2. In Terminal, approve the one-time administrator prompt.
3. Keep hands clear while the wheel initializes.

The menu-bar app starts at login. The privileged helper initializes the wheel when it is plugged in, without another prompt.

UNINSTALL
Choose Uninstall T300 Mac Fix from the menu bar and confirm, or open Uninstall T300 Mac Fix from this disk image. Approve the administrator prompt in Terminal to remove the helper, startup services, and app.

The DMG is not Developer ID signed or notarized. On macOS, Control-click an app and choose Open if Gatekeeper blocks it.
README
sh -n "$project_dir/scripts/dmg/install.command" \
  "$project_dir/scripts/dmg/uninstall.command" \
  "$project_dir/scripts/dmg/install-root.sh" \
  "$project_dir/scripts/dmg/uninstall-root.sh"
plutil -lint "$menu_app/Contents/Info.plist" \
  "$staging/Install T300 Mac Fix.app/Contents/Info.plist" \
  "$staging/Uninstall T300 Mac Fix.app/Contents/Info.plist" >/dev/null

rm -f "$output_image"
hdiutil create -volname "T300 Mac Fix $version" -srcfolder "$staging" \
  -ov -format UDZO "$output_image" >/dev/null
hdiutil verify "$output_image" >/dev/null
printf 'Created GitHub release asset: %s\n' "$output_image"
