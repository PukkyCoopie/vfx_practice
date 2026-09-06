/// <reference types="vite/client" />

interface VfxBridgeApi {
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
  onProgress?: (current: number, total: number) => void;
  onPrintError?: (text: string) => void;
}

declare class Engine {
  constructor(config: EngineConfig);
  init(basePath?: string): Promise<void>;
  preloadFile(file: string, path?: string): Promise<void>;
  start(opts?: EngineConfig): Promise<void>;
  startGame(opts?: EngineConfig): Promise<void>;
}

interface Window {
  Engine?: typeof Engine;
  vfxReady?: boolean;
  vfxSelect?: (effectId: string) => void;
  vfxPause?: () => void;
  vfxPlay?: () => void;
  vfxSetSpeed?: (scale: number) => void;
  vfxRestart?: () => void;
  vfxBridge?: VfxBridgeApi;
}
