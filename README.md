# Thrustmaster T300 Mac Fix

Use the native menu-bar app to initialize your Thrustmaster T300 in macOS without Node.js or third-party drivers. Administrator approval is needed once to install its privileged USB helper.

1. Set the T300's mode switch to **PS3 / PC**.
2. Connect the T300 to your Mac over USB.
3. Install and start the menu-bar app:

```sh
sh ./install-menubar.sh
```

The wheel may move while it recalibrates, so keep your hands clear.

It requests native USB mode; it does not change the physical switch or install firmware. The mode will reset when you unplug the wheel.

To check the live controller inputs, open `test-controller.html` or simply run:

```sh
npm run test
```

The browser opens automatically, and the monitor starts scanning as soon as the page loads. It displays the browser's indexed axes and buttons.

## Menu Bar App

The menu app launches at login and stays hidden until a T300 is connected. A root LaunchDaemon watches for the wheel and initializes generic mode automatically; the menu shows the result and offers retry and quit options. Administrator approval is required when installing or updating the helper, but plugging in the wheel never prompts. Building or updating the app requires Xcode Command Line Tools.

Remove the app and its login item with:

```sh
sh ./install-menubar.sh --uninstall
```

## GitHub DMG

Build the precompiled installer and uninstaller image with:

```sh
npm run release:dmg
```

The versioned DMG is written to `dist/` and can be attached to a GitHub Release. It contains the precompiled menu app and privileged helper, so end users do not need Node.js or Xcode Command Line Tools. The installer and uninstaller each request administrator approval when run. This DMG is unsigned and not notarized; Gatekeeper may require Control-clicking an app and choosing **Open**.

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
