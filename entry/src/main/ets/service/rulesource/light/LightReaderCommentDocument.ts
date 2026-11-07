import { NativeCommentPage } from './upstream/core/nativesource/NativeCommentPage';

/** 将书源段评转成只含展示字段的 JSON，不添加站点接口或执行额外书源动作。 */
export class LightReaderCommentDocument {
  static formatTime(value: string): string {
    if (!/^\d{10,13}$/.test(value)) return value;
    const number = Number(value);
    const date = new Date(number < 1000000000000 ? number * 1000 : number);
    if (!Number.isFinite(date.getTime())) return '';
    const pad = (part: number): string => String(part).padStart(2, '0');
    return date.getFullYear() + '-' + pad(date.getMonth() + 1) + '-' + pad(date.getDate()) +
      ' ' + pad(date.getHours()) + ':' + pad(date.getMinutes());
  }

  static parse(raw: string): string {
    const items: Record<string, string>[] = [];
    let empty = false;
    const seen = new Set<string>();
    let remaining = 3000;
    const field = (record: Record<string, Object>, keys: string[]): string => {
      for (const key of keys) {
        const value = record[key];
        if (typeof value === 'string' || typeof value === 'number') return String(value).trim();
      }
      return '';
    };
    const plain = (value: string): string => value.replace(/<br\s*\/?>/gi, '\n').replace(/<[^>]*>/g, '')
      .replace(/&nbsp;/g, ' ').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&amp;/g, '&').trim();
    const walk = (value: Object, depth: number, list: boolean, parent: string): void => {
      if (!value || depth > 7 || --remaining < 0 || items.length >= 200) return;
      if (Array.isArray(value)) {
        if (list && value.length === 0) empty = true;
        for (const child of value.slice(0, 200)) walk(child, depth + 1, true, parent);
        return;
      }
      if (typeof value !== 'object') return;
      const record = value as Record<string, Object>;
      const text = list ? plain(field(record, ['text', 'content', 'commentContent', 'comment_content', 'reviewContent', 'body', 'Content'])).slice(0, 8000) : '';
      if (text) {
        const userValue = record.user || record.userInfo || record.user_info || record.author || record.UserInfo;
        const user = userValue && typeof userValue === 'object' && !Array.isArray(userValue) ? userValue as Record<string, Object> : {};
        const author = plain(field(record, ['authorName', 'nickname', 'nickName', 'userName', 'username', 'NickName']) ||
          field(user, ['nickname', 'nickName', 'name', 'userName', 'username', 'NickName']) ||
          (typeof record.author === 'string' ? record.author : '')).slice(0, 96);
        const avatar = field(record, ['avatar', 'avatarUrl', 'avatar_url', 'headImg', 'headimgurl']) ||
          field(user, ['avatar', 'avatarUrl', 'avatar_url', 'headImg', 'headimgurl', 'HeadImage']);
        const identity = author + '\n' + text;
        let hash = 2166136261;
        for (let i = 0; i < identity.length; i++) hash = Math.imul(hash ^ identity.charCodeAt(i), 16777619);
        const id = field(record, ['id', 'commentId', 'comment_id', 'reviewId']) || (hash >>> 0).toString(36);
        if (!seen.has(id)) {
          seen.add(id);
          items.push({ id, author, text, avatar: /^https?:\/\//i.test(avatar) && avatar.length <= 2048 ? avatar : '',
            time: LightReaderCommentDocument.formatTime(field(record, ['time', 'createTime', 'createdAt', 'create_time', 'date', 'publishTime']).slice(0, 80)),
            likes: field(record, ['likes', 'likeCount', 'like_count', 'digg_count', 'agreeCount']).slice(0, 16),
            replyTo: plain(field(record, ['replyTo', 'reply_to_name']) || parent).slice(0, 96) });
        }
        for (const key of ['replies', 'replyList', 'reply_list', 'children']) {
          if (record[key]) walk(record[key], depth + 1, true, author);
        }
        return;
      }
      for (const key of ['items', 'comments', 'commentList', 'comment_list', 'reviews', 'reviewList', 'review_list', 'list', 'rows', 'data', 'result']) {
        if (record[key]) walk(record[key], depth + 1, key !== 'data' && key !== 'result', parent);
      }
      if (typeof record.empty === 'boolean') empty = record.empty;
    };
    try {
      if (raw && raw.length <= 1024 * 1024) walk(JSON.parse(raw), 0, false, '');
    } catch (_) { /* 网页或文本结果不冒充 JSON 评论 */ }
    return JSON.stringify({ items, empty: items.length === 0 && empty });
  }

  /** 固定只读 DOM 采集脚本，不读取 Cookie、存储或页面脚本变量。 */
  static readonly COLLECT: string = String.raw`(() => {
    if (window.__READER_COMMENT_ITEMS__) return JSON.stringify(window.__READER_COMMENT_ITEMS__);
    const pick=(root,selectors)=>{for(const s of selectors){const n=root.querySelector(s);if(n)return n;}return null;};
    const text=n=>(n&&(n.innerText||n.textContent)||'').trim();
    const bodies=['[data-comment-content]','.comment-content','.commentContent','.comment-text','.review-content','.review-text','.content','.text','.body','[itemprop="text"]'];
    const authors=['[data-author]','.nickname','.nick-name','.nickName','.user-name','.username','.userName','.author','.name','[itemprop="author"]'];
    const selectors=['[data-comment-id]','.comment-item','.commentItem','.review-item','.reviewItem','.comment-card','.comment_card','.comment','.review','.item'];
    let rows=[];
    for(const selector of selectors){
      const candidates=Array.from(document.querySelectorAll(selector)).slice(0,400).filter(n=>pick(n,bodies)&&pick(n,authors));
      if(candidates.length){rows=candidates;break;}
    }
    const items=[];
    for(const row of rows.slice(0,200)){
      const content=pick(row,bodies),author=pick(row,authors),avatar=pick(row,['img.avatar','.avatar img','.user-avatar img','.head img','img']);
      if(!content||content===author||content.contains(author))continue;
      const value=text(content).slice(0,8000);if(!value)continue;
      const picture=avatar&&(avatar.currentSrc||avatar.src)||'';
      items.push({id:row.getAttribute('data-comment-id')||row.id||'',authorName:text(author).slice(0,96),text:value,
        avatar:/^https?:\/\//i.test(picture)?picture:'',time:text(pick(row,['time','.time','.date','.create-time','.publish-time'])).slice(0,80),
        likes:text(pick(row,['.like-count','.likes','.likeCount','.praise-count'])).slice(0,16),
        replyTo:text(pick(row,['.reply-to','.replyTo'])).slice(0,96)});
    }
    const empty=items.length===0&&/暂无(?:段评|评论)|还没有评论|暂时没有评论|no comments/i.test(text(document.body).slice(0,12000));
    return JSON.stringify({items,empty});
  })()`;

  static nativeDocument(page: NativeCommentPage): string {
    const copy = new NativeCommentPage();
    copy.html = page.html + '<script>addEventListener("DOMContentLoaded",()=>{let remaining=40;const collect=()=>{' +
      'const value=' + LightReaderCommentDocument.COLLECT + ';parent.postMessage({type:"reader-comments",value},"*");' +
      'if(--remaining>0)setTimeout(collect,250);};collect();});</script>';
    copy.dataJson = page.dataJson;
    const document = NativeCommentPage.document(copy);
    return document.replace('</body>', '<script>addEventListener("message",e=>{' +
      'const frame=document.getElementById("native-comment-content");' +
      'if(!frame||e.source!==frame.contentWindow||!e.data||e.data.type!=="reader-comments"||' +
      'typeof e.data.value!=="string"||e.data.value.length>1048576)return;' +
      'try{window.__READER_COMMENT_ITEMS__=JSON.parse(e.data.value)}catch(_){}});</script></body>');
  }
}
