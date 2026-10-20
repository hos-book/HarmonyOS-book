import { RuleSourceLoginRouteParams } from '../../model/RuleSourceLogin';

export type LocalRuleBrowserLoginOpener = (route: RuleSourceLoginRouteParams) => void;
export type LocalRuleBrowserLoginCancel = (reason: string) => Promise<void>;

class LocalRuleBrowserLoginPending {
  route: RuleSourceLoginRouteParams = new RuleSourceLoginRouteParams();
  timer: number = -1;
  closing: boolean = false;
  resolve: (html: string) => void = (_html: string): void => {};
  reject: (error: Error) => void = (_error: Error): void => {};
  closePage: LocalRuleBrowserLoginCancel | undefined = undefined;
  scopeId: number = 0;
}

class LocalRuleBrowserLoginScope {
  id: number = 0;
  sourceUrl: string = '';
  cancelledReason: string = '';
  timer: number = -1;
}

/** Only the routed incognito login page can complete a waiting browser action. */
export class LocalRuleBrowserLoginCoordinator {
  static readonly MAX_HTML_LENGTH: number = 512 * 1024;
  private static readonly TIMEOUT_MS: number = 120000;
  private static readonly SCOPE_TIMEOUT_MS: number = 180000;
  private static readonly MAX_SCOPES: number = 128;
  private static sequence: number = 0;
  private static scopeSequence: number = 0;
  private static opener: LocalRuleBrowserLoginOpener | undefined = undefined;
  private static pending: LocalRuleBrowserLoginPending | undefined = undefined;
  private static scopes: Map<number, LocalRuleBrowserLoginScope> = new Map<number, LocalRuleBrowserLoginScope>();

  static openScope(sourceUrl: string): number {
    if (LocalRuleBrowserLoginCoordinator.scopes.size >= LocalRuleBrowserLoginCoordinator.MAX_SCOPES) {
      throw new Error('书源任务取消作用域超过上限');
    }
    const scope = new LocalRuleBrowserLoginScope();
    scope.id = ++LocalRuleBrowserLoginCoordinator.scopeSequence;
    scope.sourceUrl = sourceUrl.trim();
    scope.timer = setTimeout((): void => {
      LocalRuleBrowserLoginCoordinator.cancelScope(scope.id, '书源任务已超时');
      LocalRuleBrowserLoginCoordinator.closeScope(scope.id);
    }, LocalRuleBrowserLoginCoordinator.SCOPE_TIMEOUT_MS);
    LocalRuleBrowserLoginCoordinator.scopes.set(scope.id, scope);
    return scope.id;
  }

  static cancelScope(scopeId: number, reason: string): void {
    const scope = LocalRuleBrowserLoginCoordinator.scopes.get(scopeId);
    if (scope === undefined) return;
    scope.cancelledReason = reason || '书源任务已取消';
    const pending = LocalRuleBrowserLoginCoordinator.pending;
    if (pending !== undefined && pending.scopeId === scopeId) {
      LocalRuleBrowserLoginCoordinator.cancel(pending.route.requestId, scope.cancelledReason);
    }
  }

  static closeScope(scopeId: number): void {
    const scope = LocalRuleBrowserLoginCoordinator.scopes.get(scopeId);
    if (scope === undefined) return;
    clearTimeout(scope.timer);
    LocalRuleBrowserLoginCoordinator.scopes.delete(scopeId);
  }

  private static sourceScope(sourceUrl: string): LocalRuleBrowserLoginScope | undefined {
    // Same-source scripts run serially; the first active task owns its browser actions.
    for (const scope of LocalRuleBrowserLoginCoordinator.scopes.values()) {
      if (scope.sourceUrl === sourceUrl) return scope;
    }
    return undefined;
  }

  static bindNavigation(opener: LocalRuleBrowserLoginOpener): void {
    LocalRuleBrowserLoginCoordinator.opener = opener;
  }

  static unbindNavigation(opener: LocalRuleBrowserLoginOpener): void {
    if (LocalRuleBrowserLoginCoordinator.opener !== opener) return;
    LocalRuleBrowserLoginCoordinator.opener = undefined;
    const pending = LocalRuleBrowserLoginCoordinator.pending;
    if (pending !== undefined) LocalRuleBrowserLoginCoordinator.cancel(pending.route.requestId, '网页登录页面已关闭');
  }

