/// <reference types="vite/client" />

interface VfxBridge {
  select(effectId: string): void;
  pause(): void;
  play(): void;
  setSpeed(scale: number): void;
  restart(): void;
}

interface EngineConfig {
  args?: string[];
  canvas?: HTMLCanvasElement;
  canvasResizePolicy?: number;
  ensureCrossOriginIsolationHeaders?: boolean;
  executable?: string;
  experimentalVK?: boolean;
  fileSizes?: Record<string, number>;
  focusCanvas?: boolean;
  gdextensionLibs?: string[];
  mainPack?: string;
  serviceWorker?: boolean | string;
}

declare class Engine {
  constructor(config: EngineConfig);
  startGame(opts?: {
    executable?: string;
    mainPack?: string;
    onProgress?: (current: number, total: number) => void;
  }): Promise<void>;
}

interface Window {
  Engine?: typeof Engine;
  vfxBridge?: VfxBridge;
}
