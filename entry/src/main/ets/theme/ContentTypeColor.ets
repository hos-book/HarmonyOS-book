/** 书架封面类型角标与阅听统计共用同一配色。 */
export class ContentTypeColor {
  static readonly Comic: ResourceColor = '#CC8E5BB7';
  static readonly Text: ResourceColor = '#CC4E7FA8';
  static readonly Audio: ResourceColor = '#CCFF8800';

  static of(contentType: string): ResourceColor {
    return contentType === 'comic' ? ContentTypeColor.Comic :
      contentType === 'audio' ? ContentTypeColor.Audio : ContentTypeColor.Text;
  }

  /** 统计图沿用封面类型色相，降低饱和度，避免橙色柱抢占页面视觉。 */
  static chartOf(contentType: string): ResourceColor {
    return contentType === 'comic' ? $r('app.color.record_chart_comic') :
      contentType === 'audio' ? $r('app.color.record_chart_audio') : $r('app.color.record_chart_reading');
  }
}
