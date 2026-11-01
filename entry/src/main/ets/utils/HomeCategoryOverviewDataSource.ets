import { HomeSourceCategory } from '../service/rulesource/HomeSourceService';

export class HomeCategoryOverviewItem {
  category: HomeSourceCategory;
  label: string;
  key: string;
  constructor(category: HomeSourceCategory, label: string) {
    this.category = category;
    this.label = label;
    this.key = JSON.stringify([category.group, category.url, category.name]);
  }
}

export class HomeCategoryOverviewRow {
  title: string;
  channel: string;
  categories: HomeCategoryOverviewItem[] = [];
  key: string;
  constructor(channel: string, title: string) {
    this.channel = channel;
    this.title = title;
    this.key = JSON.stringify([channel, title]);
  }
}

/** 书源分组优先；明确的“全部·大类”入口开启子分组，保留原 URL 与频道。 */
export class HomeCategoryOverviewDataSource implements IDataSource {
  private rows: HomeCategoryOverviewRow[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): HomeCategoryOverviewRow {
    return this.rows[index];
  }

  static group(categories: HomeSourceCategory[], query: string = ''): HomeCategoryOverviewRow[] {
    const rows: HomeCategoryOverviewRow[] = [];
    const active = new Map<string, HomeCategoryOverviewRow>();
    const seen = new Set<string>();
    for (const category of categories) {
      const key = JSON.stringify([category.group, category.url, category.name]);
      if (seen.has(key)) continue;
      seen.add(key);
      const heading = /^(?:全部|所有)\s*[·•:：／/]\s*(\S.*?)\s*$/.exec(category.name);
      let row = active.get(category.group);
      if (heading !== null || row === undefined) {
        const title = heading !== null ? heading[1] : category.group;
        row = rows.find((candidate: HomeCategoryOverviewRow): boolean =>
          candidate.channel === category.group && candidate.title === title);
        if (row === undefined) { row = new HomeCategoryOverviewRow(category.group, title); rows.push(row); }
        active.set(category.group, row);
      }
      row.categories.push(new HomeCategoryOverviewItem(category, heading !== null ? '' : category.name));
    }
    const keyword = query.trim().toLocaleLowerCase();
    if (!keyword) return rows;
    const result: HomeCategoryOverviewRow[] = [];
    for (const row of rows) {
      const filtered = new HomeCategoryOverviewRow(row.channel, row.title);
      const matchesGroup = `${row.channel} ${row.title}`.toLocaleLowerCase().includes(keyword);
      filtered.categories = row.categories.filter((item: HomeCategoryOverviewItem): boolean =>
        matchesGroup || item.category.name.toLocaleLowerCase().includes(keyword));
      if (filtered.categories.length > 0) result.push(filtered);
    }
    return result;
  }

  setCategories(categories: HomeSourceCategory[], query: string = ''): void {
    this.rows = HomeCategoryOverviewDataSource.group(categories, query);
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDataReloaded());
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }
}
