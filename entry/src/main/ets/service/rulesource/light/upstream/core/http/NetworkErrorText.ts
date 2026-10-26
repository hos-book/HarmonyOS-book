/**
 * 把请求层的网络错误翻成给读者看的原因（原生与兼容书源共用）。只识别明确属于网络层的失败（域名解析、超时、连不上、
 * 安全连接、空响应）：这些情况与登录无关，不能再交给“需要登录或网页验证”的判定。
 * 认不出的错误返回空串，由调用方按原有逻辑处理。
 */
export class NetworkErrorText {
  static describe(error: string, url: string): string {
    const text = error || '';
    if (!text) return '';
    const host = NetworkErrorText.hostOf(url);
    const target = host || '服务器';
    if (/2300016|http\/?2.*(?:error|failed)|framing layer|curl(?:_|\s*)code\s*(?:result\s*)?[=:]?\s*92\b/i.test(text)) {
      return `与 ${target} 的 HTTP/2 传输异常，可尝试开启 HTTP/1.1 兼容模式`;
    }
    if (/2300999|internal error/i.test(text)) {
      return `访问 ${target} 时发生网络内部错误，请重试或尝试 HTTP/1.1 兼容模式`;
    }
    if (/2300006|resolve\s+(the\s+)?host|could\s*n['o]?t\s+resolve|name\s+does\s+not\s+resolve/i.test(text)) {
      return `无法解析域名 ${target}，请检查网络或代理`;
    }
    if (/2300028|operation\s+timeout|timed?\s*out|timeout/i.test(text)) {
      return `连接 ${target} 超时，请检查网络`;
    }
    if (/2300007|could\s*n['o]?t\s+connect|connection\s+refused|failed\s+to\s+connect|network\s+is\s+unreachable/i.test(text)) {
      return `无法连接 ${target}，请检查网络或代理`;
    }
    if (/2300035|2300060|ssl|tls|certificate/i.test(text)) {
      return `与 ${target} 建立安全连接失败`;
    }
    if (/connection\s+reset/i.test(text)) {
      return `与 ${target} 的连接被重置，请稍后重试`;
    }
    if (/2300056|recv\s+failure|failed\s+to\s+receive/i.test(text)) {
      return `接收 ${target} 的数据失败，请稍后重试`;
    }
    if (/2300052|empty\s+reply/i.test(text)) {
      return `${target} 没有返回数据，请稍后重试`;
    }
    return '';
  }

  static hostOf(url: string): string {
    const match = /^[a-z][a-z0-9+.-]*:\/\/([^/?#,\s]+)/i.exec((url || '').trim());
    if (!match) return '';
    const authority = match[1];
    const at = authority.lastIndexOf('@');
    return (at >= 0 ? authority.substring(at + 1) : authority).replace(/:\d+$/, '');
  }
}
