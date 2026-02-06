addEventListener("scheduled", (event) => {
  event.waitUntil(runKeepalive());
});

const urlString = "https://example.com/up https://example.com/re";
const urls = urlString.split(/[\s,，]+/).filter(Boolean);
const TIMEOUT_MS = 5000;

async function fetchWithTimeout(url) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const res = await fetch(url, { signal: controller.signal });
    console.log(`[keepalive] ${url} -> ${res.status}`);
  } catch (err) {
    console.log(`[keepalive] ${url} failed: ${err.message}`);
  } finally {
    clearTimeout(timeout);
  }
}

async function runKeepalive() {
  if (!urls.length) {
    console.log("[keepalive] no urls configured");
    return;
  }
  await Promise.all(urls.map(fetchWithTimeout));
  console.log("[keepalive] completed");
}
