/** Portable inline-page contracts and rendering policy, shared by the reader and source debugger. */
export class NativeCommentPage {
  static readonly SCHEME: string = 'legado-native-page:';
  static readonly MAX_HTML: number = 256 * 1024;
  static readonly MAX_DATA: number = 64 * 1024;
  html: string = '';
  dataJson: string = '{}';
  title: string = '评论';
  height: number = 0.8;
  fallbackUrl: string = '';
  error: string = '';

  static isAction(url: string): boolean { return (url || '').startsWith(NativeCommentPage.SCHEME); }

  /** UTF-8 bytes, including replacement characters for lone UTF-16 surrogates. */
  static bytes(text: string): number {
    let size = 0;
    for (let i = 0; i < text.length; i++) {
      const code = text.charCodeAt(i);
      if (code < 128) size++;
      else if (code < 2048) size += 2;
      else if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length &&
        text.charCodeAt(i + 1) >= 0xdc00 && text.charCodeAt(i + 1) <= 0xdfff) { size += 4; i++; }
      else size += 3;
    }
    return size;
  }

  /** The source document runs inside an opaque sandbox, never in the trusted outer document. */
  static contentDocument(page: NativeCommentPage): string {
    if (NativeCommentPage.bytes(page.html) > NativeCommentPage.MAX_HTML ||
      NativeCommentPage.bytes(page.dataJson) > NativeCommentPage.MAX_DATA) throw new Error('内联页面超出大小上限');
    const json = JSON.stringify(JSON.parse(page.dataJson)).replace(/</g, '\\u003c')
      .replace(/>/g, '\\u003e').replace(/&/g, '\\u0026').replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
    const policy = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; " +
      "img-src data:; connect-src 'none'; frame-src 'none'; child-src 'none'; worker-src 'none'; " +
      "object-src 'none'; base-uri 'none'; form-action 'none'";
    return '<!doctype html><html><head><meta charset="UTF-8">' +
      '<meta http-equiv="Content-Security-Policy" content="' + policy + '">' +
      '<meta name="viewport" content="width=device-width,initial-scale=1">' +
      // CSP connect-src does not cover WebRTC ICE. Disable its constructors before any source script runs.
      '<script>for(const k of ["RTCPeerConnection","webkitRTCPeerConnection"]){' +
      'Object.defineProperty(window,k,{value:undefined,writable:false,configurable:false});}' +
      'window.__QM_DATA__=' + json + ';window.__NATIVE_PAGE_DATA__=window.__QM_DATA__;</script>' +
      '</head><body>' + page.html + '</body></html>';
  }

  /** Loaded only with about:blank in a separate incognito Web, with network/file access disabled. */
  static document(page: NativeCommentPage, generation: number = 0): string {
    const content = NativeCommentPage.contentDocument(page).replace(/&/g, '&amp;').replace(/"/g, '&quot;')
      .replace(/</g, '&lt;').replace(/>/g, '&gt;');
    // allow-same-origin is deliberately absent. Even a newly created blank subframe has a distinct
    // opaque origin: source JS cannot borrow its unmodified WebRTC constructors or reach this parent.
    return '<!doctype html><html><head><meta charset="UTF-8">' +
      '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; script-src \'unsafe-inline\'; ' +
      'style-src \'unsafe-inline\'; frame-src \'self\'; child-src \'self\'; img-src data:; ' +
      'connect-src \'none\'; worker-src \'none\'; object-src \'none\'; base-uri \'none\'; form-action \'none\'">' +
      '<meta name="viewport" content="width=device-width,initial-scale=1">' +
      '<style>html,body,iframe{margin:0;padding:0;width:100%;height:100%;border:0;display:block;overflow:hidden}</style>' +
      '<script>window.__NATIVE_PAGE_READY__=false;window.__NATIVE_PAGE_GENERATION__=' + Math.floor(generation) + ';</script></head><body>' +
      '<iframe id="native-comment-content" sandbox="allow-scripts" ' +
      'onload="window.__NATIVE_PAGE_READY__=true" srcdoc="' + content + '"></iframe></body></html>';
  }
}
