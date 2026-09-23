module.exports = async function handler(req, res) {
  const videoId = req.query && req.query.v;

  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Headers", "Range, Content-Type");
  res.setHeader("Access-Control-Expose-Headers", "Content-Length, Content-Range, Accept-Ranges");
  res.setHeader("Cache-Control", "no-store");

  if (req.method === "OPTIONS") {
    res.status(204).end();
    return;
  }

  if (!videoId) {
    res.status(400).send("Missing v");
    return;
  }

  try {
    const upstream = await fetch(
      "https://stream.zemer.io/stream?v=" + encodeURIComponent(videoId),
      {
        headers: {
          "x-zemer-debug": "1",
          "Accept": "audio/*"
        }
      }
    );

    res.statusCode = upstream.status;

    for (const [name, value] of upstream.headers) {
      const lower = name.toLowerCase();
      if (
        lower === "content-type" ||
        lower === "content-length" ||
        lower === "content-range" ||
        lower === "accept-ranges"
      ) {
        res.setHeader(name, value);
      }
    }

    if (!upstream.body) {
      res.end();
      return;
    }

    const reader = upstream.body.getReader();

    while (true) {
      const chunk = await reader.read();
      if (chunk.done) break;
      res.write(Buffer.from(chunk.value));
    }

    res.end();
  } catch (error) {
    console.error("Zemer stream proxy error:", error);
    if (!res.headersSent) {
      res.status(502).send("Unable to reach Zemer stream");
    } else {
      res.end();
    }
  }
};
