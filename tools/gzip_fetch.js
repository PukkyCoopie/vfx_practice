(function () {
  if (window.__vfxGzipFetch) {
    return;
  }
  window.__vfxGzipFetch = true;
  if (typeof DecompressionStream === "undefined") {
    return;
  }

  var originalFetch = window.fetch.bind(window);

  function requestUrl(input) {
    if (typeof input === "string") {
      return input;
    }
    if (input instanceof URL) {
      return input.href;
    }
    return input.url;
  }

  window.fetch = async function (input, init) {
    var url = requestUrl(input).split("?")[0];
    if (!/\.(wasm|pck)$/i.test(url)) {
      return originalFetch(input, init);
    }

    var gzInit = Object.assign({}, init || {}, { method: "GET" });
    if (gzInit.headers) {
      var headers = new Headers(gzInit.headers);
      headers.delete("Range");
      headers.delete("range");
      gzInit.headers = headers;
    }

    var compressed = await originalFetch(url + ".gz", gzInit);
    if (compressed.ok && compressed.body) {
      var raw = await new Response(
        compressed.body.pipeThrough(new DecompressionStream("gzip"))
      ).arrayBuffer();
      return new Response(raw, {
        status: 200,
        headers: {
          "Content-Type": url.endsWith(".wasm")
            ? "application/wasm"
            : "application/octet-stream",
          "Content-Length": String(raw.byteLength),
        },
      });
    }
    return originalFetch(input, init);
  };
})();
