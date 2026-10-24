import { common } from '@kit.AbilityKit';
import { buffer } from '@kit.ArkTS';
import { relationalStore } from '@kit.ArkData';
import {
  LocalRuleSource,
  LocalRuleSourceCookie,
  LocalRuleSourceImportReport,
  LocalRuleSourceSession,
  LocalRuleSourceStatus
} from '../../model/LocalRuleSource';
import { LocalRuleSourceImportParser } from './LocalRuleSourceImportParser';
import { LocalRuleSourceCodec } from './LocalRuleSourceCodec';

const DATABASE_NAME = 'rule_sources.db';
const TABLE_NAME = 'rule_sources';
const SESSION_TABLE_NAME = 'rule_source_sessions';
const COOKIE_TABLE_NAME = 'rule_source_cookies';
const LOGIN_TABLE_NAME = 'rule_source_login_status';
const STATE_TABLE_NAME = 'rule_source_script_state';
const GROUP_TABLE_NAME = 'rule_source_groups';
const MAX_SOURCE_JSON_BYTES = 25 * 1024 * 1024;
const MAX_SCRIPT_STATE_BYTES = 512 * 1024;
const MAX_SESSION_TOKEN_LENGTH = 4096;
const MAX_SESSION_DEVICE_ID_LENGTH = 256;
const MAX_COOKIE_HEADER_LENGTH = 64 * 1024;
const BATCH_PREDICATE_LIMIT = 400;

const CREATE_TABLE_SQL = `CREATE TABLE IF NOT EXISTS ${TABLE_NAME} (
  source_url TEXT PRIMARY KEY NOT NULL,
  source_name TEXT NOT NULL,
  source_type INTEGER NOT NULL DEFAULT 0,
  source_group TEXT NOT NULL DEFAULT '',
  source_json TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1,
  enabled_explore INTEGER NOT NULL DEFAULT 0,
  is_locked INTEGER NOT NULL DEFAULT 0,
  is_pinned INTEGER NOT NULL DEFAULT 0,
  custom_order INTEGER NOT NULL DEFAULT 0,
  validation_status INTEGER NOT NULL DEFAULT 0,
  validation_message TEXT NOT NULL DEFAULT '',
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)`;

// 不建级联外键：书源 upsert 使用 REPLACE，同 URL 重导不能连带删除既有会话。
const CREATE_SESSION_TABLE_SQL = `CREATE TABLE IF NOT EXISTS ${SESSION_TABLE_NAME} (
  source_url TEXT PRIMARY KEY NOT NULL,
  token TEXT NOT NULL,
  device_id TEXT NOT NULL,
  account_label TEXT NOT NULL DEFAULT '',
  updated_at INTEGER NOT NULL
)`;

const CREATE_COOKIE_TABLE_SQL = `CREATE TABLE IF NOT EXISTS ${COOKIE_TABLE_NAME} (
  source_url TEXT NOT NULL,
  origin TEXT NOT NULL,
  cookie_header TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (source_url, origin)
)`;

const SELECT_COLUMNS = 'source_url, source_name, source_type, source_group, source_json, ' +
  'enabled, validation_status, validation_message, enabled_explore, is_locked, is_pinned, custom_order, created_at';
const LIST_SQL = `SELECT ${SELECT_COLUMNS} FROM ${TABLE_NAME} ` +
  'ORDER BY is_pinned DESC, custom_order ASC, sort_order DESC, source_name COLLATE NOCASE ASC';
const GET_SQL = `SELECT ${SELECT_COLUMNS} FROM ${TABLE_NAME} WHERE source_url = ? LIMIT 1`;
const SESSION_SELECT_COLUMNS = 'source_url, token, device_id, account_label, updated_at';
const GET_SESSION_SQL = `SELECT ${SESSION_SELECT_COLUMNS} FROM ${SESSION_TABLE_NAME} ` +
  'WHERE source_url = ? LIMIT 1';
const COOKIE_SELECT_COLUMNS = 'source_url, origin, cookie_header, updated_at';
const LIST_COOKIES_SQL = `SELECT ${COOKIE_SELECT_COLUMNS} FROM ${COOKIE_TABLE_NAME} ` +
  'WHERE source_url = ? ORDER BY updated_at DESC';

class PreparedRuleSource {
  source: LocalRuleSource = new LocalRuleSource();
  sourceJson: string = '';

  constructor(source: LocalRuleSource, sourceJson: string) {
    this.source = source;
    this.sourceJson = sourceJson;
  }
}

/** 本地规则书源持久化；错误交由上层提示，不删除或重建损坏数据库。 */
export class LocalRuleSourceRepository {
  private static store: relationalStore.RdbStore | null = null;
  private static initPromise: Promise<void> | null = null;

  static isInitialized(): boolean {
    return LocalRuleSourceRepository.store !== null;
  }

  private static loginRevision: number = 0;

  static getLoginRevision(): number { return LocalRuleSourceRepository.loginRevision; }

  static async getLoginStatus(sourceUrl: string): Promise<string> {
    const store = await LocalRuleSourceRepository.ensureStore();
    const rows = await store.querySql(`SELECT status FROM ${LOGIN_TABLE_NAME} WHERE source_url = ?`, [sourceUrl]);
    try { return rows.goToFirstRow() ? rows.getString(0) : ''; }
    finally { rows.close(); }
  }

  static async listLoginStatuses(): Promise<Map<string, string>> {
    const store = await LocalRuleSourceRepository.ensureStore();
    const rows = await store.querySql(`SELECT source_url, status FROM ${LOGIN_TABLE_NAME}`);
    const result = new Map<string, string>();
    try {
      while (rows.goToNextRow()) result.set(rows.getString(0), rows.getString(1));
    } finally { rows.close(); }
    return result;
  }

