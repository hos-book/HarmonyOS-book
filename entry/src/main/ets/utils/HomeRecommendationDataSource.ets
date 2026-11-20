/** 首页横向书单的数据源；实例跨分类切换保留，仅在推荐数据返回时更新。 */
export class HomeRecommendationDataSource<T> implements IDataSource {
  private items: T[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): T {
    return this.items[index];
  }

  setItems(items: T[]): void {
    this.items = items;
    for (const listener of this.listeners) listener.onDataReloaded();
  }

  /** 同顺序的数据快照仅通知替换项和追加项；重排仍由 setItems 完整通知。 */
  updateItems(items: T[]): void {
    const previous: T[] = this.items;
    if (items.length < previous.length) {
      this.setItems(items);
      return;
    }
    this.items = items;
    for (let index: number = 0; index < previous.length; index++) {
      if (previous[index] !== items[index]) {
        for (const listener of this.listeners.slice()) listener.onDataChange(index);
      }
    }
    for (let index: number = previous.length; index < items.length; index++) {
      for (const listener of this.listeners.slice()) listener.onDataAdd(index);
    }
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }
}
