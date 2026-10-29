/** Persisted tab IDs: 0 home, 1 shelf, 2 history, 3 profile. Podcasts use their own route. */
export class MainTabPolicy {
  static order(historyEnabled: boolean): number[] { return historyEnabled ? [0, 1, 2, 3] : [0, 1, 3]; }
  static physical(logical: number, historyEnabled: boolean): number {
    return Math.max(0, MainTabPolicy.order(historyEnabled).indexOf(logical));
  }
  static logical(physical: number, historyEnabled: boolean): number {
    return MainTabPolicy.order(historyEnabled)[physical] ?? 0;
  }
}
