export class ComicAiConfig {
  baseUrl: string = '';
  apiKey: string = '';
  model: string = '';
  models: string[] = [];
}

export class ComicAiModel {
  id: string = '';
}

export class ComicAiModelPage {
  data: ComicAiModel[] = [];
  has_more: boolean = false;
  last_id: string = '';
}

export class ComicAiModelDataSource implements IDataSource {
  private items: string[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.items.length; }
  getData(index: number): string { return this.items[index]; }
  setItems(items: string[]): void {
    this.items = items;
    for (const listener of this.listeners) listener.onDataReloaded();
  }
  registerDataChangeListener(listener: DataChangeListener): void { this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener): boolean => item !== listener);
  }
}
