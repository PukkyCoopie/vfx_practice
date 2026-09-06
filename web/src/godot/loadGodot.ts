function requestUrl(input: RequestInfo | URL): string {
  if (typeof input === "string") {
    return input;
  }
  if (input instanceof URL) {
    return input.href;
  }
  return input.url;
}

function withoutQuery(url: string): string {
  return url.split("?")[0];
}

function loadScript(src: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const existing = document.querySelector(`script[src="${src}"]`);
    if (existing) {
      resolve();
      return;
    }
    const script = document.createElement("script");
    script.src = src;
    script.async = false;
    script.onload = () => resolve();
    script.onerror = () => reject(new Error(`Failed to load script: ${src}`));
    document.head.appendChild(script);
  });
}

async function getGzipUncompressedSize(url: string): Promise<number> {
  try {
    const response = await fetch(url, { headers: { Range: "bytes=-4" } });
    if (!response.ok) {
      return 0;
    }
    const announced = Number.parseInt(response.headers.get("content-length") ?? "", 10);
    if (Number.isFinite(announced) && announced > 8) {
      return 0;
    }
    const buf = await response.arrayBuffer();
    if (buf.byteLength !== 4) {
      return 0;
    }
    return new DataView(buf).getUint32(0, true);
  } catch {
    return 0;
  }
}

async function getFileSize(url: string): Promise<number> {
  try {
    const response = await fetch(url, { method: "GET", headers: { Range: "bytes=0-0" } });
    const range = response.headers.get("content-range");
    if (range) {
      const total = Number.parseInt(range.split("/")[1] ?? "", 10);
      if (Number.isFinite(total) && total > 0) {
        return total;
      }
    }
    const length = response.headers.get("content-length");
    return length ? Number.parseInt(length, 10) : 0;
  } catch {
    return 0;
  }
}

function installCompressedFetch(): void {
  const flag = "__vfxCompressedFetch";
  if ((window as unknown as Record<string, boolean>)[flag]) {
    return;
  }
  (window as unknown as Record<string, boolean>)[flag] = true;

  const originalFetch = window.fetch.bind(window);
  window.fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = withoutQuery(requestUrl(input));
    if (!/\.(wasm|pck)$/i.test(url) || typeof DecompressionStream === "undefined") {
      return originalFetch(input, init);
    }

    const gzInit: RequestInit = { ...(init ?? {}), method: "GET" };
    if (gzInit.headers) {
      const headers = new Headers(gzInit.headers);
      headers.delete("Range");
      headers.delete("range");
      gzInit.headers = headers;
    }

    const compressed = await originalFetch(`${url}.gz`, gzInit);
    if (compressed.ok && compressed.body) {
      const raw = await new Response(compressed.body.pipeThrough(new DecompressionStream("gzip"))).arrayBuffer();
      return new Response(raw, {
        status: 200,
        headers: {
          "Content-Type": url.endsWith(".wasm") ? "application/wasm" : "application/octet-stream",
          "Content-Length": String(raw.byteLength),
        },
      });
    }
    return originalFetch(input, init);
  };
}

export function godotAssetPrefix(): string {
  const base = import.meta.env.BASE_URL.endsWith("/")
    ? import.meta.env.BASE_URL
    : `${import.meta.env.BASE_URL}/`;
  return `${base}godot/index`.replace(/\/{2,}/g, "/");
}

export function syncCanvasSize(canvas: HTMLCanvasElement): void {
  const parent = canvas.parentElement;
  if (!parent) {
    return;
  }
  const width = Math.max(1, Math.floor(parent.clientWidth));
  const height = Math.max(1, Math.floor(parent.clientHeight));
  if (canvas.width !== width || canvas.height !== height) {
    canvas.width = width;
    canvas.height = height;
  }
}

export async function waitForBridge(timeoutMs = 20000): Promise<void> {
  const started = Date.now();
  return new Promise((resolve, reject) => {
    const tick = () => {
      if (window.vfxReady) {
        resolve();
        return;
      }
      if (Date.now() - started > timeoutMs) {
        reject(new Error("Timed out waiting for Godot"));
        return;
      }
      window.requestAnimationFrame(tick);
    };
    tick();
  });
}

let loadOnce: Promise<Engine> | null = null;

export async function loadGodotEngine(
  canvas: HTMLCanvasElement,
  onProgress?: (ratio: number) => void,
): Promise<Engine> {
  if (loadOnce) {
    return loadOnce;
  }

  loadOnce = (async () => {
    const prefix = godotAssetPrefix();
    const scriptUrl = `${prefix}.js`;
    const wasmUrl = `${prefix}.wasm`;
    const pckUrl = `${prefix}.pck`;

    const [wasmSize, pckSize] = await Promise.all([
      getGzipUncompressedSize(`${wasmUrl}.gz`).then((size) => size || getFileSize(wasmUrl)),
      getGzipUncompressedSize(`${pckUrl}.gz`).then((size) => size || getFileSize(pckUrl)),
    ]);
    installCompressedFetch();

    await loadScript(scriptUrl);
    if (typeof window.Engine === "undefined") {
      throw new Error("Godot Engine global was not created.");
    }

    syncCanvasSize(canvas);

    const fileSizes: Record<string, number> = {};
    if (wasmSize > 0) {
      fileSizes[wasmUrl] = wasmSize;
    }
    if (pckSize > 0) {
      fileSizes[pckUrl] = pckSize;
    }

    const engine = new window.Engine({
      args: ["--main-pack", "index.pck"],
      canvas,
      canvasResizePolicy: 0,
      ensureCrossOriginIsolationHeaders: false,
      executable: "index",
      experimentalVK: false,
      fileSizes,
      focusCanvas: true,
      gdextensionLibs: [],
      serviceWorker: false,
      onProgress: (current, total) => {
        if (total > 0) {
          onProgress?.(Math.min(1, current / total));
        }
      },
      onPrintError: (text) => {
        console.error(text);
      },
    });

    await Promise.all([engine.init(prefix), engine.preloadFile(pckUrl, "index.pck")]);
    await engine.start();
    onProgress?.(1);
    return engine;
  })().catch((error) => {
    loadOnce = null;
    throw error;
  });

  return loadOnce;
}
