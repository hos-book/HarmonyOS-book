export enum ReaderAiAction {
  Dictionary = 'dictionary',
  Summarize = 'summarize'
}

export class ReaderAiRequest {
  action: ReaderAiAction = ReaderAiAction.Dictionary;
  chapterIndex: number = -1;
  chapterTitle: string = '';
  text: string = '';
}
