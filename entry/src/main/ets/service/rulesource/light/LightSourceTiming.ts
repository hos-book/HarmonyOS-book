/** Numeric correlation only: never log source URLs, script bodies, headers or content. */
export class LightSourceTiming {
  private static serial: number = 0;
  private static contexts = new WeakMap<Object, number>();
  private static observers = new Map<number, (stage: string, detail: string) => void>();
  static next(): number { return ++this.serial; }
  static observe(id: number, observer: (stage: string, detail: string) => void): void {
    if (id > 0) this.observers.set(id, observer);
  }
  static close(id: number): void { this.observers.delete(id); }
  static bind(target: Object, id: number): void { if (id > 0) this.contexts.set(target, id); }
  static id(target: Object | null | undefined): number { return target ? this.contexts.get(target) || 0 : 0; }
  static copy(source: Object, target: Object): void { this.bind(target, this.id(source)); }
  static end(id: number, stage: string, startedAt: number, detail: string = ''): void {
    if (id <= 0) return;
    const message = `id=${id}; elapsedMs=${Math.max(0, Date.now() - startedAt)}; ${detail}`;
    this.observers.get(id)?.(stage, message);
    console.info(`[LightTiming] stage=${stage} ${message}`);
  }
}