  static request(sourceUrl: string, sourceName: string, address: string, browserHtml: string = '',
    injectJs: string = ''): Promise<string> {
    const route = RuleSourceLoginRouteParams.of(sourceUrl, sourceName || sourceUrl, address);
    if (!route.isValid()) return Promise.reject(new Error('等待网页登录仅支持有效的 HTTPS 地址'));
    const scope = LocalRuleBrowserLoginCoordinator.sourceScope(route.sourceUrl);
    if (scope !== undefined && scope.cancelledReason.length > 0) {
      return Promise.reject(new Error(scope.cancelledReason));
    }
    if (browserHtml.length > LocalRuleBrowserLoginCoordinator.MAX_HTML_LENGTH) {
      return Promise.reject(new Error('网页登录内容超过输入大小限制'));
    }
    route.initialHtml = browserHtml;
    route.injectJs = injectJs;
    if (LocalRuleBrowserLoginCoordinator.pending !== undefined) {
      return Promise.reject(new Error('已有等待中的网页登录，请先完成或取消'));
    }
    const opener = LocalRuleBrowserLoginCoordinator.opener;
    if (opener === undefined) return Promise.reject(new Error('网页登录导航尚未就绪'));
    route.requestId = `browser-login-${++LocalRuleBrowserLoginCoordinator.sequence}`;
    return new Promise<string>((resolve, reject) => {
      const pending = new LocalRuleBrowserLoginPending();
      pending.route = route;
      pending.scopeId = scope?.id ?? 0;
      pending.resolve = resolve;
      pending.reject = reject;
      LocalRuleBrowserLoginCoordinator.pending = pending;
      pending.timer = setTimeout(() => {
        LocalRuleBrowserLoginCoordinator.cancel(route.requestId, '等待网页登录超时');
      }, LocalRuleBrowserLoginCoordinator.TIMEOUT_MS);
      try { opener(route); }
      catch (error) {
        LocalRuleBrowserLoginCoordinator.reject(route.requestId,
          error instanceof Error ? error.message : '无法打开网页登录页面');
      }
    });
  }

  static open(sourceUrl: string, sourceName: string, address: string): void {
    const route = RuleSourceLoginRouteParams.of(sourceUrl, sourceName || sourceUrl, address);
    if (!route.isValid()) throw new Error('网页登录仅支持有效的 HTTPS 地址');
    if (LocalRuleBrowserLoginCoordinator.pending !== undefined) throw new Error('请先完成当前网页登录');
    const opener = LocalRuleBrowserLoginCoordinator.opener;
    if (opener === undefined) throw new Error('网页登录导航尚未就绪');
    opener(route);
  }

  static attach(requestId: string, closePage: LocalRuleBrowserLoginCancel): boolean {
    const pending = LocalRuleBrowserLoginCoordinator.pending;
    if (pending === undefined || pending.route.requestId !== requestId || pending.closing) return false;
    pending.closePage = closePage;
    return true;
  }

  static isPending(requestId: string): boolean {
    const pending = LocalRuleBrowserLoginCoordinator.pending;
    return pending !== undefined && pending.route.requestId === requestId && !pending.closing;
  }

  static resolve(requestId: string, html: string): void {
    const pending = LocalRuleBrowserLoginCoordinator.pending;
    if (pending === undefined || pending.route.requestId !== requestId || pending.closing) return;
    LocalRuleBrowserLoginCoordinator.clear(pending);
    if (html.length > LocalRuleBrowserLoginCoordinator.MAX_HTML_LENGTH) {
      pending.reject(new Error('网页登录内容超过返回大小限制'));
    } else { pending.resolve(html); }
  }

  static reject(requestId: string, reason: string): void {
    const pending = LocalRuleBrowserLoginCoordinator.pending;
    if (pending === undefined || pending.route.requestId !== requestId || pending.closing) return;
    LocalRuleBrowserLoginCoordinator.clear(pending);
    pending.reject(new Error(reason || '网页登录已取消'));
  }

  static cancelForSource(sourceUrl: string, reason: string): void {
    const pending = LocalRuleBrowserLoginCoordinator.pending;
    if (pending !== undefined && pending.route.sourceUrl === sourceUrl) {
      LocalRuleBrowserLoginCoordinator.cancel(pending.route.requestId, reason);
    }
  }

  private static cancel(requestId: string, reason: string): void {
    const pending = LocalRuleBrowserLoginCoordinator.pending;
    if (pending === undefined || pending.route.requestId !== requestId || pending.closing) return;
    pending.closing = true;
    clearTimeout(pending.timer);
    pending.reject(new Error(reason));
    const closePage = pending.closePage;
    if (closePage === undefined) {
      LocalRuleBrowserLoginCoordinator.clear(pending);
      return;
    }
    // Keep the slot occupied until cookies and the shared Web lease have been released.
    closePage(reason).catch((): void => {}).finally((): void => {
      LocalRuleBrowserLoginCoordinator.clear(pending);
    });
  }

  private static clear(pending: LocalRuleBrowserLoginPending): void {
    clearTimeout(pending.timer);
    if (LocalRuleBrowserLoginCoordinator.pending === pending) LocalRuleBrowserLoginCoordinator.pending = undefined;
  }
}
