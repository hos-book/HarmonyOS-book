/** 勋章定义与持久化记录分离，资源仅用于展示。 */
export class MedalDefinition {
  id: string;
  hours: number;
  image: Resource;
  badge: Resource;
  name: Resource;

  constructor(id: string, hours: number, image: Resource, name: Resource, badge: Resource = image) {
    this.id = id;
    this.hours = hours;
    this.image = image;
    this.name = name;
    this.badge = badge;
  }
}

export const MEDALS: MedalDefinition[] = [
  new MedalDefinition('reading_1h', 1, $r('app.media.reading_medal_1h'), $r('app.string.account_reading_medal_1h_name')),
  new MedalDefinition('reading_10h', 10, $r('app.media.reading_medal_10h'), $r('app.string.account_reading_medal_10h_name')),
  new MedalDefinition('reading_50h', 50, $r('app.media.reading_medal_50h'), $r('app.string.account_reading_medal_50h_name')),
  new MedalDefinition('reading_100h', 100, $r('app.media.reading_medal_100h'), $r('app.string.account_reading_medal_100h_name')),
  new MedalDefinition('reading_300h', 300, $r('app.media.reading_medal_300h'), $r('app.string.account_reading_medal_300h_name')),
  new MedalDefinition('reading_500h', 500, $r('app.media.reading_medal_500h'), $r('app.string.account_reading_medal_500h_name')),
  new MedalDefinition('reading_1000h', 1000, $r('app.media.reading_medal_1000h'), $r('app.string.account_reading_medal_1000h_name')),
  new MedalDefinition('reading_2000h', 2000, $r('app.media.reading_medal_2000h'), $r('app.string.account_reading_medal_2000h_name')),
  new MedalDefinition('reading_5000h', 5000, $r('app.media.reading_medal_5000h'), $r('app.string.account_reading_medal_5000h_name'))
];

export class MedalAward {
  medalId: string = '';
  unlockedAt: number = 0;
  historical: boolean = true;

  constructor(medalId: string = '', unlockedAt: number = 0, historical: boolean = true) {
    this.medalId = medalId;
    this.unlockedAt = unlockedAt;
    this.historical = historical;
  }
}

export class MedalSnapshot {
  version: number = 1;
  selectedMedalId: string = '';
  awards: MedalAward[] = [];
  /** SHA-256 应用内账号标识；空值为旧版或未登录数据。 */
  ownerKey: string = '';
  earnedSeconds: number = 0;
  /** 仅本机增量游标，恢复备份时不复制。 */
  statsBaseline: number = 0;
}

export class MedalAccountStore {
  version: number = 2;
  legacyClaimed: boolean = false;
  lastOwnerKey: string = '';
  profiles: MedalSnapshot[] = [];
}
