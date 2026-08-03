const [portText] = process.argv.slice(2);
const port = Number(portText);
const pause = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));

let endpoint;
for (let attempt = 0; attempt !== 240; ++attempt) {
  try {
    const response = await fetch(`http://127.0.0.1:${port}/json/list`, {
      headers: {Connection: "close"}
    });
    const targets = await response.json();
    endpoint = targets.find(target =>
      target.type === "page" && target.webSocketDebuggerUrl)?.webSocketDebuggerUrl;
    if (endpoint) break;
  } catch {
    // Browser initialization is still in progress.
  }
  await pause(250);
}
if (!endpoint) throw new Error("Chromium DevTools endpoint did not appear");

const socket = new WebSocket(endpoint);
await new Promise((resolve, reject) => {
  socket.addEventListener("open", resolve, {once: true});
  socket.addEventListener("error", reject, {once: true});
});
console.log("CHROMIUM_NETLOG_CLOSE_CONNECTED");
await pause(Number(process.env.VKMT_CDP_NETLOG_DWELL_MS || 15000));

const response = new Promise((resolve, reject) => {
  const timer = setTimeout(() => reject(new Error("Browser.close timed out")), 15000);
  socket.addEventListener("message", event => {
    const message = JSON.parse(event.data);
    if (message.id !== 1) return;
    clearTimeout(timer);
    if (message.error) reject(new Error(JSON.stringify(message.error)));
    else resolve(message.result);
  });
});
socket.send(JSON.stringify({
  id: 1,
  method: "Runtime.evaluate",
  params: {expression: "window.close(); true", returnByValue: true}
}));
await response;
console.log("CHROMIUM_NETLOG_CLOSE_OK");
