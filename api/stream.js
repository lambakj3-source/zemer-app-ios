export default async function handler(request) {
  const url = new URL(request.url);
  const videoId = url.searchParams.get("v");

  if (!videoId) {
    return new Response("Missing v", { status: 400 });
  }

  const upstreamUrl =
    "https://stream.zemer.io/stream?v=" + encodeURIComponent(videoId);

  const upstream = await fetch(upstreamUrl, {
    headers: {
      "x-zemer-debug": "1",
      "Accept": "audio/*"
    },
    signal: request.signal
  });

  const headers = new Headers();
  const contentType = upstream.headers.get("content-type");
  const contentLength = upstream.headers.get("content-length");
  const contentRange = upstream.headers.get("content-range");
  const acceptRanges = upstream.headers.get("accept-ranges");

  headers.set("Access-Control-Allow-Origin", "*");
  headers.set("Access-Control-Expose-Headers", "Content-Length, Content-Range, Accept-Ranges");
  headers.set("Cache-Control", "no-store");

  if (contentType) headers.set("Content-Type", contentType);
  if (contentLength) headers.set("Content-Length", contentLength);
  if (contentRange) headers.set("Content-Range", contentRange);
  if (acceptRanges) headers.set("Accept-Ranges", acceptRanges);

  return new Response(upstream.body, {
    status: upstream.status,
    headers
  });
}
