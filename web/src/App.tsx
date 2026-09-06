import { useEffect, useRef, useState } from "react";
import { ThumbnailBar } from "./components/ThumbnailBar";
import { effects } from "./catalog";
import { loadGodotEngine, waitForBridge } from "./godot/loadGodot";

const defaultId = effects[0]?.id ?? "studio";

export function App() {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const queuedId = useRef<string | null>(null);
  const started = useRef(false);
  const [activeId, setActiveId] = useState(defaultId);
  const [status, setStatus] = useState("Loading Godot export…");
  const [ready, setReady] = useState(false);
  const [failed, setFailed] = useState(false);
  const [progress, setProgress] = useState(0);
  const [galleryOpen, setGalleryOpen] = useState(true);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || started.current) {
      return;
    }
    started.current = true;
    let cancelled = false;

    loadGodotEngine(canvas, (ratio) => {
      if (!cancelled) {
        setProgress(ratio);
        setStatus(`Loading Godot export… ${Math.round(ratio * 100)}%`);
      }
    })
      .then(() => waitForBridge())
      .then((bridge) => {
        if (cancelled) {
          return;
        }
        const next = queuedId.current ?? activeId;
        bridge.select(next);
        setActiveId(next);
        setReady(true);
        setStatus("");
      })
      .catch((error: Error) => {
        if (cancelled) {
          return;
        }
        setFailed(true);
        setStatus(error.message);
      });

    return () => {
      cancelled = true;
    };
  }, []);

  function selectEffect(id: string) {
    setActiveId(id);
    if (window.vfxBridge) {
      window.vfxBridge.select(id);
      return;
    }
    queuedId.current = id;
  }

  return (
    <div className="app">
      <section className="stage" aria-label="Godot viewport">
        <canvas ref={canvasRef} id="godot-canvas" tabIndex={0} />
        {!ready && (
          <div className={failed ? "overlay is-error" : "overlay"}>
            <p>{status}</p>
            {!failed && (
              <div className="progress">
                <span style={{ width: `${Math.round(progress * 100)}%` }} />
              </div>
            )}
          </div>
        )}
      </section>

      <aside className={galleryOpen ? "dock is-open" : "dock"}>
        <button
          type="button"
          className="dock-toggle"
          onClick={() => setGalleryOpen((open) => !open)}
          aria-expanded={galleryOpen}
        >
          {galleryOpen ? "Hide Gallery" : "Show Gallery"}
        </button>
        <div className="dock-panel">
          <ThumbnailBar activeId={activeId} onSelect={selectEffect} />
        </div>
      </aside>
    </div>
  );
}
