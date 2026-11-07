/** 段评网页没有平台桥；原生内联页面仅允许宿主生成的离线文档。 */
export class ReaderCommentWebPolicy {
  static remote(url: string): boolean { return /^https?:\/\/[^\s/]+/i.test(url); }

  static navigation(url: string, offline: boolean, mainFrame: boolean, documentBase64: string): boolean {
    if (url === 'about:blank' || url === 'about:srcdoc') return true;
    if (!offline) return ReaderCommentWebPolicy.remote(url);
    if (!mainFrame || !documentBase64) return false;
    const comma = url.indexOf(',');
    return comma > 0 && /^data:text\/html(?:;charset=[a-z0-9_-]+)?;base64$/i.test(url.substring(0, comma)) &&
      url.substring(comma + 1) === documentBase64;
  }
}
