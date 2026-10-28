import { setTimeout as delay } from "node:timers/promises";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import usb from "usb";

const { getDeviceList } = usb;
const executeFile = promisify(execFile);

const vendorId = 0x044f;
const genericProductId = 0xb65d;
const nativeProductIds = new Map([
  [0xb66d, "PS4"],
  [0xb66e, "PS3 / PC"],
  [0xb66f, "PS3 advanced"],
]);
export const t300Models = new Set([0x0204, 0x0206, 0x0209, 0x020a]);
const preparationPackets = [
  [0x42, 0x01, 0, 0, 0, 0, 0, 0, 0],
  [0x0a, 0x04, 0x90, 0x03, 0, 0, 0, 0],
  [0x0a, 0x04, 0x00, 0x0c, 0, 0, 0, 0],
  [0x0a, 0x04, 0x12, 0x10, 0, 0, 0, 0],
  [0x0a, 0x04, 0x00, 0x06, 0, 0, 0, 0],
];

const hex = (value) => value.toString(16).padStart(4, "0");
const isWheel = (device) => device.deviceDescriptor.idVendor === vendorId;
const productId = (device) => device.deviceDescriptor.idProduct;
const portPath = (device) => `${device.busNumber}:${device.portNumbers.join(".")}`;

export function assertT300PedalMode(product) {
  if (product === 0xb66e) return;
  throw new Error(
    `044f:${hex(product)} is ${nativeProductIds.get(product) ?? "unknown"} mode, not the verified PS3 / PC pedal mode (044f:b66e). ` +
      "Unplug USB, select PS3 / PC on the wheel base, reconnect, then rerun --initialize. " +
      "The initializer does not change the physical PS3/PS4 switch.",
  );
}

export function parseT300Model(response) {
  if (!Buffer.isBuffer(response) || response.length < 8)
    throw new Error("Wheel returned a truncated model response; refusing to switch modes.");
  const type = response.readUInt16LE(0);
  if (type !== 0x0049 && type !== 0x0047)
    throw new Error(`Unknown model response type 0x${hex(type)}; refusing to switch modes.`);
  if (type === 0x0049 && response.length < 16)
    throw new Error(
      "Wheel returned a truncated extended model response; refusing to switch modes.",
    );
  const model = response.readUInt16LE(6);
  if (!t300Models.has(model))
    throw new Error(
      `Model 0x${hex(model)} is not a supported attached T300; refusing to switch modes.`,
    );
  return model;
}

function controlTransfer(device, requestType, request, value, data) {
  return new Promise((resolveTransfer, reject) => {
    device.controlTransfer(requestType, request, value, 0, data, (error, response) => {
      if (error) reject(error);
      else resolveTransfer(response);
    });
  });
}

function transfer(endpoint, packet) {
  return new Promise((resolveTransfer, reject) => {
    endpoint.transfer(Buffer.from(packet), (error) => {
      if (error) reject(error);
      else resolveTransfer();
    });
  });
}

async function inspectFreshDevices() {
  const { stdout } = await executeFile(
    process.execPath,
    [fileURLToPath(import.meta.url), "--inspect-json"],
    { timeout: 5000 },
  );
  return JSON.parse(stdout);
}

export async function verifyNativeMode(
  expectedPort,
  listDevices = getDeviceList,
  refreshDevices = inspectFreshDevices,
  wait = delay,
) {
  const findWheel = (devices) =>
    devices.find(
      (candidate) =>
        isWheel(candidate) &&
        nativeProductIds.has(productId(candidate)) &&
        portPath(candidate) === expectedPort,
    );
  for (let attempt = 0; attempt < 40; attempt++) {
    const native = findWheel(listDevices());
    if (native) {
      assertT300PedalMode(productId(native));
      return native;
    }
    await wait(250);
  }
  let refreshed;
  try {
    refreshed = await refreshDevices();
  } catch (error) {
    console.warn(`Fresh USB inspection could not confirm the switch: ${error.message}`);
    return undefined;
  }
  const native = findWheel(refreshed);
  if (native) assertT300PedalMode(productId(native));
  return native;
}

