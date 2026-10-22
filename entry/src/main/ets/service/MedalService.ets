import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { emitter } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { MEDALS, MedalAward, MedalDefinition, MedalSnapshot, MedalAccountStore } from '../model/Medal';
import { StatsService, EVT_USAGE_STATS_UPDATED } from './StatsService';

const ACCOUNT_STORE_KEY: string = 'medal_accounts_v2';

/** 系统核验账号独立保存成就；记录只提供增量，清理记录不收回成就。 */
@ObservedV2
export class MedalService {
  private static singleton: MedalService | null = null;
  static get instance(): MedalService {
    if (MedalService.singleton === null) MedalService.singleton = new MedalService();
    return MedalService.singleton;
  }

  @Trace ready: boolean = false;
  @Trace failed: boolean = false;
  @Trace totalSeconds: number = 0;
  @Trace selectedMedalId: string = '';
  @Trace awards: MedalAward[] = [];
  @Trace newAwardCount: number = 0;
  @Trace accountId: string = '';
  private database: MedalAccountStore = new MedalAccountStore();
  private generation: number = 0;
  private requestedAccount: string = '';
  private store: preferences.Preferences | undefined = undefined;
  private state: MedalSnapshot = new MedalSnapshot();
  private initPromise: Promise<void> | undefined = undefined;
  private queue: Promise<void> = Promise.resolve();
  private listening: boolean = false;
  private pendingAwards: MedalAward[] = [];
  private pendingSnapshot: MedalSnapshot | undefined = undefined;
  private onStatsUpdated = (event: emitter.EventData): void => {
    // 事件发出时立即取缓存：删除记录排在后面时，也不会丢掉刚达标的勋章。
    this.refreshUnlocks(event.data?.historical === true, event.data?.restored === true).catch((error: Error): void => {
      this.failed = true;
      console.warn(`[MedalService] unlock failed: ${error.message}`);
    });
  };

  async init(context: common.Context): Promise<void> {
    if (this.initPromise === undefined) {
      this.initPromise = this.initialize(context).catch((error: Error): void => {
        this.failed = true;
        this.initPromise = undefined;
        throw error;
      });
    }
    await this.initPromise;
  }

  private async initialize(context: common.Context): Promise<void> {
    await StatsService.init(context);
    this.store = await preferences.getPreferences(context, { name: 'listenbook_medals' });
    const raw = await this.store.get(ACCOUNT_STORE_KEY, '');
    if (typeof raw !== 'string') throw new Error('Invalid medal storage');
    if (raw.length > 0) {
      const saved: MedalAccountStore = JSON.parse(raw);
      if (!MedalService.validAccountStore(saved)) throw new Error('Invalid medal accounts');
      this.database = MedalService.copyDatabase(saved);
    } else {
      const legacy = await this.store.get('medal_state_v1', '');
      if (typeof legacy !== 'string') throw new Error('Invalid medal storage');
      const saved: MedalSnapshot = legacy.length > 0 ? JSON.parse(legacy) : new MedalSnapshot();
      if (!MedalService.isValidSnapshot(saved)) throw new Error('Invalid medal snapshot');
      const guest = MedalService.copy(saved);
      guest.ownerKey = '';
      guest.earnedSeconds = Math.max(guest.earnedSeconds, this.currentStats());
      guest.statsBaseline = this.currentStats();
      this.database = new MedalAccountStore();
      this.database.profiles.push(guest);
    }
    this.state = MedalService.copy(this.database.profiles.find((item: MedalSnapshot): boolean => item.ownerKey === '') ??
      new MedalSnapshot());
    this.publish();
    if (!this.listening) {
      emitter.on(EVT_USAGE_STATS_UPDATED, this.onStatsUpdated);
      this.listening = true;
    }
    await this.refreshUnlocks(true);
    this.ready = this.requestedAccount.length === 0;
    this.failed = false;
  }

