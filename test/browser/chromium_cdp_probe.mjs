import fs from "node:fs";
import zlib from "node:zlib";

const [portText, screenshotPath, httpsUrl, transportMode] =
  process.argv.slice(2);
const port = Number(portText);
if (!port || !screenshotPath) {
  throw new Error(
    "usage: chromium_cdp_probe.mjs PORT SCREENSHOT.png [HTTPS_URL]");
}

const pause = milliseconds =>
  new Promise(resolve => setTimeout(resolve, milliseconds));

let target;
let browserEndpoint;
let candidateTargetId;
let stableTargetPolls = 0;
let targetStable = false;
for (let attempt = 0; attempt < 120; ++attempt) {
  try {
    const versionResponse =
      await fetch(`http://127.0.0.1:${port}/json/version`, {
        headers: {Connection: "close"}
      });
    const version = await versionResponse.json();
    browserEndpoint = version.webSocketDebuggerUrl;
    const targetsResponse =
      await fetch(`http://127.0.0.1:${port}/json/list`, {
        headers: {Connection: "close"}
      });
    const targets = await targetsResponse.json();
    const candidate = targets.find(item =>
      item.type === "page" && item.webSocketDebuggerUrl);
    if (candidate && candidate.id === candidateTargetId) {
      ++stableTargetPolls;
    } else {
      candidateTargetId = candidate?.id;
      stableTargetPolls = candidate ? 1 : 0;
    }
    target = candidate;
    /* CEF may replace its initial OSR renderer between two HTTP polls,
     * especially once native EGL initialization is available.  Attach to the
     * first published page immediately; command completion is the real
     * liveness gate and avoids racing endpoint retirement. */
    if (target && stableTargetPolls >= 1) {
      targetStable = true;
      break;
    }
  } catch {
    // The browser may not have published its DevTools socket yet.
  }
  await pause(250);
}
if (!target && !browserEndpoint) {
  throw new Error("Chromium DevTools endpoint did not appear");
}

/* A page endpoint is tied to one renderer.  If CEF kept replacing that page
 * throughout the observation window, attach through the browser endpoint
 * instead so renderer replacement does not tear down the control socket. */
if (!targetStable || transportMode === "browser") target = undefined;

const socket = new WebSocket(
  target ? target.webSocketDebuggerUrl : browserEndpoint);
await new Promise((resolve, reject) => {
  socket.addEventListener("open", resolve, {once: true});
  socket.addEventListener("error", reject, {once: true});
});
if (target) {
  console.log(`CHROMIUM_CDP_TARGET ${target.type} ${target.url || ""}`);
}

let nextId = 1;
let activeSessionId;
const pending = new Map();
socket.addEventListener("message", event => {
  const message = JSON.parse(event.data);
  if (!message.id || !pending.has(message.id)) return;
  const {resolve, reject} = pending.get(message.id);
  pending.delete(message.id);
  if (message.error) reject(new Error(JSON.stringify(message.error)));
  else resolve(message.result);
});
socket.addEventListener("close", () => {
  for (const {reject} of pending.values()) {
    reject(new Error("Chromium DevTools WebSocket closed"));
  }
  pending.clear();
});

function call(method, params = {}) {
  const id = nextId++;
  return new Promise((resolve, reject) => {
    pending.set(id, {resolve, reject});
    const message = {id, method, params};
    if (activeSessionId) message.sessionId = activeSessionId;
    socket.send(JSON.stringify(message));
  });
}

if (!target) {
  let targetInfo;
  let lastTargets = [];
  let attachedTargetId;
  let attachedTargetPolls = 0;
  for (let attempt = 0; attempt < 120; ++attempt) {
    const result = await call("Target.getTargets");
    lastTargets = result.targetInfos;
    const candidate = lastTargets.find(item =>
      item.type === "page" && item.targetId);
    if (candidate && candidate.targetId === attachedTargetId) {
      ++attachedTargetPolls;
    } else {
      attachedTargetId = candidate?.targetId;
      attachedTargetPolls = candidate ? 1 : 0;
    }
    targetInfo = candidate;
    if (targetInfo && attachedTargetPolls >= 2) break;
    await pause(250);
  }
  if (!targetInfo || attachedTargetPolls < 2) {
    throw new Error(
      `Chromium DevTools renderer target did not stabilize: ${
        JSON.stringify(lastTargets)}`);
  }
  const attached = await call("Target.attachToTarget", {
    targetId: targetInfo.targetId,
    flatten: true
  });
  activeSessionId = attached.sessionId;
  console.log(
    `CHROMIUM_CDP_TARGET ${targetInfo.type} ${targetInfo.url || ""}`);
}

/* Page.enable crashes CEF 109's 32-bit OSR target before the first command
 * completes.  Neither Runtime.evaluate nor Page.captureScreenshot requires
 * domain-event subscription, so keep the functional probe on the direct
 * command path shared by x64 and i386. */
for (let attempt = 0; attempt < 120; ++attempt) {
  const state = await call("Runtime.evaluate", {
    expression: "document.readyState",
    returnByValue: true
  });
  if (state.result.value === "complete") break;
  await pause(250);
}

