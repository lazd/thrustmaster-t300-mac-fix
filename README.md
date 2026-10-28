# Thrustmaster T300 Mac Fix

This script makes it possible to use your Thrustmaster T300 in macOS without any special drivers or apps, just a quick command line call.

1. Set the T300's mode switch to **PS3 / PC**.
2. Connect the T300 to your Mac over USB.
3. Install dependencies and initialize the wheel:

```sh
npm install
npm run initialize
```

Warning: The initializer may move the wheel while it recalibrates, so keep your hands clear.

It requests native USB mode; it does not change the physical switch or install firmware. The mode will reset when you unplug the wheel.

To check the live controller inputs, open `test-controller.html` or simply run:

```sh
npm run test
```

The browser opens automatically, and the monitor starts scanning as soon as the page loads. It displays the browser's indexed axes and buttons.

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