  static async setLoginStatus(sourceUrl: string, status: string): Promise<void> {
    const store = await LocalRuleSourceRepository.ensureStore();
    const values: relationalStore.ValuesBucket = {
      source_url: LocalRuleSourceRepository.requireSourceUrl(sourceUrl),
      status: status, updated_at: Date.now()
    };
    await store.insert(LOGIN_TABLE_NAME, values, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
    LocalRuleSourceRepository.loginRevision++;
  }

  static async expireLogin(sourceUrl: string): Promise<void> {
    const previous = await LocalRuleSourceRepository.getLoginStatus(sourceUrl);
    if (previous !== 'expired' && previous !== 'signedOut') {
      await LocalRuleSourceRepository.setLoginStatus(sourceUrl, 'expired');
    }
  }

  static async readScriptState(sourceUrl: string): Promise<string> {
    const store = await LocalRuleSourceRepository.ensureStore();
    const args: relationalStore.ValueType[] = [sourceUrl];
    const rows = await store.querySql(`SELECT state_json FROM ${STATE_TABLE_NAME} WHERE source_url = ?`, args);
    try {
      return rows.goToFirstRow() ? rows.getString(0) : '';
    } finally {
      rows.close();
    }
  }

  static async writeScriptState(sourceUrl: string, stateJson: string): Promise<void> {
    if (buffer.byteLength(stateJson, 'utf-8') > MAX_SCRIPT_STATE_BYTES) {
      throw new Error('书源运行状态超过 512 KiB');
    }
    const store = await LocalRuleSourceRepository.ensureStore();
    const args: relationalStore.ValueType[] = [sourceUrl, stateJson, sourceUrl];
    await store.execute(`INSERT OR REPLACE INTO ${STATE_TABLE_NAME} (source_url, state_json) ` +
      `SELECT ?, ? WHERE EXISTS (SELECT 1 FROM ${TABLE_NAME} WHERE source_url = ?)`, args);
  }

  static async init(context: common.BaseContext): Promise<void> {
    if (LocalRuleSourceRepository.store !== null) return;
    if (LocalRuleSourceRepository.initPromise !== null) {
      await LocalRuleSourceRepository.initPromise;
      return;
    }

    const pending = LocalRuleSourceRepository.open(context);
    LocalRuleSourceRepository.initPromise = pending;
    try {
      await pending;
    } catch (error) {
      if (LocalRuleSourceRepository.initPromise === pending) {
        LocalRuleSourceRepository.initPromise = null;
      }
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
  }

  static async list(): Promise<LocalRuleSource[]> {
    const store = await LocalRuleSourceRepository.ensureStore();
    let resultSet: relationalStore.ResultSet | null = null;
    const sources: LocalRuleSource[] = [];
    try {
      resultSet = await store.querySql(LIST_SQL);
      while (resultSet.goToNextRow()) {
        sources.push(LocalRuleSourceRepository.readSource(resultSet));
      }
      return sources;
    } finally {
      if (resultSet !== null) resultSet.close();
    }
  }

  static async getAll(): Promise<LocalRuleSource[]> {
    return LocalRuleSourceRepository.list();
  }

  static async getEnabled(): Promise<LocalRuleSource[]> {
    const sources = await LocalRuleSourceRepository.list();
    return sources.filter((source: LocalRuleSource): boolean => source.isSearchEnabled());
  }

  static async get(sourceUrl: string): Promise<LocalRuleSource | undefined> {
    const normalizedUrl = sourceUrl.trim();
    if (normalizedUrl.length === 0) return undefined;

    const store = await LocalRuleSourceRepository.ensureStore();
    let resultSet: relationalStore.ResultSet | null = null;
    const args: relationalStore.ValueType[] = [normalizedUrl];
    try {
      resultSet = await store.querySql(GET_SQL, args);
      if (!resultSet.goToFirstRow()) return undefined;
      return LocalRuleSourceRepository.readSource(resultSet);
    } finally {
      if (resultSet !== null) resultSet.close();
    }
  }

  static async getByUrl(sourceUrl: string): Promise<LocalRuleSource | undefined> {
    return LocalRuleSourceRepository.get(sourceUrl);
  }

  static async findByUrl(sourceUrl: string): Promise<LocalRuleSource | undefined> {
    return LocalRuleSourceRepository.get(sourceUrl);
  }

  static async insert(source: LocalRuleSource): Promise<void> {
    await LocalRuleSourceRepository.upsert(source);
  }

  static async update(source: LocalRuleSource): Promise<void> {
    await LocalRuleSourceRepository.upsert(source);
  }

  static async getSession(sourceUrl: string): Promise<LocalRuleSourceSession | undefined> {
    const normalizedUrl = LocalRuleSourceRepository.requireSourceUrl(sourceUrl);
    const store = await LocalRuleSourceRepository.ensureStore();
    let resultSet: relationalStore.ResultSet | null = null;
    const args: relationalStore.ValueType[] = [normalizedUrl];
    try {
      resultSet = await store.querySql(GET_SESSION_SQL, args);
      if (!resultSet.goToFirstRow()) return undefined;
      const session = new LocalRuleSourceSession();
      session.sourceUrl = resultSet.getString(0);
      session.token = LocalRuleSourceRepository.requireSessionToken(resultSet.getString(1));
      session.deviceId = LocalRuleSourceRepository.requireSessionValue(
        'deviceId', resultSet.getString(2), MAX_SESSION_DEVICE_ID_LENGTH);
      session.accountLabel = resultSet.getString(3);
      session.updatedAt = resultSet.getLong(4);
      return session;
    } finally {
      if (resultSet !== null) resultSet.close();
    }
  }

  static async saveSession(session: LocalRuleSourceSession): Promise<void> {
    const sourceUrl = LocalRuleSourceRepository.requireSourceUrl(session.sourceUrl);
    const token = LocalRuleSourceRepository.requireSessionToken(session.token);
    const deviceId = LocalRuleSourceRepository.requireSessionValue(
      'deviceId', session.deviceId, MAX_SESSION_DEVICE_ID_LENGTH);
    const source = await LocalRuleSourceRepository.get(sourceUrl);
    if (source === undefined) throw new Error(`书源不存在：${sourceUrl}`);

    const store = await LocalRuleSourceRepository.ensureStore();
    const updatedAt = Date.now();
    const values: relationalStore.ValuesBucket = {
      'source_url': sourceUrl,
      'token': token,
      'device_id': deviceId,
      'account_label': session.accountLabel,
      'updated_at': updatedAt
    };
    const rowId = await store.insert(SESSION_TABLE_NAME, values,
      relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
    if (rowId < 0) throw new Error(`书源会话写入失败：${sourceUrl}`);
    session.sourceUrl = sourceUrl;
    session.updatedAt = updatedAt;
    await LocalRuleSourceRepository.setLoginStatus(sourceUrl, token.length > 0 ? 'valid' : 'signedOut');
  }

  static async clearSession(sourceUrl: string): Promise<void> {
    const normalizedUrl = LocalRuleSourceRepository.requireSourceUrl(sourceUrl);
    const store = await LocalRuleSourceRepository.ensureStore();
    const predicates = new relationalStore.RdbPredicates(SESSION_TABLE_NAME);
    predicates.equalTo('source_url', normalizedUrl);
    await store.delete(predicates);
    await LocalRuleSourceRepository.setLoginStatus(normalizedUrl, 'signedOut');
  }

  static async listCookies(sourceUrl: string): Promise<LocalRuleSourceCookie[]> {
    const normalizedUrl = LocalRuleSourceRepository.requireSourceUrl(sourceUrl);
    const store = await LocalRuleSourceRepository.ensureStore();
    let resultSet: relationalStore.ResultSet | null = null;
    const cookies: LocalRuleSourceCookie[] = [];
    const args: relationalStore.ValueType[] = [normalizedUrl];
    try {
      resultSet = await store.querySql(LIST_COOKIES_SQL, args);
      while (resultSet.goToNextRow()) {
        const cookie = new LocalRuleSourceCookie();
        cookie.sourceUrl = resultSet.getString(0);
        cookie.origin = LocalRuleSourceRepository.requireOrigin(resultSet.getString(1));
        cookie.cookieHeader = LocalRuleSourceRepository.requireCookieHeader(resultSet.getString(2));
        cookie.updatedAt = resultSet.getLong(3);
        cookies.push(cookie);
      }
      return cookies;
    } finally {
      if (resultSet !== null) resultSet.close();
    }
  }

  static async saveCookie(cookie: LocalRuleSourceCookie): Promise<void> {
    const sourceUrl = LocalRuleSourceRepository.requireSourceUrl(cookie.sourceUrl);
    const origin = LocalRuleSourceRepository.requireOrigin(cookie.origin);
    const cookieHeader = LocalRuleSourceRepository.requireCookieHeader(cookie.cookieHeader);
    if (cookieHeader.length === 0) {
      await LocalRuleSourceRepository.clearCookie(sourceUrl, origin);
      return;
    }
    const source = await LocalRuleSourceRepository.get(sourceUrl);
    if (source === undefined) throw new Error(`书源不存在：${sourceUrl}`);

    const store = await LocalRuleSourceRepository.ensureStore();
    const updatedAt = Date.now();
    const values: relationalStore.ValuesBucket = {
      'source_url': sourceUrl,
      'origin': origin,
      'cookie_header': cookieHeader,
      'updated_at': updatedAt
    };
    const rowId = await store.insert(COOKIE_TABLE_NAME, values,
      relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
    if (rowId < 0) throw new Error(`书源 Cookie 写入失败：${sourceUrl}`);
    cookie.sourceUrl = sourceUrl;
    cookie.origin = origin;
    cookie.cookieHeader = cookieHeader;
    cookie.updatedAt = updatedAt;
  }

  static async clearCookie(sourceUrl: string, origin: string): Promise<void> {
    const normalizedUrl = LocalRuleSourceRepository.requireSourceUrl(sourceUrl);
    const normalizedOrigin = LocalRuleSourceRepository.requireOrigin(origin);
    const store = await LocalRuleSourceRepository.ensureStore();
    const predicates = new relationalStore.RdbPredicates(COOKIE_TABLE_NAME);
    predicates.equalTo('source_url', normalizedUrl);
    predicates.equalTo('origin', normalizedOrigin);
    await store.delete(predicates);
  }

  static async clearCookies(sourceUrl: string): Promise<void> {
    const normalizedUrl = LocalRuleSourceRepository.requireSourceUrl(sourceUrl);
    const store = await LocalRuleSourceRepository.ensureStore();
    const predicates = new relationalStore.RdbPredicates(COOKIE_TABLE_NAME);
    predicates.equalTo('source_url', normalizedUrl);
    await store.delete(predicates);
  }

  static async upsert(source: LocalRuleSource): Promise<void> {
    const sources: LocalRuleSource[] = [source];
    await LocalRuleSourceRepository.upsertBatch(sources);
  }

  static async upsertMany(sources: LocalRuleSource[]): Promise<void> {
    await LocalRuleSourceRepository.upsertBatch(sources);
  }

  /** 导入排在未置顶分区前面；重导保留置顶顺序和本机管理状态，跳过锁定书源。 */
  static async upsertImportedBatch(sources: LocalRuleSource[]): Promise<number> {
    return LocalRuleSourceRepository.writeBatch(sources, true);
  }

  static preserveEnabledStates(incoming: LocalRuleSource[], existing: LocalRuleSource[]): void {
    const existingByUrl = new Map<string, LocalRuleSource>();
    for (const source of existing) {
      existingByUrl.set(source.bookSourceUrl.trim(), source);
    }
    for (const source of incoming) {
      const sourceUrl = source.bookSourceUrl.trim();
      if (!source.canExecute()) {
        source.enabled = false;
      } else {
        const previous = existingByUrl.get(sourceUrl);
        if (previous !== undefined) {
          source.enabled = previous.enabled;
          source.enabledExplore = previous.enabledExplore;
          source.bookSourceGroup = previous.bookSourceGroup;
          source.isLocked = previous.isLocked;
          source.isPinned = previous.isPinned;
          source.customOrder = previous.customOrder;
        }
      }
    }
  }

  /** 全批次预校验后再写入，任意一条失败都会回滚整个批次。 */
  static async upsertBatch(sources: LocalRuleSource[]): Promise<number> {
    return LocalRuleSourceRepository.writeBatch(sources, false);
  }

  private static async writeBatch(sources: LocalRuleSource[], importing: boolean): Promise<number> {
    if (sources.length === 0) return 0;

    const prepared: PreparedRuleSource[] = [];
    for (const source of sources) {
      prepared.push(LocalRuleSourceRepository.prepare(source));
    }

    const store = await LocalRuleSourceRepository.ensureStore();
    const transaction = await store.createTransaction();
    const now = Date.now();
    let writtenCount = 0;
    try {
      const orderRows = await transaction.querySql(`SELECT MAX(custom_order), MIN(custom_order) FROM ${TABLE_NAME}`);
      let nextOrder = 0;
      let importOrder = -prepared.length;
      try {
        if (orderRows.goToFirstRow()) {
          nextOrder = orderRows.getLong(0) + 1;
          importOrder = orderRows.getLong(1) - prepared.length;
        }
      } finally {
        orderRows.close();
      }
      for (let index = 0; index < prepared.length; index++) {
        let item = prepared[index];
        const args: relationalStore.ValueType[] = [item.source.bookSourceUrl.trim()];
        const rows = await transaction.querySql(GET_SQL, args);
        let previous: LocalRuleSource | undefined = undefined;
        let createdAt = now;
        try {
          if (rows.goToFirstRow()) {
            previous = LocalRuleSourceRepository.readSource(rows);
            createdAt = rows.getLong(12);
          }
        } finally {
          rows.close();
        }
        if (previous !== undefined) {
          if (previous.isLocked) {
            if (importing) continue;
            throw new Error(`书源已锁定，请先解锁：${previous.bookSourceName}`);
          }
          if (importing) LocalRuleSourceRepository.preserveEnabledStates([item.source], [previous]);
          item.source.isLocked = previous.isLocked;
          item.source.isPinned = previous.isPinned;
          item.source.customOrder = previous.customOrder;
        } else {
          if (item.source.customOrder === 0) item.source.customOrder = nextOrder++;
        }
        if (importing && !item.source.isPinned) {
          // 忽略导入文件的普通排序值，同批次保持文件顺序，已有置顶来源原位不动。
          item.source.customOrder = importOrder++;
        }
        item = LocalRuleSourceRepository.prepare(item.source);
        const values = LocalRuleSourceRepository.toValues(item, now - index, now, createdAt);
        const rowId = await transaction.insert(TABLE_NAME, values,
          relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
        if (rowId < 0) {
          throw new Error(`书源写入失败：${item.source.bookSourceName}`);
        }
        writtenCount++;
      }
      await transaction.commit();
      return writtenCount;
    } catch (error) {
      try {
        await transaction.rollback();
      } catch (_rollbackError) {
        // 事务可能已因提交失败而关闭，保留原始写入错误。
      }
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
  }

  /** 批量测试仅更新健康状态，避免重复解析和重写整份书源 JSON。 */
  static async updateValidationBatch(sources: LocalRuleSource[]): Promise<void> {
    if (sources.length === 0) return;
    const store = await LocalRuleSourceRepository.ensureStore();
    const transaction = await store.createTransaction();
    try {
      for (const source of sources) {
        const sourceUrl = LocalRuleSourceRepository.requireSourceUrl(source.bookSourceUrl);
        const values: relationalStore.ValuesBucket = {
          'validation_status': source.validationStatus,
          'validation_message': source.validationMessage,
          'updated_at': Date.now()
        };
        const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
        predicates.equalTo('source_url', sourceUrl);
        const updated = await transaction.update(values, predicates);
        if (updated !== 1) throw new Error(`书源状态更新失败：${sourceUrl}`);
      }
      await transaction.commit();
    } catch (error) {
      try {
        await transaction.rollback();
      } catch (_rollbackError) {
        // 事务可能已关闭，保留原始状态更新错误。
      }
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
  }

  static async setEnabled(sourceUrl: string, enabled: boolean): Promise<void> {
    const normalizedUrl = LocalRuleSourceRepository.requireSourceUrl(sourceUrl);
    const updated = await LocalRuleSourceRepository.setEnabledBatch([normalizedUrl], enabled);
    if (updated === 0) throw new Error('书源已锁定，请先解锁');
  }

  /** 在同一事务中启用或禁用多条书源，任一书源不存在则整批回滚。 */
  static async setEnabledBatch(sourceUrls: string[], enabled: boolean): Promise<number> {
    const values: relationalStore.ValuesBucket = {
      'enabled': enabled ? 1 : 0,
      'updated_at': Date.now()
    };
    return LocalRuleSourceRepository.updateManagedBatch(sourceUrls, values, false);
  }

  static async setExploreEnabledBatch(sourceUrls: string[], enabled: boolean): Promise<number> {
    const values: relationalStore.ValuesBucket = {
      'enabled_explore': enabled ? 1 : 0,
      'updated_at': Date.now()
    };
    return LocalRuleSourceRepository.updateManagedBatch(sourceUrls, values, false);
  }

  static async setLockedBatch(sourceUrls: string[], locked: boolean): Promise<number> {
    const values: relationalStore.ValuesBucket = {
      'is_locked': locked ? 1 : 0,
      'updated_at': Date.now()
    };
    return LocalRuleSourceRepository.updateManagedBatch(sourceUrls, values, true);
  }

  static async setGroupBatch(sourceUrls: string[], group: string): Promise<number> {
    const normalized = LocalRuleSourceRepository.groupNames(group)
      .map((name: string): string => LocalRuleSourceRepository.normalizeGroup(name, false)).join(',');
    const values: relationalStore.ValuesBucket = {
      'source_group': normalized,
      'updated_at': Date.now()
    };
    return LocalRuleSourceRepository.updateManagedBatch(sourceUrls, values, false);
  }

  static async setPinned(sourceUrl: string, pinned: boolean): Promise<void> {
    const normalizedUrl = LocalRuleSourceRepository.requireSourceUrl(sourceUrl);
    const store = await LocalRuleSourceRepository.ensureStore();
    const transaction = await store.createTransaction();
    try {
      await LocalRuleSourceRepository.selectManagedUrls(transaction, [normalizedUrl], true);
      const rows = await transaction.querySql(`SELECT MIN(custom_order) FROM ${TABLE_NAME}`);
      let firstOrder = 0;
      try {
        if (rows.goToFirstRow()) firstOrder = rows.getLong(0) - 1;
      } finally {
        rows.close();
      }
      const values: relationalStore.ValuesBucket = {
        'is_pinned': pinned ? 1 : 0, 'custom_order': firstOrder, 'updated_at': Date.now()
      };
      const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
      predicates.equalTo('source_url', normalizedUrl);
      await transaction.update(values, predicates);
      await transaction.commit();
    } catch (error) {
      await LocalRuleSourceRepository.rollback(transaction);
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
  }

  /** 可传入筛选后的列表；其余书源保留原位置，置顶分区始终优先。 */
  static async saveOrder(orderedUrls: string[]): Promise<void> {
    if (orderedUrls.length === 0) return;
    const requested = LocalRuleSourceRepository.normalizeUrls(orderedUrls);
    const store = await LocalRuleSourceRepository.ensureStore();
    const transaction = await store.createTransaction();
    try {
      await LocalRuleSourceRepository.selectManagedUrls(transaction, requested, true);
      const rows = await transaction.querySql(LIST_SQL);
      const current: string[] = [];
      const pinned = new Set<string>();
      try {
        while (rows.goToNextRow()) {
          current.push(rows.getString(0));
          if (rows.getLong(10) !== 0) pinned.add(rows.getString(0));
        }
      } finally {
        rows.close();
      }
      const selected = new Set<string>(requested);
      let nextIndex = 0;
      const merged = current.map((url: string): string => selected.has(url) ? requested[nextIndex++] : url);
      const ordered = merged.filter((url: string): boolean => pinned.has(url))
        .concat(merged.filter((url: string): boolean => !pinned.has(url)));
      for (let index = 0; index < ordered.length; index++) {
        const values: relationalStore.ValuesBucket = { 'custom_order': index, 'updated_at': Date.now() };
        const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
        predicates.equalTo('source_url', ordered[index]);
        await transaction.update(values, predicates);
      }
      await transaction.commit();
    } catch (error) {
      await LocalRuleSourceRepository.rollback(transaction);
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
  }

  static groupNames(sourceGroup: string): string[] {
    const names: string[] = [];
    for (const value of sourceGroup.split(/[,，·|]+/)) {
      const name = value.trim();
      if (name.length > 0 && name.toLowerCase() !== '[object object]' && !names.includes(name)) names.push(name);
    }
    return names;
  }

  static async listGroups(): Promise<string[]> {
    const store = await LocalRuleSourceRepository.ensureStore();
    const rows = await store.querySql(`SELECT group_name FROM ${GROUP_TABLE_NAME} UNION ` +
      `SELECT TRIM(source_group) AS group_name FROM ${TABLE_NAME} WHERE TRIM(source_group) <> '' ` +
      'ORDER BY group_name COLLATE NOCASE ASC');
    const groups = new Set<string>();
    try {
      while (rows.goToNextRow()) {
        for (const name of LocalRuleSourceRepository.groupNames(rows.getString(0))) groups.add(name);
      }
    } finally {
      rows.close();
    }
    return Array.from(groups).sort((left: string, right: string): number => left.localeCompare(right));
  }

  static async createGroup(name: string): Promise<void> {
    const group = LocalRuleSourceRepository.normalizeGroup(name, false);
    const store = await LocalRuleSourceRepository.ensureStore();
    const transaction = await store.createTransaction();
    try {
      if (await LocalRuleSourceRepository.groupExists(transaction, group)) throw new Error('分组名称已存在');
      const values: relationalStore.ValuesBucket = { 'group_name': group, 'created_at': Date.now() };
      await transaction.insert(GROUP_TABLE_NAME, values);
      await transaction.commit();
    } catch (error) {
      await LocalRuleSourceRepository.rollback(transaction);
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
  }

  static async renameGroup(oldName: string, newName: string): Promise<number> {
    const oldGroup = LocalRuleSourceRepository.normalizeGroup(oldName, false);
    const newGroup = LocalRuleSourceRepository.normalizeGroup(newName, false);
    if (oldGroup === newGroup) return 0;
    return LocalRuleSourceRepository.changeGroup(oldGroup, newGroup);
  }

  static async deleteGroup(name: string): Promise<number> {
    return LocalRuleSourceRepository.changeGroup(LocalRuleSourceRepository.normalizeGroup(name, false), '');
  }

  static async toggle(sourceUrl: string): Promise<boolean> {
    const normalizedUrl = LocalRuleSourceRepository.requireSourceUrl(sourceUrl);
    const source = await LocalRuleSourceRepository.get(normalizedUrl);
    if (source === undefined) {
      throw new Error(`书源不存在：${normalizedUrl}`);
    }
    const enabled = !source.enabled;
    await LocalRuleSourceRepository.setEnabled(normalizedUrl, enabled);
    return enabled;
  }

  static async delete(sourceUrl: string): Promise<boolean> {
    const normalizedUrl = LocalRuleSourceRepository.requireSourceUrl(sourceUrl);
    return (await LocalRuleSourceRepository.deleteSources([normalizedUrl], true)) > 0;
  }

  /** 在同一事务中分块删除多条书源、登录会话和 Cookie，避免大批量逐行调用。 */
  static async deleteBatch(sourceUrls: string[]): Promise<number> {
    return LocalRuleSourceRepository.deleteSources(sourceUrls, false);
  }

  private static async deleteSources(sourceUrls: string[], single: boolean): Promise<number> {
    if (sourceUrls.length === 0) return 0;
    const requested = LocalRuleSourceRepository.normalizeUrls(sourceUrls);

    const store = await LocalRuleSourceRepository.ensureStore();
    const transaction = await store.createTransaction();
    let deletedCount = 0;
    try {
      const normalizedUrls = await LocalRuleSourceRepository.selectManagedUrls(transaction, requested, false, single);
      if (single && normalizedUrls.length === 0) {
        const existing = await LocalRuleSourceRepository.selectManagedUrls(transaction, requested, true, true);
        if (existing.length > 0) throw new Error('书源已锁定，请先解锁');
      }
      for (let start = 0; start < normalizedUrls.length; start += BATCH_PREDICATE_LIMIT) {
        const end = Math.min(normalizedUrls.length, start + BATCH_PREDICATE_LIMIT);
        const batchValues: relationalStore.ValueType[] = [];
        for (let index = start; index < end; index++) batchValues.push(normalizedUrls[index]);
        const sessionPredicates = new relationalStore.RdbPredicates(SESSION_TABLE_NAME);
        sessionPredicates.in('source_url', batchValues);
        const cookiePredicates = new relationalStore.RdbPredicates(COOKIE_TABLE_NAME);
        cookiePredicates.in('source_url', batchValues);
        const sourcePredicates = new relationalStore.RdbPredicates(TABLE_NAME);
        sourcePredicates.in('source_url', batchValues);
        await transaction.delete(sessionPredicates);
        await transaction.delete(cookiePredicates);
        const loginPredicates = new relationalStore.RdbPredicates(LOGIN_TABLE_NAME);
        loginPredicates.in('source_url', batchValues);
        await transaction.delete(loginPredicates);
        const statePredicates = new relationalStore.RdbPredicates(STATE_TABLE_NAME);
        statePredicates.in('source_url', batchValues);
        await transaction.delete(statePredicates);
        deletedCount += await transaction.delete(sourcePredicates);
      }
      if (deletedCount !== normalizedUrls.length) throw new Error('部分书源不存在，批量删除已取消');
      await transaction.commit();
      return deletedCount;
    } catch (error) {
      try {
        await transaction.rollback();
      } catch (_rollbackError) {
        // 事务可能已关闭，保留原始删除错误。
      }
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
  }

  static async remove(sourceUrl: string): Promise<void> {
    await LocalRuleSourceRepository.delete(sourceUrl);
  }

  private static async open(context: common.BaseContext): Promise<void> {
    const config: relationalStore.StoreConfig = {
      name: DATABASE_NAME,
      securityLevel: relationalStore.SecurityLevel.S2,
      encrypt: true,
      allowRebuild: false
    };
    const store = await relationalStore.getRdbStore(context, config);
    await store.execute(CREATE_TABLE_SQL);
    await store.execute(CREATE_SESSION_TABLE_SQL);
    await store.execute(CREATE_COOKIE_TABLE_SQL);
    await store.execute(`CREATE TABLE IF NOT EXISTS ${LOGIN_TABLE_NAME} (` +
      'source_url TEXT PRIMARY KEY NOT NULL, status TEXT NOT NULL, updated_at INTEGER NOT NULL)');
    await store.execute(`INSERT OR IGNORE INTO ${LOGIN_TABLE_NAME} (source_url, status, updated_at) ` +
      `SELECT source_url, 'valid', updated_at FROM ${SESSION_TABLE_NAME} WHERE token <> ''`);
    await store.execute(`INSERT OR IGNORE INTO ${LOGIN_TABLE_NAME} (source_url, status, updated_at) ` +
      `SELECT source_url, 'saved', updated_at FROM ${COOKIE_TABLE_NAME} WHERE cookie_header <> ''`);
    await store.execute(`CREATE TABLE IF NOT EXISTS ${STATE_TABLE_NAME} (` +
      'source_url TEXT PRIMARY KEY NOT NULL, state_json TEXT NOT NULL)');
    await store.execute(`CREATE TABLE IF NOT EXISTS ${GROUP_TABLE_NAME} (` +
      'group_name TEXT PRIMARY KEY NOT NULL, created_at INTEGER NOT NULL)');
    await LocalRuleSourceRepository.migrateManagementFields(store);
    LocalRuleSourceRepository.store = store;
  }

  private static async ensureStore(): Promise<relationalStore.RdbStore> {
    if (LocalRuleSourceRepository.store === null && LocalRuleSourceRepository.initPromise !== null) {
      await LocalRuleSourceRepository.initPromise;
    }
    if (LocalRuleSourceRepository.store === null) {
      throw new Error('LocalRuleSourceRepository 尚未初始化');
    }
    return LocalRuleSourceRepository.store;
  }

  private static async migrateManagementFields(store: relationalStore.RdbStore): Promise<void> {
    const transaction = await store.createTransaction();
    try {
      const columns = new Set<string>();
      const schema = await transaction.querySql(`PRAGMA table_info(${TABLE_NAME})`);
      try {
        while (schema.goToNextRow()) columns.add(schema.getString(1));
      } finally {
        schema.close();
      }
      const fields: string[] = ['enabled_explore', 'is_locked', 'is_pinned', 'custom_order'];
      const missing = fields.filter((field: string): boolean => !columns.has(field));
      for (const field of missing) {
        await transaction.execute(`ALTER TABLE ${TABLE_NAME} ADD COLUMN ${field} INTEGER NOT NULL DEFAULT 0`);
      }
      if (missing.length > 0) {
        const rows = await transaction.querySql(`SELECT source_url, source_json FROM ${TABLE_NAME} ` +
          'ORDER BY sort_order DESC, source_name COLLATE NOCASE ASC');
        const urls: string[] = [];
        const definitions: string[] = [];
        try {
          while (rows.goToNextRow()) {
            urls.push(rows.getString(0));
            definitions.push(rows.getString(1));
          }
        } finally {
          rows.close();
        }
        for (let index = 0; index < urls.length; index++) {
          const parsed = LocalRuleSourceImportParser.parse(definitions[index]).sources;
          const source = parsed.length > 0 ? parsed[0] : new LocalRuleSource();
          const values: relationalStore.ValuesBucket = {};
          if (missing.includes('enabled_explore')) values['enabled_explore'] = source.enabledExplore ? 1 : 0;
          if (missing.includes('is_locked')) values['is_locked'] = source.isLocked ? 1 : 0;
          if (missing.includes('is_pinned')) values['is_pinned'] = source.isPinned ? 1 : 0;
          if (missing.includes('custom_order')) values['custom_order'] = index;
          const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
          predicates.equalTo('source_url', urls[index]);
          await transaction.update(values, predicates);
        }
      }
      await transaction.commit();
    } catch (error) {
      await LocalRuleSourceRepository.rollback(transaction);
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
  }

  private static async updateManagedBatch(sourceUrls: string[], values: relationalStore.ValuesBucket,
    allowLocked: boolean): Promise<number> {
    if (sourceUrls.length === 0) return 0;
    const store = await LocalRuleSourceRepository.ensureStore();
    const transaction = await store.createTransaction();
    try {
      const urls = await LocalRuleSourceRepository.selectManagedUrls(transaction,
        LocalRuleSourceRepository.normalizeUrls(sourceUrls), allowLocked);
      let updatedCount = 0;
      for (let start = 0; start < urls.length; start += BATCH_PREDICATE_LIMIT) {
        const args: relationalStore.ValueType[] = urls.slice(start, start + BATCH_PREDICATE_LIMIT);
        const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
        predicates.in('source_url', args);
        updatedCount += await transaction.update(values, predicates);
      }
      const group = values['source_group'];
      if (updatedCount > 0 && typeof group === 'string' && group.length > 0) {
        for (const name of LocalRuleSourceRepository.groupNames(group)) {
          const groupValues: relationalStore.ValuesBucket = { 'group_name': name, 'created_at': Date.now() };
          await transaction.insert(GROUP_TABLE_NAME, groupValues,
            relationalStore.ConflictResolution.ON_CONFLICT_IGNORE);
        }
      }
      await transaction.commit();
      return updatedCount;
    } catch (error) {
      await LocalRuleSourceRepository.rollback(transaction);
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
  }

  private static async selectManagedUrls(transaction: relationalStore.Transaction, urls: string[],
    allowLocked: boolean, allowMissing: boolean = false): Promise<string[]> {
    const eligible: string[] = [];
    for (let start = 0; start < urls.length; start += BATCH_PREDICATE_LIMIT) {
      const batch = urls.slice(start, start + BATCH_PREDICATE_LIMIT);
      const args: relationalStore.ValueType[] = batch;
      const placeholders = batch.map((_url: string): string => '?').join(',');
      const rows = await transaction.querySql(`SELECT source_url, is_locked FROM ${TABLE_NAME} ` +
        `WHERE source_url IN (${placeholders})`, args);
      let found = 0;
      try {
        while (rows.goToNextRow()) {
          found++;
          if (allowLocked || rows.getLong(1) === 0) eligible.push(rows.getString(0));
        }
      } finally {
        rows.close();
      }
      if (!allowMissing && found !== batch.length) throw new Error('部分书源不存在，操作已取消');
    }
    return eligible;
  }

  private static normalizeUrls(sourceUrls: string[]): string[] {
    const urls: string[] = [];
    const seen = new Set<string>();
    for (const value of sourceUrls) {
      const url = LocalRuleSourceRepository.requireSourceUrl(value);
      if (!seen.has(url)) urls.push(url);
      seen.add(url);
    }
    return urls;
  }

  private static normalizeGroup(value: string, allowEmpty: boolean): string {
    const group = value.trim();
    if (!allowEmpty && group.length === 0) throw new Error('分组名称不能为空');
    if (group.length > 100) throw new Error('分组名称不能超过 100 个字符');
    if (/[\r\n\x00-\x1f]/.test(group)) throw new Error('分组名称包含非法字符');
    if (/[,，·|]/.test(group)) throw new Error('分组名称不能包含分隔符');
    return group;
  }

  private static async groupExists(transaction: relationalStore.Transaction, group: string): Promise<boolean> {
    const rows = await transaction.querySql(`SELECT group_name FROM ${GROUP_TABLE_NAME} ` +
      `UNION SELECT source_group FROM ${TABLE_NAME} WHERE TRIM(source_group) <> ''`);
    try {
      while (rows.goToNextRow()) {
        if (LocalRuleSourceRepository.groupNames(rows.getString(0)).includes(group)) return true;
      }
      return false;
    } finally {
      rows.close();
    }
  }

  private static async changeGroup(oldGroup: string, newGroup: string): Promise<number> {
    const store = await LocalRuleSourceRepository.ensureStore();
    const transaction = await store.createTransaction();
    try {
      if (!await LocalRuleSourceRepository.groupExists(transaction, oldGroup)) throw new Error('分组不存在');
      if (newGroup.length > 0 && await LocalRuleSourceRepository.groupExists(transaction, newGroup)) {
        throw new Error('分组名称已存在');
      }
      const sourceRows = await transaction.querySql(`SELECT source_url, source_group FROM ${TABLE_NAME} ` +
        "WHERE is_locked = 0 AND TRIM(source_group) <> ''");
      const sourceUrls: string[] = [];
      const sourceGroups: string[] = [];
      try {
        while (sourceRows.goToNextRow()) {
          const names = LocalRuleSourceRepository.groupNames(sourceRows.getString(1));
          if (!names.includes(oldGroup)) continue;
          sourceUrls.push(sourceRows.getString(0));
          sourceGroups.push(LocalRuleSourceRepository.replaceGroupName(names, oldGroup, newGroup).join(','));
        }
      } finally {
        sourceRows.close();
      }
      for (let index = 0; index < sourceUrls.length; index++) {
        const values: relationalStore.ValuesBucket = {
          'source_group': sourceGroups[index], 'updated_at': Date.now()
        };
        const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
        predicates.equalTo('source_url', sourceUrls[index]);
        await transaction.update(values, predicates);
      }
      const groupRows = await transaction.querySql(`SELECT group_name FROM ${GROUP_TABLE_NAME}`);
      const storedGroups: string[] = [];
      try {
        while (groupRows.goToNextRow()) storedGroups.push(groupRows.getString(0));
      } finally {
        groupRows.close();
      }
      // 兼容旧版本曾把 A,B 作为一个持久分组保存的情况。
      for (const stored of storedGroups) {
        const names = LocalRuleSourceRepository.groupNames(stored);
        if (!names.includes(oldGroup)) continue;
        const predicates = new relationalStore.RdbPredicates(GROUP_TABLE_NAME);
        predicates.equalTo('group_name', stored);
        await transaction.delete(predicates);
        for (const name of LocalRuleSourceRepository.replaceGroupName(names, oldGroup, newGroup)) {
          const values: relationalStore.ValuesBucket = { 'group_name': name, 'created_at': Date.now() };
          await transaction.insert(GROUP_TABLE_NAME, values, relationalStore.ConflictResolution.ON_CONFLICT_IGNORE);
        }
      }
      if (newGroup.length > 0) {
        const values: relationalStore.ValuesBucket = { 'group_name': newGroup, 'created_at': Date.now() };
        await transaction.insert(GROUP_TABLE_NAME, values, relationalStore.ConflictResolution.ON_CONFLICT_IGNORE);
      }
      await transaction.commit();
      return sourceUrls.length;
    } catch (error) {
      await LocalRuleSourceRepository.rollback(transaction);
      if (error instanceof Error) throw error;
      throw new Error(String(error));
    }
  }

  private static replaceGroupName(names: string[], oldName: string, newName: string): string[] {
    const updated: string[] = [];
    for (const name of names) {
      const next = name === oldName ? newName : name;
      if (next.length > 0 && !updated.includes(next)) updated.push(next);
    }
    return updated;
  }

  private static async rollback(transaction: relationalStore.Transaction): Promise<void> {
    try {
      await transaction.rollback();
    } catch (_error) {
      // 保留最初的数据库错误。
    }
  }

  private static prepare(source: LocalRuleSource): PreparedRuleSource {
    const sourceUrl = LocalRuleSourceRepository.requireSourceUrl(source.bookSourceUrl);
    if (source.bookSourceName.trim().length === 0) {
      throw new Error(`书源名称为空：${sourceUrl}`);
    }

    const sourceJson = LocalRuleSourceCodec.stringify(source);
    const sourceBytes = buffer.byteLength(sourceJson, 'utf-8');
    if (sourceBytes > MAX_SOURCE_JSON_BYTES) {
      throw new Error(`书源数据超过 1 MiB：${source.bookSourceName}`);
    }

    const report = LocalRuleSourceImportParser.parse(sourceJson);
    let matched = false;
    for (const parsed of report.sources) {
      if (parsed.bookSourceUrl === sourceUrl) {
        matched = true;
        break;
      }
    }
    if (!matched) {
      const detail = report.message.length > 0 ? `，${report.message}` : '';
      throw new Error(`书源原始数据无法重建：${source.bookSourceName}${detail}`);
    }
    return new PreparedRuleSource(source, sourceJson);
  }

  private static toValues(item: PreparedRuleSource, sortOrder: number,
    now: number, createdAt: number): relationalStore.ValuesBucket {
    const source = item.source;
    const values: relationalStore.ValuesBucket = {
      'source_url': source.bookSourceUrl.trim(),
      'source_name': source.bookSourceName.trim(),
      'source_type': source.bookSourceType,
      'source_group': source.bookSourceGroup,
      'source_json': item.sourceJson,
      'enabled': source.enabled ? 1 : 0,
      'enabled_explore': source.enabledExplore ? 1 : 0,
      'is_locked': source.isLocked ? 1 : 0,
      'is_pinned': source.isPinned ? 1 : 0,
      'custom_order': source.customOrder,
      'validation_status': source.validationStatus,
      'validation_message': source.validationMessage,
      'sort_order': sortOrder,
      'created_at': createdAt,
      'updated_at': now
    };
    return values;
  }

  private static readSource(resultSet: relationalStore.ResultSet): LocalRuleSource {
    const startedAt = Date.now();
    const sourceUrl = resultSet.getString(0);
    const sourceName = resultSet.getString(1);
    const sourceType = resultSet.getLong(2);
    const sourceGroup = resultSet.getString(3);
    const sourceJson = resultSet.getString(4);
    const enabled = resultSet.getLong(5) !== 0;
    const validationStatus = resultSet.getLong(6);
    const validationMessage = resultSet.getString(7);

    const report: LocalRuleSourceImportReport = LocalRuleSourceImportParser.parse(sourceJson);
    let source: LocalRuleSource | undefined = undefined;
    for (const parsed of report.sources) {
      if (parsed.bookSourceUrl === sourceUrl) {
        source = parsed;
        break;
      }
    }
    if (source === undefined) {
      source = LocalRuleSource.descriptor(sourceUrl, sourceName);
      source.enabled = false;
      source.validationStatus = LocalRuleSourceStatus.UNSUPPORTED;
      source.validationMessage = report.message.length > 0
        ? `持久化书源无法解析：${report.message}` : '持久化书源无法解析';
    } else {
      source.enabled = enabled;
      if (validationStatus === LocalRuleSourceStatus.UNSUPPORTED) {
        source.validationStatus = LocalRuleSourceStatus.UNCHECKED;
        source.validationMessage = '兼容层已更新，等待重新测试';
      } else {
        source.validationStatus = validationStatus;
        source.validationMessage = validationMessage;
      }
    }

    source.bookSourceUrl = sourceUrl;
    source.bookSourceName = sourceName;
    source.bookSourceType = sourceType;
    source.bookSourceGroup = sourceGroup;
    source.enabledExplore = resultSet.getLong(8) !== 0;
    source.isLocked = resultSet.getLong(9) !== 0;
    source.isPinned = resultSet.getLong(10) !== 0;
    source.customOrder = resultSet.getLong(11);
    source.rawSourceJson = sourceJson;
    if (Date.now() - startedAt >= 8) console.info(`[ComicPerf] source-row ms=${Date.now() - startedAt}`);
    return source;
  }

  private static requireSourceUrl(sourceUrl: string): string {
    const normalizedUrl = sourceUrl.trim();
    if (normalizedUrl.length === 0) throw new Error('书源地址为空');
    return normalizedUrl;
  }

  private static requireSessionValue(fieldName: string, value: string, maxLength: number): string {
    if (value.length === 0) throw new Error(`${fieldName} 不能为空`);
    if (value.length > maxLength) throw new Error(`${fieldName} 长度不能超过 ${maxLength}`);
    if (value.includes('\r') || value.includes('\n') || value.includes(';')) {
      throw new Error(`${fieldName} 包含非法字符`);
    }
    return value;
  }

  private static requireSessionToken(value: string): string {
    if (value.length > MAX_SESSION_TOKEN_LENGTH) {
      throw new Error(`token 长度不能超过 ${MAX_SESSION_TOKEN_LENGTH}`);
    }
    if (value.includes('\r') || value.includes('\n') || value.includes(';')) {
      throw new Error('token 包含非法字符');
    }
    return value;
  }

  private static requireOrigin(value: string): string {
    const normalized = value.trim().toLowerCase();
    const schemeEnd = normalized.indexOf('://');
    if (schemeEnd < 0 || (normalized.substring(0, schemeEnd) !== 'https' &&
      normalized.substring(0, schemeEnd) !== 'http')) {
      throw new Error('Cookie origin 格式不正确');
    }
    const authority = normalized.substring(schemeEnd + 3);
    if (authority.length === 0 || authority.includes('/') || authority.includes('?') ||
      authority.includes('#') || authority.includes(' ') || authority.includes('\t')) {
      throw new Error('Cookie origin 格式不正确');
    }
    return normalized;
  }

  private static requireCookieHeader(value: string): string {
    const normalized = value.trim();
    if (normalized.length > MAX_COOKIE_HEADER_LENGTH) {
      throw new Error(`Cookie 长度不能超过 ${MAX_COOKIE_HEADER_LENGTH}`);
    }
    if (normalized.includes('\r') || normalized.includes('\n')) {
      throw new Error('Cookie 包含非法字符');
    }
    return normalized;
  }
}
