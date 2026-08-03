import net from "node:net";

const [listenPortText, upstreamHost = "127.0.0.1", upstreamPortText = "19445",
  delayText = "25", chunkText = "512"] = process.argv.slice(2);
const listenPort = Number(listenPortText);
const upstreamPort = Number(upstreamPortText);
const delayMs = Number(delayText);
const chunkBytes = Number(chunkText);
if (!listenPort || !upstreamPort || delayMs < 0 || chunkBytes < 1) {
  throw new Error("usage: tls_delay_proxy.mjs LISTEN_PORT HOST PORT DELAY_MS CHUNK_BYTES");
}

const server = net.createServer(client => {
  const upstream = net.createConnection({host: upstreamHost, port: upstreamPort});
  let delivery = Promise.resolve();

  client.on("data", data => upstream.write(data));
  upstream.on("data", data => {
    for (let offset = 0; offset < data.length; offset += chunkBytes) {
      const piece = Buffer.from(data.subarray(offset, offset + chunkBytes));
      delivery = delivery.then(() => new Promise(resolve => {
        setTimeout(() => {
          if (!client.destroyed) client.write(piece);
          resolve();
        }, delayMs);
      }));
    }
  });
  upstream.on("end", () => delivery.then(() => client.end()));
  client.on("end", () => upstream.end());
  client.on("error", () => upstream.destroy());
  upstream.on("error", () => client.destroy());
});

server.listen(listenPort, "127.0.0.1", () => {
  console.log(`VKMT_TLS_DELAY_PROXY_READY port=${listenPort} delay_ms=${delayMs} chunk=${chunkBytes}`);
});
