const { app, BrowserWindow } = require("electron");
const fs = require("fs");
const https = require("https");

const resultPath = process.env.VKMT_ELECTRON_RESULT;
const httpsUrl = process.env.VKMT_ELECTRON_HTTPS_URL;

function finish(ok, detail) {
  const marker = ok
    ? `ELECTRON_HTTPS_INPUT_AUDIO_PIXEL_OK ${detail}\n`
    : `ELECTRON_FAIL ${detail}\n`;
  process.stdout.write(marker);
  if (resultPath) fs.writeFileSync(resultPath, marker, "utf8");
  app.exit(ok ? 0 : 2);
}

app.commandLine.appendSwitch("no-sandbox");
app.commandLine.appendSwitch("disable-gpu-compositing");
app.commandLine.appendSwitch("autoplay-policy", "no-user-gesture-required");

function getHttps(url) {
  return new Promise((resolve, reject) => {
    const request = https.get(url, { rejectUnauthorized: false }, response => {
      response.resume();
      response.on("end", () => resolve(response.statusCode));
    });
    request.setTimeout(15000, () => request.destroy(new Error("HTTPS timeout")));
    request.on("error", reject);
  });
}

app.whenReady().then(async () => {
  const status = await getHttps(httpsUrl);
  if (status !== 200) throw new Error(`HTTPS status ${status}`);
  process.stdout.write("ELECTRON_HTTPS_OK\n");

  const window = new BrowserWindow({
    width: 320,
    height: 240,
    show: false,
    webPreferences: {
      contextIsolation: true,
      sandbox: false,
      backgroundThrottling: false
    }
  });
  window.loadURL(
    "data:text/html,<canvas id=c width=4 height=4></canvas><input id=i>"
  );
  await new Promise(resolve => setTimeout(resolve, 10000));
  const rendererResult = window.webContents.executeJavaScript(`(() => {
    const c = document.getElementById("c");
    const i = document.getElementById("i");
    const x = c.getContext("2d");
    x.fillStyle = "#112233";
    x.fillRect(0, 0, 4, 4);
    i.addEventListener("input", () => i.dataset.hit = "input-ok");
    i.value = "VKMT";
    i.dispatchEvent(new Event("input", { bubbles: true }));
    const pixel = [...x.getImageData(0, 0, 1, 1).data].join(",");
    const audio = new OfflineAudioContext(1, 8, 8000);
    const buffer = audio.createBuffer(1, 8, 8000);
    buffer.getChannelData(0)[0] = 0.5;
    return {
      marker: "VKMT_ELECTRON_OK",
      pixel,
      input: i.dataset.hit,
      audio: buffer.getChannelData(0)[0] === 0.5 ? "audio-ok" : "audio-bad"
    };
  })()`);
  const result = await Promise.race([
    rendererResult,
    new Promise((_, reject) =>
      setTimeout(() => reject(new Error("renderer IPC timeout")), 30000))
  ]);
  if (result.marker !== "VKMT_ELECTRON_OK" ||
      result.pixel !== "17,34,51,255" ||
      result.input !== "input-ok" ||
      result.audio !== "audio-ok") {
    throw new Error(`bad renderer result ${JSON.stringify(result)}`);
  }
  window.destroy();
  finish(true, JSON.stringify(result));
}).catch(error => finish(false, error.stack || String(error)));

setTimeout(() => finish(false, "timeout"), 90000).unref();
