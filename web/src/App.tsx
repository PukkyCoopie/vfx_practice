import { useEffect, useRef, useState } from "react";
import { RiMenuFoldLine, RiMenuUnfoldLine } from "@remixicon/react";
import { ThumbnailBar } from "./components/ThumbnailBar";
import { effects } from "./catalog";
import { loadGodotEngine, syncCanvasSize, waitForBridge } from "./godot/loadGodot";

const defaultId = effects[0]?.id ?? "player";

export function App() {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const queuedId = useRef<string | null>(null);
  const [activeId, setActiveId] = useState(defaultId);
  const [status, setStatus] = useState("Loading Godot export…");
  const [ready, setReady] = useState(false);
  const [failed, setFailed] = useState(false);
  const [progress, setProgress] = useState(0);
  const [galleryOpen, setGalleryOpen] = useState(true);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) {
      return;
    }

    const parent = canvas.parentElement;
    const resize = () => syncCanvasSize(canvas);
    resize();
    const observer = parent ? new ResizeObserver(resize) : null;
    observer?.observe(parent ?? canvas);
    window.addEventListener("resize", resize);

    let cancelled = false;
    loadGodotEngine(canvas, (ratio) => {
      if (!cancelled) {
        const clamped = Math.min(1, Math.max(0, ratio));
        setProgress(clamped);
        setStatus(`Loading… ${Math.round(clamped * 100)}%`);
      }
    })
      .then(async () => {
        if (cancelled) {
          return;
        }
        setProgress(1);
        setStatus("Starting…");
        try {
          await waitForBridge();
        } catch {
          // Engine already started; gallery clicks still work after vfxReady.
        }
        const next = queuedId.current ?? activeId;
        window.vfxSelect?.(next);
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
      observer?.disconnect();
      window.removeEventListener("resize", resize);
    };
  }, []);

  function selectEffect(id: string) {
    setActiveId(id);
    if (window.vfxSelect) {
      window.vfxSelect(id);
      return;
    }
    queuedId.current = id;
  }

  return (
    <div className={galleryOpen ? "app is-open" : "app"}>
      <aside className="sidebar" aria-label="Effect gallery">
        <div className="sidebar-head">
          <span className="sidebar-title">Gallery</span>
          <button
            type="button"
            className="icon-btn"
            onClick={() => setGalleryOpen(false)}
            aria-label="Hide gallery"
          >
            <RiMenuFoldLine size={18} />
          </button>
        </div>
        <ThumbnailBar activeId={activeId} onSelect={selectEffect} />
      </aside>

      <section className="stage" aria-label="Godot viewport">
        {!galleryOpen && (
          <button
            type="button"
            className="icon-btn sidebar-show"
            onClick={() => setGalleryOpen(true)}
            aria-label="Show gallery"
          >
            <RiMenuUnfoldLine size={18} />
          </button>
        )}
        <canvas ref={canvasRef} id="godot-canvas" tabIndex={0} />
        {!ready && (
          <div className={failed ? "overlay is-error" : "overlay"}>
            <p>{status}</p>
            {!failed && (
              <div className="progress">
                <span style={{ width: `${Math.round(Math.min(progress, 1) * 100)}%` }} />
              </div>
            )}
          </div>
        )}
      </section>
    </div>
  );
}
