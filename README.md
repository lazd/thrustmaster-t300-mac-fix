# Thrustmaster T300 Mac Fix

Initialize a Thrustmaster T300 on macOS with a menu-bar app and automatic plug-in setup. No Node.js or third-party drivers are needed.

## Install from DMG

1. Download [the latest **T300-Mac-Fix** DMG](https://github.com/lazd/thrustmaster-t300-mac-fix/releases/latest/download/T300-Mac-Fix.dmg).
2. Set the wheel's mode switch to **PS3 / PC**, then connect it to your Mac over USB.
3. Open the downloaded DMG and launch **Install T300 Mac Fix**.
4. Approve the one-time administrator prompt in Terminal. Keep hands clear while the wheel initializes; it may move.

The menu-bar app starts at login and appears when the T300 is connected. Future plug-ins do not require another administrator prompt. If Gatekeeper blocks the unsigned app, Control-click it and choose **Open**.

To remove the app and its helper, choose **Uninstall T300 Mac Fix...** from the menu bar and confirm, then approve the administrator prompt in Terminal. You can also open the DMG and launch **Uninstall T300 Mac Fix**.

To check the live controller inputs, open `test-controller.html` or simply run:

```sh
npm run test
```

The browser opens automatically, and the monitor starts scanning as soon as the page loads. It displays the browser's indexed axes and buttons.

You can also use the [online controller tester](https://lazd.github.io/thrustmaster-t300-mac-fix/). Connect the initialized wheel, press a wheel button to activate browser gamepad access, then turn the wheel and press buttons or pedals to watch their indexed values update. For a direct release download, use [Download the latest DMG](https://github.com/lazd/thrustmaster-t300-mac-fix/releases/latest/download/T300-Mac-Fix.dmg).

## Menu Bar App

The menu app launches at login and stays hidden until a T300 is connected. A root LaunchDaemon watches for the wheel and initializes generic mode automatically; the menu shows the result and offers retry, uninstall, and quit options. Administrator approval is required when installing, updating, or uninstalling the helper, but plugging in the wheel never prompts. Building or updating the app requires Xcode Command Line Tools.

Remove the app and its login item with:

```sh
sh ./install-menubar.sh --uninstall
```

## Build a Release DMG

To build the precompiled installer and uninstaller image locally:

```sh
npm run release:dmg
```

The DMG is written to `dist/T300-Mac-Fix.dmg` for attaching to a GitHub Release. Its read-me includes the package version. End users do not need Node.js or Xcode Command Line Tools.

You can then use your Thrustmaster T300 in any game and your pedals will act as axes instead of buttons, steering will be precise, and buttons will be mapped predictably.

## T300 6-Axis Layout

Once this script is ran, your T300 will map as follows.

### Buttons

| Button         | Number |
| -------------- | -----: |
| Left paddle    |      0 |
| Right paddle   |      1 |
| Wheel button 2 |      2 |
| Wheel button 3 |      3 |
| Wheel button 4 |      4 |
| Wheel button 5 |      5 |
| Wheel button 6 |      6 |
| Wheel button 7 |      7 |
| Wheel button 8 |      8 |
| Wheel button 9 |      9 |
| L3             |     10 |
| R3             |     11 |
| D-pad up       |     12 |
| D-pad right    |     13 |
| D-pad down     |     14 |
| D-pad left     |     15 |

### Axes

| Axis              | Number |
| ----------------- | -----: |
| Steering          |      0 |
| Accelerator pedal |      1 |
| Brake pedal       |      2 |
| Clutch pedal      |      3 |
| D-pad horizontal  |      4 |
| D-pad vertical    |      5 |
