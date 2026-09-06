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

async function getFileSize(url: string): Promise<number> {
  try {
    const response = await fetch(url, { method: "HEAD" });
    const length = response.headers.get("content-length");
    return length ? Number.parseInt(length, 10) : 0;
  } catch {
    return 0;
  }
}

export async function waitForBridge(timeoutMs = 30000): Promise<VfxBridge> {
  const started = Date.now();
  return new Promise((resolve, reject) => {
    const tick = () => {
      if (window.vfxBridge) {
        resolve(window.vfxBridge);
        return;
      }
      if (Date.now() - started > timeoutMs) {
        reject(new Error("Timed out waiting for Godot vfxBridge"));
        return;
      }
      window.requestAnimationFrame(tick);
    };
    tick();
  });
}

export async function loadGodotEngine(
  canvas: HTMLCanvasElement,
  onProgress?: (ratio: number) => void,
): Promise<Engine> {
  const basePath = `${import.meta.env.BASE_URL}godot`.replace(/\/{2,}/g, "/");
  const executable = "index";
  const scriptUrl = `${basePath}/${executable}.js`;
  const wasmUrl = `${basePath}/${executable}.wasm`;
  const pckUrl = `${basePath}/${executable}.pck`;

  const probe = await fetch(scriptUrl, { method: "HEAD" });
  if (!probe.ok) {
    throw new Error("Godot web export is missing. Run tools/export-web.ps1 first.");
  }

  await loadScript(scriptUrl);
  if (typeof window.Engine === "undefined") {
    throw new Error("Godot Engine global was not created.");
  }

  const [wasmSize, pckSize] = await Promise.all([getFileSize(wasmUrl), getFileSize(pckUrl)]);
  const engine = new window.Engine({
    args: [],
    canvas,
    canvasResizePolicy: 2,
    ensureCrossOriginIsolationHeaders: false,
    executable,
    experimentalVK: false,
    fileSizes: {
      [`${executable}.pck`]: pckSize,
      [`${executable}.wasm`]: wasmSize,
    },
    focusCanvas: true,
    gdextensionLibs: [],
    serviceWorker: false,
  });

  await engine.startGame({
    onProgress: (current, total) => {
      if (total > 0) {
        onProgress?.(current / total);
      }
    },
  });

  return engine;
}