  /** 由 AuthService 在 Account Kit 核验成功后绑定。 */
  async bindAccount(context: common.Context, accountId: string): Promise<void> {
    if (!accountId) throw new Error('Missing medal account');
    if (this.ready && this.accountId === accountId && this.requestedAccount === accountId) return;
    this.requestedAccount = accountId;
    this.ready = false;
    const generation = ++this.generation;
    await this.init(context);
    const digest = cryptoFramework.createMd('SHA256');
    await digest.update({ data: new util.TextEncoder().encodeInto(accountId) });
    const result = await digest.digest();
    let ownerKey = '';
    for (const byte of result.data) ownerKey += byte.toString(16).padStart(2, '0');
    await this.enqueue(async (): Promise<void> => {
      if (generation !== this.generation) return;
      if (this.pendingSnapshot !== undefined) {
        await this.save(this.pendingSnapshot, MedalService.copyDatabase(this.database), generation);
        this.pendingSnapshot = undefined;
      }
      const seconds = this.currentStats();
      const saved = this.database.profiles.find((item: MedalSnapshot): boolean => item.ownerKey === ownerKey);
      let next = saved === undefined ? new MedalSnapshot() : MedalService.copy(saved);
      const db = MedalService.copyDatabase(this.database);
      if (!db.legacyClaimed) {
        const guest = db.profiles.find((item: MedalSnapshot): boolean => item.ownerKey === '');
        if (guest !== undefined) next = MedalService.copy(guest);
        next.earnedSeconds = Math.max(next.earnedSeconds, seconds);
        db.legacyClaimed = true;
      } else if (saved !== undefined && db.lastOwnerKey === ownerKey) {
        next.earnedSeconds += Math.max(0, seconds - next.statsBaseline);
      }
      next.ownerKey = ownerKey;
      next.statsBaseline = seconds;
      this.addAwards(next, true);
      db.lastOwnerKey = ownerKey;
      await this.save(next, db, generation);
      if (generation !== this.generation) return;
      this.accountId = accountId;
      this.pendingAwards = [];
      this.ready = true;
      this.failed = false;
      this.newAwardCount = 0;
    });
  }

  clearAccount(): Promise<void> {
    this.requestedAccount = '';
    this.accountId = '';
    this.ready = false;
    this.totalSeconds = 0;
    this.awards = [];
    this.selectedMedalId = '';
    this.newAwardCount = 0;
    this.pendingAwards = [];
    const generation = ++this.generation;
    // init 在自身队列内处理统计；不能在此队列中反向等待 init，以免互等。
    const initialized = this.initPromise ?? Promise.resolve();
    return initialized.then((): Promise<void> => this.enqueue(async (): Promise<void> => {
      if (!this.store || generation !== this.generation) return;
      if (this.pendingSnapshot !== undefined) {
        await this.save(this.pendingSnapshot, MedalService.copyDatabase(this.database), generation);
        this.pendingSnapshot = undefined;
      }
      const next = MedalService.copy(this.database.profiles.find((item: MedalSnapshot): boolean => item.ownerKey === '') ??
        new MedalSnapshot());
      next.statsBaseline = this.currentStats();
      const db = MedalService.copyDatabase(this.database);
      db.lastOwnerKey = '';
      await this.save(next, db, generation);
      if (generation === this.generation) this.ready = true;
    })).catch((): void => { this.failed = true; });
  }

  private currentStats(): number {
    const stats = StatsService.getCachedStatsBundle(1);
    if (stats === undefined) throw new Error('Listening statistics unavailable');
    return stats.summary.totalSeconds;
  }

  private enqueue(action: () => Promise<void>): Promise<void> {
    const task = this.queue.then(action);
    this.queue = task.catch((): void => {});
    return task;
  }

  refreshUnlocks(historical: boolean = false, restored: boolean = false): Promise<void> {
    const stats = StatsService.getCachedStatsBundle(1);
    if (stats === undefined) return Promise.reject(new Error('Listening statistics unavailable'));
    const seconds = stats.summary.totalSeconds;
    const generation = this.generation;
    return this.enqueue(async (): Promise<void> => {
      if (generation !== this.generation || !this.store || this.state.ownerKey !== this.database.lastOwnerKey ||
        this.requestedAccount !== this.accountId) return;
      const next = MedalService.copy(this.pendingSnapshot ?? this.state);
      for (const pending of this.pendingAwards) {
        if (!next.awards.some((award: MedalAward): boolean => award.medalId === pending.medalId)) {
          next.awards.push(pending);
        }
      }
      if (!restored) next.earnedSeconds += Math.max(0, seconds - next.statsBaseline);
      next.statsBaseline = seconds;
      const added = this.addAwards(next, historical);
      if (JSON.stringify(next) !== JSON.stringify(this.state) || this.failed || this.pendingAwards.length > 0) {
        this.pendingAwards = next.awards.slice();
        this.pendingSnapshot = MedalService.copy(next);
        await this.save(next);
        this.pendingAwards = [];
        this.pendingSnapshot = undefined;
      }
      if (generation !== this.generation) return;
      this.publish();
      if (!historical) this.newAwardCount += added;
      this.failed = false;
    });
  }

