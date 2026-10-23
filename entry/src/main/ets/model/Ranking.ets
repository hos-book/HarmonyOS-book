/** 发现元数据，不能直接用于详情、目录或播放分发。 */
export class RankingBook {
  id: string = '';
  platformId: string = '';
  title: string = '';
  author: string = '';
  narrator: string = '';
  contentType: 'text' | 'audio' = 'text';
  coverUrl: string = '';
  originalUrl: string = '';
  intro: string = '';
  rank: number = 0;
  rating: number = 0;
}

export class RankingBoard {
  id: string;
  platformId: string;
  platformName: Resource;
  title: Resource;
  endpoint: string;
  books: RankingBook[] = [];
  fetchedAt: number = 0;
  unavailable: boolean = false;
  stale: boolean = false;

  constructor(id: string, platformId: string, platformName: Resource, title: Resource, endpoint: string) {
    this.id = id;
    this.platformId = platformId;
    this.platformName = platformName;
    this.title = title;
    this.endpoint = endpoint;
  }
}

export class RankingPlatform {
  id: string;
  name: Resource;
  constructor(id: string, name: Resource) {
    this.id = id;
    this.name = name;
  }
}
