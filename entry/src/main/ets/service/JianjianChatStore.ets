import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { JianjianChatItem, JianjianChatRoute, JianjianCitation } from '../model/JianjianAi';

/** Atomic completed turns, separate from credentials and exported reading history. */
export class JianjianChatStore {
  private static chain: Promise<void> = Promise.resolve();

  static key(route: JianjianChatRoute): string {
    return route.bookId ? JSON.stringify(['book', route.sourceUrl, route.bookUrl || route.bookId, route.bookId]) : 'general';
  }

  private static async store(context: common.Context): Promise<relationalStore.RdbStore> {
    const store = await relationalStore.getRdbStore(context, { name: 'jianjian_chats.db',
      securityLevel: relationalStore.SecurityLevel.S2, encrypt: true, allowRebuild: false });
    await store.executeSql('CREATE TABLE IF NOT EXISTS conversations (id TEXT PRIMARY KEY, messages TEXT NOT NULL, updated_at INTEGER NOT NULL)');
    return store;
  }

  static decode(raw: string): JianjianChatItem[] {
    if (!raw || raw.length > 200000) return [];
    const parsed: JianjianChatItem[] = JSON.parse(raw);
    if (!Array.isArray(parsed)) throw new Error('Invalid conversation');
    const items: JianjianChatItem[] = [];
    const ids: Set<string> = new Set<string>();
    for (const item of parsed.slice(-60)) {
      if (!item || typeof item.id !== 'string' || !item.id || ids.has(item.id) ||
        !['user', 'assistant'].includes(item.role) || typeof item.content !== 'string' ||
        !item.content || item.content.length > 32000) continue;
      const value = new JianjianChatItem(item.id, item.role, item.content);
      value.boundaryChapter = Number.isSafeInteger(item.boundaryChapter) ? item.boundaryChapter : -1;
      value.boundaryOffset = Number.isSafeInteger(item.boundaryOffset) ? item.boundaryOffset : -1;
      if (Array.isArray(item.references)) {
        for (const ref of item.references.slice(0, 8)) {
          if (!ref || typeof ref.id !== 'string' || !/^[1-8]$/.test(ref.id) ||
            typeof ref.chapterId !== 'string' || typeof ref.chapterUrl !== 'string' ||
            typeof ref.chapterTitle !== 'string' || ref.chapterTitle.length > 1024 ||
            ![ref.chapterIndex, ref.charOffset, ref.endOffset].every((n: number): boolean => Number.isSafeInteger(n) && n >= 0) ||
            ref.endOffset <= ref.charOffset) continue;
          const citation = new JianjianCitation();
          citation.id = ref.id; citation.chapterId = ref.chapterId; citation.chapterUrl = ref.chapterUrl;
          citation.chapterTitle = ref.chapterTitle; citation.chapterIndex = ref.chapterIndex;
          citation.charOffset = ref.charOffset; citation.endOffset = ref.endOffset;
          value.references.push(citation);
        }
      }
      ids.add(value.id); items.push(value);
    }
    // A pending, cancelled or malformed half-turn must never reappear after reopening.
    const complete: JianjianChatItem[] = [];
    for (let index = 0; index + 1 < items.length; index++) {
      if (items[index].role === 'user' && items[index + 1].role === 'assistant') {
        complete.push(items[index], items[index + 1]); index++;
      }
    }
    return complete;
  }

  static async load(context: common.Context, key: string): Promise<JianjianChatItem[]> {
    await JianjianChatStore.chain;
    const store = await JianjianChatStore.store(context);
    const rows = await store.querySql('SELECT messages FROM conversations WHERE id = ?', [key]);
    try { return rows.goToFirstRow() ? JianjianChatStore.decode(rows.getString(0)) : []; }
    finally { rows.close(); }
  }

  private static enqueue(action: () => Promise<void>): Promise<void> {
    const task = JianjianChatStore.chain.then(action);
    JianjianChatStore.chain = task.catch((): void => {});
    return task;
  }

  static save(context: common.Context, key: string, items: JianjianChatItem[]): Promise<void> {
    let bounded = items.slice(-60);
    while (JSON.stringify(bounded).length > 180000 && bounded.length > 2) bounded = bounded.slice(2);
    const raw = JSON.stringify(bounded);
    return JianjianChatStore.enqueue(async (): Promise<void> => {
      const store = await JianjianChatStore.store(context);
      await store.executeSql('INSERT OR REPLACE INTO conversations (id, messages, updated_at) VALUES (?, ?, ?)', [key, raw, Date.now()]);
      await store.executeSql('DELETE FROM conversations WHERE id NOT IN (SELECT id FROM conversations ORDER BY updated_at DESC LIMIT 100)');
    });
  }

  static clear(context: common.Context, key: string): Promise<void> {
    return JianjianChatStore.enqueue(async (): Promise<void> => {
      const store = await JianjianChatStore.store(context);
      await store.executeSql('DELETE FROM conversations WHERE id = ?', [key]);
    });
  }
}
