/**
 * 音频来源抽象
 * rawfile: 资源文件名（已不再使用，保留以便未来内置音频）
 * url: 网络流地址
 * file: 本地导入沙箱路径
 */
export interface AudioSource {
  type: 'rawfile' | 'url' | 'file';
  value: string;
}

export interface Chapter {
  id: string;
  index: number;
  title: string;
  duration: number;
  source: AudioSource;
  /** 章节页 URL（用于解析音频时调 BookSourceService.getAudioUrl）。
   *  source.value 在播放期间会被解析后的真实音频 URL 覆盖，
   *  此字段保留原始章节页 URL，重启/续播时可以重新解析（避免临时签名链接过期）。 */
  originSourceValue?: string;
  /** 本地规则源在目录阶段为当前章节生成的独立解析上下文。 */
  variables?: Record<string, string>;
}

export interface Book {
  id: string;
  /** 内容类型：audio=有声书；text=电子书；comic=漫画图片章节。 */
  contentType?: 'audio' | 'text' | 'comic';
  title: string;
  author: string;
  narrator: string;
  cover: string;
  /** 详情规则返回的封面优先于后续搜索缩略图；旧数据未设置时按普通封面处理。 */
  coverFromDetail?: boolean;
  /** 详情封面加载失败时可回退的搜索封面。 */
  coverFallback?: string;
  category: string;
  intro: string;
  /** 保留书源返回的文本，不将字数误当作目录章节数。 */
  wordCount?: string;
  latestChapterTitle?: string;
  updateTime?: string;
  totalDuration: number;
  chapterCount: number;
  rating: number;
  tags: string[];
  chapters: Chapter[];
  /** false 表示在线目录尚未完整获取；部分目录不得覆盖持久目录。旧缓存未设置时按原规则判断。 */
  tocComplete?: boolean;
  bookUrl: string;
  sourceUrl: string;
  variables?: Record<string, string>;
  /** 跳过片头秒数（每本书独立设置） */
  skipIntro?: number;
  /** 跳过片尾秒数（每本书独立设置） */
  skipOutro?: number;
  /** 目录倒序（每本书独立设置）：仅影响目录展示，不改变阅读和播放的章节顺序 */
  chaptersDescending?: boolean;
  /** 是否完结；由通用规则或来源返回的状态归一化。 */
  completed?: boolean;
}