  private addAwards(next: MedalSnapshot, historical: boolean): number {
    let added: number = 0;
    for (const medal of MEDALS) {
      if (next.earnedSeconds >= medal.hours * 3600 && !next.awards.some((award: MedalAward): boolean => award.medalId === medal.id)) {
        next.awards.push(new MedalAward(medal.id, historical ? 0 : Date.now(), historical));
        added++;
      }
    }
    return added;
  }

  isUnlocked(id: string): boolean {
    return this.awards.some((award: MedalAward): boolean => award.medalId === id);
  }

  /** 等级取永久保存的已获勋章，清理记录或时长不降级。 */
  usageLevel(): number {
    let level: number = 1;
    for (let index: number = 0; index < MEDALS.length; index++) {
      if (this.isUnlocked(MEDALS[index].id)) {
        level = index + 1;
      }
    }
    return level;
  }

  usageLevelName(): Resource {
    return MEDALS[this.usageLevel() - 1].name;
  }

  selected(): MedalDefinition | undefined {
    return MEDALS.find((medal: MedalDefinition): boolean => medal.id === this.selectedMedalId);
  }

  equipMedal(id: string): Promise<void> {
    const generation = this.generation;
    return this.enqueue(async (): Promise<void> => {
      if (generation !== this.generation || !this.ready || (id !== '' && !this.isUnlocked(id))) throw new Error('Medal is locked');
      const next = MedalService.copy(this.state);
      next.selectedMedalId = id;
      await this.save(next);
    });
  }

  private async save(next: MedalSnapshot, db: MedalAccountStore = MedalService.copyDatabase(this.database),
    generation: number = this.generation): Promise<void> {
    const store = this.store;
    if (store === undefined) throw new Error('MedalService not initialized');
    db.profiles = db.profiles.filter((item: MedalSnapshot): boolean => item.ownerKey !== next.ownerKey);
    db.profiles.push(MedalService.copy(next));
    try {
      await store.put(ACCOUNT_STORE_KEY, JSON.stringify(db));
      await store.flush();
    } catch (error) {
      this.failed = true;
      // 回滚 Preferences 内存缓存，失败的佩戴操作不能被后续 flush 意外提交。
      try { await store.put(ACCOUNT_STORE_KEY, JSON.stringify(this.database)); } catch (_error) { /* 保留原始错误 */ }
      throw new Error(String(error));
    }
    this.database = db;
    if (generation !== this.generation) return;
    this.state = MedalService.copy(next);
    this.publish();
  }

  private publish(): void {
    this.totalSeconds = this.state.earnedSeconds;
    // 历史款仅保留备份记录，不参与展示、数量统计或佩戴。
    this.awards = this.state.awards.filter((award: MedalAward): boolean =>
      MEDALS.some((medal: MedalDefinition): boolean => medal.id === award.medalId));
    this.selectedMedalId = this.state.selectedMedalId;
  }

  async exportSnapshot(context: common.Context, totalSeconds: number): Promise<MedalSnapshot> {
    await this.queue;
    let saved: MedalSnapshot = this.state;
    if (this.store === undefined) {
      // 备份使用已经清洗的统计副本，不强制初始化原始统计，避免一条旧记录损坏阻断备份。
      const store = await preferences.getPreferences(context, { name: 'listenbook_medals' });
      const accounts = await store.get(ACCOUNT_STORE_KEY, '');
      if (typeof accounts !== 'string') throw new Error('Invalid medal storage');
      if (accounts.length > 0) return new MedalSnapshot();
      const raw = await store.get('medal_state_v1', '');
      if (typeof raw !== 'string') throw new Error('Invalid medal storage');
      saved = raw.length > 0 ? JSON.parse(raw) : new MedalSnapshot();
      if (!MedalService.isValidSnapshot(saved)) throw new Error('Invalid medal snapshot');
    }
    const snapshot = MedalService.copy(saved);
    if (this.store === undefined) {
      snapshot.earnedSeconds = Math.max(snapshot.earnedSeconds, totalSeconds);
      this.addAwards(snapshot, true);
    }
    snapshot.statsBaseline = 0;
    return snapshot;
  }

