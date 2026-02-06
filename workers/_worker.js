export default {
  async fetch(request) {
    const url = new URL(request.url);
    url.protocol = "https:";
    url.hostname = "example.com";
    return fetch(new Request(url, request));
  },
};
