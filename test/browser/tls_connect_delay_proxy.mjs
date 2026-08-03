/* Local HTTP CONNECT proxy used by the TLS contract. It forwards the
 * established TLS stream while deliberately fragmenting both directions so
 * WinHTTP/WinINet exercise partial reads and writes without external network. */
import net from "node:net";

const [listenText, upstreamHost = "127.0.0.1", upstreamText = "19445",
  delayText = "20", chunkText = "3"] = process.argv.slice(2);
const listenPort = Number(listenText);
const upstreamPort = Number(upstreamText);
const delayMs = Number(delayText);
const chunkBytes = Number(chunkText);
if (!listenPort || !upstreamPort || delayMs < 0 || chunkBytes < 1)
  throw new Error("usage: tls_connect_delay_proxy.mjs LISTEN HOST PORT DELAY_MS CHUNK_BYTES");

const sendPieces = (socket, data, state) => {
  for (let offset = 0; offset < data.length; offset += chunkBytes) {
    const piece = Buffer.from(data.subarray(offset, offset + chunkBytes));
    state.delivery = state.delivery.then(() => new Promise(resolve => {
      setTimeout(() => {
        if (!socket.destroyed) socket.write(piece);
        resolve();
      }, delayMs);
    }));
  }
};

const server = net.createServer(client => {
  let request = Buffer.alloc(0);
  let connected = false;
  let upstream;
  const state = {delivery: Promise.resolve()};

  const connect = () => {
    if (connected) return;
    connected = true;
    upstream = net.createConnection({host: upstreamHost, port: upstreamPort});
    upstream.on("data", data => sendPieces(client, data, state));
    upstream.on("end", () => state.delivery.then(() => client.end()));
    upstream.on("error", () => client.destroy());
    client.write("HTTP/1.1 200 Connection Established\r\n\r\n");
    if (request.length) sendPieces(upstream, request, state);
  };

  client.on("data", data => {
    if (!connected) {
      request = Buffer.concat([request, data]);
      const end = request.indexOf("\r\n\r\n");
      if (end < 0) return;
      if (!request.subarray(0, end).toString("ascii").startsWith("CONNECT ")) {
        client.destroy();
        return;
      }
      request = request.subarray(end + 4);
      connect();
    } else sendPieces(upstream, data, state);
  });
  client.on("end", () => { if (upstream) upstream.end(); });
  client.on("error", () => { if (upstream) upstream.destroy(); });
});
server.listen(listenPort, "127.0.0.1", () => {
  console.log(`VKMT_TLS_CONNECT_PROXY_READY port=${listenPort} upstream=${upstreamPort} delay_ms=${delayMs} chunk=${chunkBytes}`);
});