export async function initialize(device, listDevices = getDeviceList) {
  const expectedPort = portPath(device);
  let wheelInterface;
  let claimed = false;
  let switchRequested = false;
  device.open();
  try {
    device.timeout = 2000;
    wheelInterface = device.interfaces.find((candidate) =>
      candidate.endpoints.some(
        (endpoint) => endpoint.direction === "out" && endpoint.transferType === 3,
      ),
    );
    if (!wheelInterface) throw new Error("No interrupt output interface found; no packets sent.");
    if (process.platform !== "win32" && wheelInterface.isKernelDriverActive())
      device.setAutoDetachKernelDriver(true);
    wheelInterface.claim();
    claimed = true;
    const output = wheelInterface.endpoints.find(
      (endpoint) => endpoint.direction === "out" && endpoint.transferType === 3,
    );
    output.timeout = 2000;
    console.log("\n⚠️  Preparing wheel... Keep hands clear: the wheel may recalibrate!");
    for (const packet of preparationPackets) await transfer(output, packet);
    const response = await controlTransfer(device, 0xc1, 73, 0, 16);
    const model = parseT300Model(response);
    console.log(`🔍 Confirmed T300 model 0x${hex(model)}.`);
    console.log("🔄 Requesting native USB mode.");
    switchRequested = true;
    try {
      await controlTransfer(device, 0x41, 83, 0x0005, Buffer.alloc(0));
    } catch (error) {
      if (
        ![
          "LIBUSB_ERROR_NO_DEVICE",
          "LIBUSB_ERROR_PIPE",
          "LIBUSB_ERROR_IO",
          "LIBUSB_TRANSFER_STALL",
        ].includes(error.message)
      )
        throw error;
    }
  } finally {
    if (claimed) {
      await new Promise((release) => wheelInterface.release(false, () => release()));
    }
    device.close();
  }
  if (!switchRequested) return;
  const native = await verifyNativeMode(expectedPort, listDevices);
  if (native) {
    console.log(
      `✅ Initialization successful: T300 confirmed in PS3 / PC USB mode (044f:${hex(productId(native))}).`,
    );
    console.log("\n✨ Reload the game and test gas, brake, clutch, steering, and buttons!");
    return true;
  }
  console.warn(
    "Mode-switch request sent, but the result is unconfirmed. The wheel may already be working. " +
      "Run npm run wheel:init -- --inspect to check its current USB mode before retrying initialization.",
  );
  return false;
}

async function main() {
  const args = process.argv.slice(2);
  if (
    args.length > 1 ||
    (args.length && !["--inspect", "--inspect-json", "--initialize", "--help"].includes(args[0]))
  )
    throw new Error("Usage: npm run wheel:init -- [--inspect | --initialize | --help]");
  if (args[0] === "--help") {
    console.log("Usage: npm run wheel:init -- [--inspect | --initialize]");
    console.log(
      "Default: inspect USB IDs without opening, claiming, or sending packets to the wheel.",
    );
    console.log(
      "--initialize: prepare an attached T300 and request native USB mode. The wheel may move.",
    );
    console.log(
      "This does not flash firmware or install a kernel driver. Unplugging may reset the mode.",
    );
    return;
  }
  const wheels = getDeviceList().filter(isWheel);
  if (args[0] === "--inspect-json") {
    console.log(
      JSON.stringify(
        wheels.map((device) => ({
          busNumber: device.busNumber,
          portNumbers: device.portNumbers,
          deviceDescriptor: {
            idVendor: device.deviceDescriptor.idVendor,
            idProduct: productId(device),
          },
        })),
      ),
    );
    return;
  }
  let inNativeMode = false;
  for (const device of wheels) {
    const mode =
      productId(device) === genericProductId
        ? "🛑 Generic"
        : nativeProductIds.has(productId(device))
          ? `✅ Native T300: ${nativeProductIds.get(productId(device))}`
          : "other Thrustmaster";
    console.log(`🎮 USB ${portPath(device)} - 044f:${hex(productId(device))}\n  ${mode}`);
    if (nativeProductIds.has(productId(device))) inNativeMode = true;
  }
  if (args[0] !== "--initialize") {
    if (!wheels.length) console.log("\n🔎 No Thrustmaster USB devices found.");
    if (inNativeMode) {
      console.log("\n✨ Your T300 is in native mode. Go race!");
    } else {
      console.log("\nInspection only; no wheel initialization packets sent.");
    }
    return;
  }
  const generic = wheels.filter((device) => productId(device) === genericProductId);
  if (generic.length !== 1) {
    const native = wheels.find((device) => nativeProductIds.has(productId(device)));
    if (!generic.length && native) {
      assertT300PedalMode(productId(native));
      console.log(
        "\n✨ A T300 is already in PS3 / PC USB mode (044f:b66e); no initialization needed.",
      );
      return;
    }
    throw new Error(
      "Connect exactly one generic Thrustmaster wheel (044f:b65d) before initializing.",
    );
  }
  if ((await initialize(generic[0])) === false) process.exitCode = 2;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch((error) => {
    console.error(`Wheel initialization failed: ${error.message}`);
    console.error(
      "Close apps using the wheel and retry. macOS USB access may require elevated privileges.",
    );
    process.exitCode = 1;
  });
}