const fixture = await call("Runtime.evaluate", {
  expression: `(async () => {
    const httpsOk = location.protocol === "https:" ||
      (${JSON.stringify(httpsUrl || "")} &&
       (await fetch(${JSON.stringify(httpsUrl || "")})).ok);
    document.documentElement.style.cssText =
      "margin:0;width:100%;height:100%;background:#112233";
    document.body.style.cssText =
      "margin:0;width:100vw;height:100vh;background:#112233;overflow:hidden";
    document.body.innerHTML =
      "<input id=i style='position:absolute;left:32px;top:32px;width:80px;height:24px'>";
    const input = document.getElementById("i");
    input.addEventListener("input", () => input.dataset.input = "input-ok");
    document.body.addEventListener("mousedown",
      () => document.body.dataset.mouse = "mouse-ok");
    const audio = new OfflineAudioContext(1, 8, 8000);
    const buffer = audio.createBuffer(1, 8, 8000);
    buffer.getChannelData(0)[0] = 0.5;
    return {
      protocol: location.protocol,
      httpsOk,
      audio: buffer.getChannelData(0)[0] === 0.5 ? "audio-ok" : "audio-bad"
    };
  })()`,
  awaitPromise: true,
  returnByValue: true
});
const fixtureValue = fixture.result.value;
if (!fixtureValue.httpsOk || fixtureValue.audio !== "audio-ok") {
  throw new Error(`bad Chromium fixture result ${JSON.stringify(fixtureValue)}`);
}
console.log("CHROMIUM_CDP_HTTPS_AUDIO_OK");

await call("Page.bringToFront");
await call("Runtime.evaluate", {
  expression: `(() => {
    const input = document.getElementById("i");
    input.focus();
    input.value = "VKMT";
    return input.dispatchEvent(new InputEvent("input", {
      data: "VKMT", inputType: "insertText", bubbles: true
    }));
  })()`,
  returnByValue: true
});
const input = await call("Runtime.evaluate", {
  expression: "({value:i.value,event:i.dataset.input})",
  returnByValue: true
});
if (input.result.value.value !== "VKMT" ||
    input.result.value.event !== "input-ok") {
  throw new Error(
    `text input did not reach renderer: ${JSON.stringify(input.result.value)}`);
}
console.log("CHROMIUM_CDP_INPUT_OK");

await pause(500);
const capture = await call("Page.captureScreenshot", {
  format: "png",
  fromSurface: true,
  captureBeyondViewport: false
});
const png = Buffer.from(capture.data, "base64");
fs.writeFileSync(screenshotPath, png);

function paeth(a, b, c) {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
}

function decodeCenterPixel(data) {
  const signature = "89504e470d0a1a0a";
  if (data.subarray(0, 8).toString("hex") !== signature) {
    throw new Error("capture is not PNG");
  }
  let offset = 8;
  let width, height, bitDepth, colorType;
  const idat = [];
  while (offset + 12 <= data.length) {
    const length = data.readUInt32BE(offset);
    const type = data.toString("ascii", offset + 4, offset + 8);
    const payload = data.subarray(offset + 8, offset + 8 + length);
    if (type === "IHDR") {
      width = payload.readUInt32BE(0);
      height = payload.readUInt32BE(4);
      bitDepth = payload[8];
      colorType = payload[9];
    } else if (type === "IDAT") {
      idat.push(payload);
    } else if (type === "IEND") {
      break;
    }
    offset += 12 + length;
  }
  const channels = colorType === 6 ? 4 : colorType === 2 ? 3 : 0;
  if (!width || !height || bitDepth !== 8 || !channels) {
    throw new Error(
      `unsupported PNG width=${width} height=${height} depth=${bitDepth} type=${colorType}`);
  }
  const packed = zlib.inflateSync(Buffer.concat(idat));
  const stride = width * channels;
  const rows = Buffer.alloc(stride * height);
  let source = 0;
  for (let y = 0; y < height; ++y) {
    const filter = packed[source++];
    for (let x = 0; x < stride; ++x) {
      const raw = packed[source++];
      const left = x >= channels ? rows[y * stride + x - channels] : 0;
      const up = y ? rows[(y - 1) * stride + x] : 0;
      const upperLeft = y && x >= channels
        ? rows[(y - 1) * stride + x - channels] : 0;
      let value;
      if (filter === 0) value = raw;
      else if (filter === 1) value = raw + left;
      else if (filter === 2) value = raw + up;
      else if (filter === 3) value = raw + Math.floor((left + up) / 2);
      else if (filter === 4) value = raw + paeth(left, up, upperLeft);
      else throw new Error(`unsupported PNG filter ${filter}`);
      rows[y * stride + x] = value & 0xff;
    }
  }
  const pixelOffset =
    Math.floor(height / 2) * stride + Math.floor(width / 2) * channels;
  return {
    width,
    height,
    rgba: [
      rows[pixelOffset],
      rows[pixelOffset + 1],
      rows[pixelOffset + 2],
      channels === 4 ? rows[pixelOffset + 3] : 255
    ]
  };
}

const decoded = decodeCenterPixel(png);
if (decoded.rgba.join(",") !== "17,34,51,255") {
  throw new Error(
    `bad Chromium pixel ${decoded.rgba.join(",")} at ${decoded.width}x${decoded.height}`);
}
console.log(
  `CHROMIUM_CDP_PIXEL_OK ${decoded.width}x${decoded.height} ${decoded.rgba.join(",")}`);
socket.close();
