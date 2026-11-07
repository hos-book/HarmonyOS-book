/** 段评坐标始终基于规范化正文，不把地址和脚本放入阅读/朗读文本。 */
export class ReaderParagraphComment {
  offset: number = 0;
  label: string = '';
  url: string = '';
  title: string = '';
}

export class ReaderCommentChapter {
  content: string = '';
  comments: ReaderParagraphComment[] = [];
  /** 区分旧纯文本缓存与已查询但没有段评的章节。 */
  commentsLoaded: boolean = false;
}

export class ReaderCommentMessage {
  id: string = '';
  author: string = '';
  avatar: string = '';
  text: string = '';
  time: string = '';
  likes: string = '';
  replyTo: string = '';
}

export class ReaderCommentMessages {
  items: ReaderCommentMessage[] = [];
  empty: boolean = false;
}
