/** Primitive JSON boundary: upstream TypeScript never imports application ArkTS. */
export interface LightSourceHost {
  keepWebSession?: boolean;
  release?(): void;
  acquireWeb?(): Promise<number>;
  releaseWeb?(lease: number): void;
  evaluate(script: string, sourceUrl: string, timingId?: number): Promise<string>;
  evaluateNative?(script: string, sourceUrl: string, timeoutMs: number): Promise<string>;
  toast?(message: string): void;
  refreshExplore?(sourceUrl: string): Promise<void>;
  openBrowser?(sourceUrl: string, sourceName: string, address: string): Promise<void>;
  cancelBrowser?(sourceUrl: string): void;
  hydrate(url: string): Promise<string>;
  getSource(url: string): Promise<string>;
  listSources(): Promise<string>;
  readState(url: string): Promise<string>;
  writeState(url: string, state: string): Promise<void>;
  saveCookies(sourceUrl: string, origin: string, cookies: string): Promise<void>;
  fetch(source: string, address: string, sniff: boolean): Promise<string>;
  browse?(sourceUrl: string, sourceName: string, address: string, html: string, injectJs: string): Promise<string>;
}
export class LightLocalSource {
  keepWebSession: boolean = false;
  bookSourceUrl: string = '';
  variable: string = '';
  rawSourceJson: string = '';
  definition: string = '';
  engine: string = '';
  enabledExplore: boolean = false;
}