  async restoreSnapshot(context: common.Context, saved: MedalSnapshot | undefined): Promise<void> {
    if (saved !== undefined && !MedalService.isValidSnapshot(saved)) throw new Error('Invalid medal backup');
    await this.init(context);
    const generation = this.generation;
    await this.enqueue(async (): Promise<void> => {
      if (generation !== this.generation) throw new Error('Medal account changed');
      const next = MedalService.copy(this.state);
      if (saved !== undefined && (saved.ownerKey ?? '') === next.ownerKey) {
        for (const award of saved.awards) {
          const existing = next.awards.find((item: MedalAward): boolean => item.medalId === award.medalId);
          if (existing === undefined) next.awards.push(new MedalAward(award.medalId, award.unlockedAt, award.historical));
          else if (existing.historical && !award.historical) {
            existing.unlockedAt = award.unlockedAt;
            existing.historical = false;
          }
        }
        next.selectedMedalId = saved.selectedMedalId;
        next.earnedSeconds = Math.max(next.earnedSeconds, saved.earnedSeconds ?? 0);
        this.addAwards(next, true);
      }
      next.statsBaseline = this.currentStats();
      await this.save(next);
    });
  }

  async flush(): Promise<void> {
    await this.queue;
    if (this.ready && this.failed) await this.refreshUnlocks();
  }

  private static copy(value: MedalSnapshot): MedalSnapshot {
    const copy = new MedalSnapshot();
    copy.ownerKey = value.ownerKey ?? '';
    copy.earnedSeconds = value.earnedSeconds ?? 0;
    copy.statsBaseline = value.statsBaseline ?? 0;
    copy.selectedMedalId = MEDALS.some((medal: MedalDefinition): boolean => medal.id === value.selectedMedalId) ?
      value.selectedMedalId : '';
    copy.awards = value.awards.map((award: MedalAward): MedalAward =>
      new MedalAward(award.medalId, award.unlockedAt, award.historical));
    for (const medal of MEDALS) {
      if (copy.awards.some((award: MedalAward): boolean => award.medalId === medal.id)) {
        copy.earnedSeconds = Math.max(copy.earnedSeconds, medal.hours * 3600);
      }
    }
    return copy;
  }

  private static copyDatabase(value: MedalAccountStore): MedalAccountStore {
    const copy = new MedalAccountStore();
    copy.legacyClaimed = value.legacyClaimed;
    copy.lastOwnerKey = value.lastOwnerKey;
    copy.profiles = value.profiles.map((item: MedalSnapshot): MedalSnapshot => MedalService.copy(item));
    return copy;
  }

  private static validAccountStore(value: MedalAccountStore): boolean {
    if (!value || value.version !== 2 || typeof value.legacyClaimed !== 'boolean' ||
      typeof value.lastOwnerKey !== 'string' || !Array.isArray(value.profiles)) return false;
    const owners = new Set<string>();
    for (const item of value.profiles) {
      if (!MedalService.isValidSnapshot(item) || typeof item.ownerKey !== 'string' || owners.has(item.ownerKey)) return false;
      owners.add(item.ownerKey);
    }
    return value.lastOwnerKey === '' || owners.has(value.lastOwnerKey);
  }

  static isValidSnapshot(value: MedalSnapshot): boolean {
    if (!value || value.version !== 1 || typeof value.selectedMedalId !== 'string' ||
      !Array.isArray(value.awards) || value.awards.length > MEDALS.length + 2) return false;
    if (value.ownerKey !== undefined && (typeof value.ownerKey !== 'string' ||
      (value.ownerKey !== '' && !/^[a-f0-9]{64}$/.test(value.ownerKey)))) return false;
    if (value.earnedSeconds !== undefined && (!Number.isFinite(value.earnedSeconds) || value.earnedSeconds < 0)) return false;
    if (value.statsBaseline !== undefined && (!Number.isFinite(value.statsBaseline) || value.statsBaseline < 0)) return false;
    const seen = new Set<string>();
    for (const award of value.awards) {
      if (!award || (!MEDALS.some((medal: MedalDefinition): boolean => medal.id === award.medalId) &&
        award.medalId !== 'national_day' && award.medalId !== 'reading_3000h') ||
        seen.has(award.medalId) || !Number.isSafeInteger(award.unlockedAt) || award.unlockedAt < 0 ||
        typeof award.historical !== 'boolean' || (!award.historical && award.unlockedAt === 0)) return false;
      seen.add(award.medalId);
    }
    return value.selectedMedalId === '' || seen.has(value.selectedMedalId);
  }
}
