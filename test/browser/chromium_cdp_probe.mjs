import fs from "node:fs";
import zlib from "node:zlib";

const [portText, screenshotPath, httpsUrl, transportMode, expectedUrl] =
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
  clearTimeout(pending.get(message.id).timer);
  pending.delete(message.id);
  if (message.error) reject(new Error(JSON.stringify(message.error)));
  else resolve(message.result);
});
socket.addEventListener("close", () => {
  for (const {reject, timer} of pending.values()) {
    clearTimeout(timer);
    reject(new Error("Chromium DevTools WebSocket closed"));
  }
  pending.clear();
});

function call(method, params = {}) {
  const id = nextId++;
  return new Promise((resolve, reject) => {
    const timeoutMs = Number(process.env.VKMT_CDP_CALL_TIMEOUT_MS || 15000);
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new Error(`${method} timed out after ${timeoutMs}ms`));
    }, timeoutMs);
    pending.set(id, {resolve, reject, timer});
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
console.log("CHROMIUM_CDP_RUNTIME_READY_BEGIN");
const pageStateExpression = `(() => ({
    href: location.href,
    title: document.title,
    readyState: document.readyState,
    htmlLength: document.documentElement?.outerHTML.length || 0,
    text: (document.body?.innerText || "").slice(0, 240),
    width: document.documentElement?.clientWidth || 0,
    height: document.documentElement?.clientHeight || 0,
    userAgent: navigator.userAgent
  }))()`;

function navigationMatches(state, url) {
  if (!url || !state?.href) return Boolean(state);
  const expected = new URL(url);
  const actual = new URL(state.href);
  const normalizedPath = path => path.length > 1 && path.endsWith("/")
    ? path.slice(0, -1)
    : path;
  return expected.protocol === "data:"
    ? actual.protocol === "data:"
    : actual.protocol === expected.protocol &&
      actual.hostname === expected.hostname &&
      normalizedPath(actual.pathname) === normalizedPath(expected.pathname);
}

let pageState;
const navigationDeadline = Date.now() +
  Number(process.env.VKMT_CDP_NAVIGATION_TIMEOUT_MS || 90000);
let lastEvaluationError;
do {
  try {
    const result = await call("Runtime.evaluate", {
      expression: pageStateExpression,
      returnByValue: true
    });
    pageState = result.result.value;
    lastEvaluationError = undefined;
    if (pageState?.readyState === "complete" &&
        navigationMatches(pageState, expectedUrl) &&
        pageState.htmlLength >= 40) break;
  } catch (error) {
    /* Renderer replacement temporarily removes the default execution context.
     * The requested page may still be progressing in its successor renderer. */
    lastEvaluationError = error;
  }
  await pause(250);
} while (Date.now() < navigationDeadline);
if (!pageState && lastEvaluationError) throw lastEvaluationError;
console.log("CHROMIUM_CDP_RUNTIME_READY_OK");
console.log(`CHROMIUM_CDP_PAGE_STATE ${JSON.stringify(pageState)}`);

if (expectedUrl) {
  if (!navigationMatches(pageState, expectedUrl) || pageState.htmlLength < 40) {
    throw new Error(
      `initial navigation did not commit: expected=${expectedUrl} ` +
      `actual=${pageState?.href || "unavailable"} ` +
      `htmlLength=${pageState?.htmlLength || 0}`);
  }
  console.log(`CHROMIUM_CDP_NAVIGATION_OK ${pageState.href}`);
}

/* Preserve the page exactly as Chromium painted it before the deterministic
 * fixture replaces its DOM. This makes a real-site/windowed gate auditable
 * independently from the exact-pixel fixture below. */
const pageScreenshotPath = screenshotPath.endsWith(".png")
  ? `${screenshotPath.slice(0, -4)}-page.png`
  : `${screenshotPath}-page.png`;
if (process.env.VKMT_CDP_SKIP_PAGE_CAPTURE === "1") {
  console.log("CHROMIUM_CDP_PAGE_CAPTURE_SKIPPED");
} else {
  const pageCapture = await call("Page.captureScreenshot", {
    format: "png",
    fromSurface: true,
    captureBeyondViewport: false
  });
  fs.writeFileSync(
    pageScreenshotPath, Buffer.from(pageCapture.data, "base64"));
  console.log(`CHROMIUM_CDP_PAGE_PAINT_OK ${pageScreenshotPath}`);
}

const fixture = await call("Runtime.evaluate", {
  expression: `(async () => {
    try {
      const httpsOk = location.protocol === "https:" ||
        (${JSON.stringify(httpsUrl || "")} &&
         (await fetch(${JSON.stringify(httpsUrl || "")})).ok);
      if (!document.documentElement) {
        document.appendChild(document.createElement("html"));
      }
      if (!document.body) {
        document.documentElement.appendChild(document.createElement("body"));
      }
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
    } catch (error) {
      return {
        protocol: location.protocol,
        httpsOk: location.protocol === "https:",
        audio: "audio-error",
        error: String(error),
        offlineAudioType: typeof OfflineAudioContext
      };
    }
  })()`,
  awaitPromise: true,
  returnByValue: true
});
const fixtureValue = fixture.result.value;
console.log(`CHROMIUM_CDP_FIXTURE ${JSON.stringify(fixtureValue)}`);
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
