import { Book } from './Book';

export enum HiCarTab {
  Recent = 0,
  Shelf = 1,
  Downloaded = 2
}

@ObservedV2
export class HiCarState {
  @Trace supported: boolean = false;
  @Trace connected: boolean = false;
  @Trace carWindow: boolean = false;
}

export class HiCarLibrary {
  recent: Book[] = [];
  shelf: Book[] = [];
  downloaded: Book[] = [];

  books(tab: HiCarTab): Book[] {
    if (tab === HiCarTab.Shelf) return this.shelf;
    if (tab === HiCarTab.Downloaded) return this.downloaded;
    return this.recent;
  }
}
