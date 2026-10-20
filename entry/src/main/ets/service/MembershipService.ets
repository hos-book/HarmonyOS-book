import lazy { PreferenceService } from './PreferenceService';
import lazy { AutoBackupService } from './AutoBackupService';
import { DeveloperMembership } from './membership/DeveloperMembership';
import lazy { iap } from '@kit.IAPKit';
import lazy { authentication } from '@kit.AccountKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MembershipState } from '../model/MembershipState';
import { PlatformCompat } from '../utils/PlatformCompat';
import { AppIconService } from './AppIconService';
import { SubscriptionOrder, SubscriptionPayload, SubscriptionPolicy, SubscriptionStatus } from './membership/SubscriptionData';
import { SubscriptionVerifier } from './membership/SubscriptionVerifier';
import { LifetimeOrder, LifetimePolicy } from './membership/LifetimeData';
import { MembershipDisplaySnapshot } from '../model/MembershipDisplaySnapshot';
import { MembershipDisplayStore } from './membership/MembershipDisplayStore';

export class MembershipPlan {
  id: string;
  price: string;
  groupId: string;
  constructor(product: iap.Product) {
    this.id = product.id;
    this.price = product.localPrice || product.price;
    this.groupId = product.subscriptionInfo?.groupId || '';
  }
}

class MembershipTimeout extends Error implements BusinessError {
  code: number = -2;
  constructor() { super('IAP request timed out'); }
}

/** 无自有服务器：每次查询都向华为获取凭据，在本机验签，不持久化 VIP 布尔值。 */
@ObservedV2
export class MembershipService {
  private static singleton: MembershipService | null = null;
  static get instance(): MembershipService {
    if (!MembershipService.singleton) MembershipService.singleton = new MembershipService();
    return MembershipService.singleton;
  }
  @Trace plans: MembershipPlan[] = [];
  @Trace busy: boolean = false;
  @Trace message: Resource = $r('app.string.membership_checking');
  @Trace productsMessage: Resource = $r('app.string.membership_products_loading');
  @Trace confirmationPending: boolean = false;
  private refreshTask: Promise<void> | null = null;
  @Trace productsLoading: boolean = false;
  private productsTask: Promise<void> | null = null;
  private productsAt: number = 0;
  private productsQueryAt: number = 0;
  private queryAt: number = 0;
  private queryTask: Promise<void> = Promise.resolve();
  private refreshedAt: number = 0;
  private expiryTimer: number = -1;
  private allowSandbox: boolean = false;
  private sandboxChecked: boolean = false;
  private sandboxTask: Promise<void> | null = null;
  private inForeground: boolean = true;
  private abilityContext: common.UIAbilityContext | null = null;
  private displayRestoreStarted: boolean = false;
  private displayRevision: number = 0;
  private displayWriteTask: Promise<void> = Promise.resolve();
  private purchaseInProgress: boolean = false;
  private awaitingPurchaseForeground: boolean = false;
  private purchaseReturnUntil: number = 0;
  private recoverRequested: boolean = false;
  private entitlementRevision: number = 0;
  private confirmationTask: Promise<void> = Promise.resolve();
  private recoveryTask: Promise<void> | null = null;
  private finishedOrders: Set<string> = new Set<string>();
  private verifiedAccountId: string = '';
  private accountCheckPending: boolean = false;
  private forceRefreshRequested: boolean = false;

  private async restoreDisplay(context: common.UIAbilityContext): Promise<void> {
    if (this.displayRestoreStarted) return;
    this.displayRestoreStarted = true;
    const revision = this.displayRevision;
    try {
      const snapshot = await MembershipDisplayStore.read(context);
      // 联网结果始终优先，迟到的磁盘读取不能恢复已撤销的展示。
      if (revision === this.displayRevision && !MembershipState.current.active &&
        !MembershipState.current.confirmedInactive) MembershipState.current.restoreDisplay(snapshot);
    } catch (_error) { /* 缓存损坏或读取失败不影响真实会员核验。 */ }
  }

  private persistDisplay(context: common.UIAbilityContext, snapshot: MembershipDisplaySnapshot | null): Promise<void> {
    this.displayRevision++;
    MembershipState.current.restoreDisplay(snapshot);
    this.displayWriteTask = this.displayWriteTask.then((): Promise<void> =>
      MembershipDisplayStore.write(context, snapshot)).catch((): void => {
      hilog.warn(0x0000, 'MembershipService', 'Membership display cache could not be saved');
    });
    return this.displayWriteTask;
  }

  /** 共用已验签权益；到期、换号或核验失败时不放行新的会员操作。 */
  async hasCurrentEntitlement(): Promise<boolean> {
    if (MembershipState.current.hasAccess) return true;
    const context = this.abilityContext;
    if (!context || !this.supported) return false;
    await this.refresh(context);
    return MembershipState.current.hasAccess;
  }

  get supported(): boolean {
    return MembershipState.featureEnabled && !PlatformCompat.wearable && canIUse('SystemCapability.Payment.IAP');
  }

  private bounded<T>(operation: Promise<T>, timeout: number = 20000): Promise<T> {
    return new Promise<T>((resolve, reject): void => {
      const timer = setTimeout((): void => { reject(new MembershipTimeout()); }, timeout);
      operation.then((result: T): void => { clearTimeout(timer); resolve(result); },
        (error: BusinessError): void => { clearTimeout(timer); reject(error); });
    });
  }

  /** 回前台先在本机核对账号，未换号且权益仍有效时复用本进程已验签结果。 */
  foreground(context: common.UIAbilityContext): void {
    this.abilityContext = context;
    if (!MembershipState.featureEnabled) return;
    MembershipState.current.developerAccess = DeveloperMembership.allowed(context.applicationInfo.debug);
    this.inForeground = true;
    if (this.purchaseInProgress) {
      return;
    }
    const state = MembershipState.current;
    const now = Date.now();
    const returningFromPurchase = this.awaitingPurchaseForeground && state.hasAccess &&
      now >= state.verifiedAt && now < this.purchaseReturnUntil;
    this.awaitingPurchaseForeground = false;
    this.purchaseReturnUntil = 0;
    // 收银台的前台事件可能晚于购买回调；只消费这一次返回，采用刚验签的购买凭据。
    if (returningFromPurchase) {
      this.scheduleRefresh(context);
      return;
    }
    if (this.busy && !this.refreshTask) return;
    this.accountCheckPending = true;
    // 本地账号检查期间保留展示，不进入页面 busy；会员操作合并等待这次检查。
    state.revalidating = true;
    this.refresh(context).catch((): void => {});
  }

  async load(context: common.UIAbilityContext, restore: boolean = false): Promise<void> {
    // 价格不依赖权益查询；两个请求各自合并，慢价格不会锁住会员操作。
    await Promise.all([this.refresh(context, restore, restore), this.loadProducts(context, restore)]);
  }

  private async loadProducts(context: common.UIAbilityContext, force: boolean = false): Promise<void> {
    if (!this.supported) return;
    if (this.productsTask) return this.productsTask;
    const age = Date.now() - this.productsAt;
    if (!force && this.productsAt > 0 && age >= 0 && age < 5 * 60 * 1000) return;
    this.productsLoading = true;
    this.productsMessage = $r('app.string.membership_products_loading');
    this.productsTask = this.loadProductsInner(context).finally((): void => {
      this.productsLoading = false;
      this.productsTask = null;
    });
    return this.productsTask;
  }

  private async loadProductsInner(context: common.UIAbilityContext): Promise<void> {
    try {
      const delay = Math.max(0, this.productsQueryAt + 5100 - Date.now());
      if (delay > 0) await new Promise<void>((resolve): void => { setTimeout(resolve, delay); });
      this.productsQueryAt = Date.now();
      await this.bounded(iap.queryEnvironmentStatus(context));
      await this.checkSandbox(context);
      // API 20 起支持跨商品类型批量查询，最低支持版本已覆盖。
      const products = await this.bounded(iap.queryProducts(context,
        [SubscriptionPolicy.month, SubscriptionPolicy.year, LifetimePolicy.product]));
      const plans: MembershipPlan[] = [];
      for (const product of products) {
        if ((product.status !== undefined && product.status !== iap.ProductStatus.VALID) ||
          !(product.localPrice || product.price)) continue;
        if (product.id === LifetimePolicy.product && product.type === iap.ProductType.NONCONSUMABLE) {
          plans.push(new MembershipPlan(product));
          continue;
        }
        const info = product.subscriptionInfo;
        if (!SubscriptionPolicy.knownProduct(product.id) || product.type !== iap.ProductType.AUTORENEWABLE ||
          !info || !info.groupId) continue;
        const expected = product.id === SubscriptionPolicy.month ? iap.PeriodUnit.MONTH : iap.PeriodUnit.YEAR;
        if ((info.periodUnit !== expected || info.periodCount !== 1) &&
          !(this.allowSandbox && info.periodUnit === iap.PeriodUnit.MINUTE)) continue;
        plans.push(new MembershipPlan(product));
      }
      const subscriptions = plans.filter((plan: MembershipPlan): boolean => plan.id !== LifetimePolicy.product);
      this.plans = subscriptions.length === 2 && subscriptions[0].groupId !== subscriptions[1].groupId ?
        plans.filter((plan: MembershipPlan): boolean => plan.id === LifetimePolicy.product) : plans;
      this.productsAt = Date.now();
      this.productsMessage = this.plans.length > 0 ? $r('app.string.membership_price_hint') :
        $r('app.string.membership_products_unavailable');
    } catch (error) {
      this.plans = [];
      this.productsAt = 0;
      this.productsMessage = this.errorMessage(error);
    }
  }

  async refresh(context: common.UIAbilityContext, force: boolean = false, recoverUnfinished: boolean = false): Promise<void> {
    this.abilityContext = context;
    // 暂停会员期间不查 IAP、不清购买展示缓存，也不重置用户已选的功能设置。
    if (!MembershipState.featureEnabled) return;
    MembershipState.current.developerAccess = DeveloperMembership.allowed(context.applicationInfo.debug);
    if (MembershipState.current.developerAccess) {
      this.accountCheckPending = false;
      MembershipState.current.revalidating = false;
      MembershipState.current.confirmedInactive = false;
      this.message = $r('app.string.membership_developer_active');
      return;
    }
    if (!this.supported) {
      this.entitlementRevision++;
      this.accountCheckPending = false;
      this.verifiedAccountId = '';
      MembershipState.current.revalidating = false;
      MembershipState.current.clear();
      MembershipState.current.confirmedInactive = true;
      await this.persistDisplay(context, null);
      await this.resetDefaults(context);
      this.message = $r('app.string.membership_unsupported');
      return;
    }
    this.restoreDisplay(context);
    // 已核验结果先返回，确认发货和恢复历史订单不阻塞新的会员操作。
    if (!force && !this.accountCheckPending && !MembershipState.current.revalidating && this.hasCachedResult()) return;
    if (recoverUnfinished && this.recoveryTask) return this.recoveryTask;
    if (this.refreshTask) {
      if (force) this.forceRefreshRequested = true;
      if (recoverUnfinished) this.recoverRequested = true;
      await this.refreshTask;
      if (recoverUnfinished) await this.confirmationTask;
      return;
    }
    if (this.busy) return;
    this.recoverRequested = recoverUnfinished;
    this.forceRefreshRequested = force;
    const checkingCachedAccount = !force && this.accountCheckPending &&
      this.verifiedAccountId.length > 0 && this.hasCachedResult();
    this.busy = !MembershipState.current.hasAccess && !checkingCachedAccount;
    if (this.busy) this.message = $r('app.string.membership_checking');
    this.refreshTask = this.refreshCurrentAccount(context).catch(async (error: BusinessError): Promise<void> => {
      this.entitlementRevision++;
      this.verifiedAccountId = '';
      // 无有效会员凭据时恢复受限设置；不改变真实购买记录。
      MembershipState.current.clear();
      // 查询失败表示状态未知，不能据此引导用户重新开通。
      MembershipState.current.confirmedInactive = false;
      await this.persistDisplay(context, null);
      await this.resetDefaults(context);
      this.refreshedAt = 0;
      if (this.expiryTimer !== -1) clearTimeout(this.expiryTimer);
      this.expiryTimer = -1;
      this.message = this.errorMessage(error);
    }).finally((): void => {
      MembershipState.current.revalidating = this.accountCheckPending;
      this.forceRefreshRequested = false;
      this.busy = false;
      this.refreshTask = null;
    });
    await this.refreshTask;
    if (recoverUnfinished) await this.confirmationTask;
  }

  private hasCachedResult(): boolean {
    const age = Date.now() - this.refreshedAt;
    return MembershipState.current.active || (MembershipState.current.confirmedInactive &&
      this.refreshedAt > 0 && age >= 0 && age < 60000);
  }

  private async matchesSystemAccount(accountId: string): Promise<boolean> {
    if (!accountId || !canIUse('SystemCapability.AuthenticationServices.HuaweiID.Auth')) return false;
    try {
      const request: authentication.StateRequest = {
        idType: authentication.IdType.OPEN_ID, idValue: accountId
      };
      // API 12 起提供的本地检查，不依赖网络，也不会弹出登录或授权页面。
      const result = await this.bounded(new authentication.HuaweiIDProvider().getHuaweiIDState(request), 2000);
      return result.state === authentication.State.AUTHORIZED;
    } catch (_error) {
      return false;
    }
  }

  private async accountForVerification(context: common.UIAbilityContext): Promise<string> {
    try {
      await PreferenceService.ensureReady(context);
      const account = await PreferenceService.getHwAccount();
      const accountId = account?.openID || this.verifiedAccountId;
      return await this.matchesSystemAccount(accountId) ? accountId : '';
    } catch (_error) {
      // 无可核对的身份仍可使用 IAP；只是下次回前台不能跳过权益查询。
      return '';
    }
  }

  private async refreshCurrentAccount(context: common.UIAbilityContext): Promise<void> {
    do {
      const checkAccount = this.accountCheckPending;
      this.accountCheckPending = false;
      if (checkAccount && !this.forceRefreshRequested && !this.recoverRequested && this.hasCachedResult() &&
        await this.matchesSystemAccount(this.verifiedAccountId) && this.hasCachedResult() &&
        !this.forceRefreshRequested && !this.recoverRequested) {
        MembershipState.current.revalidating = this.accountCheckPending;
        this.scheduleRefresh(context);
        if (context.applicationInfo.debug) {
          hilog.info(0x0000, 'MembershipService', 'Foreground reused verified entitlement after local account check');
        }
      } else {
        if (checkAccount) {
          this.sandboxChecked = false;
          MembershipState.current.confirmedInactive = false;
        }
        this.busy = !MembershipState.current.hasAccess;
        if (this.busy) this.message = $r('app.string.membership_checking');
        await this.refreshInner(context);
        this.forceRefreshRequested = false;
      }
      // 查询期间又发生前后台切换时，再核对最新账号；所有入口仍共用一个任务。
    } while (this.accountCheckPending && this.inForeground);
  }

  private async checkSandbox(context: common.UIAbilityContext): Promise<void> {
    if (this.sandboxChecked) return;
    if (this.sandboxTask) return this.sandboxTask;
    this.sandboxTask = this.checkSandboxInner(context).finally((): void => { this.sandboxTask = null; });
    return this.sandboxTask;
  }

  private async checkSandboxInner(context: common.UIAbilityContext): Promise<void> {
    this.allowSandbox = false;
    if (context.applicationInfo.debug) {
      try { this.allowSandbox = await this.bounded(iap.isSandboxActivated(context)); } catch (_error) { /* 生产凭据仍可验签。 */ }
    }
    this.sandboxChecked = true;
  }

  private async query(context: common.UIAbilityContext, type: iap.PurchaseQueryType): Promise<SubscriptionPayload[]> {
    const payloads: SubscriptionPayload[] = [];
    for (const data of await this.queryData(context, type, iap.ProductType.AUTORENEWABLE)) {
      payloads.push(await SubscriptionVerifier.verify(context, data));
    }
    return payloads;
  }

  private async queryLifetime(context: common.UIAbilityContext, type: iap.PurchaseQueryType): Promise<LifetimeOrder[]> {
    const orders: LifetimeOrder[] = [];
    for (const data of await this.queryData(context, type, iap.ProductType.NONCONSUMABLE)) {
      const order = LifetimePolicy.validate(await SubscriptionVerifier.verifyLifetime(context, data), this.allowSandbox, Date.now());
      if (order) orders.push(order);
    }
    return orders;
  }

  private async queryData(context: common.UIAbilityContext, type: iap.PurchaseQueryType,
    productType: iap.ProductType): Promise<string[]> {
    let token = '';
    const seen = new Set<string>();
    const payloads: string[] = [];
    for (let page = 0; page < 20; page++) {
      const result = await this.queryPage(context, {
        productType: productType, queryType: type, continuationToken: token || undefined
      });
      // 无购买记录时，实机 IAP 可能省略列表或返回 null；仅在查询成功后将空值视为空列表。
      const purchaseDataList: string[] = result.purchaseDataList ?? [];
      if (!Array.isArray(purchaseDataList)) throw new Error('Invalid purchase list');
      if (context.applicationInfo.debug) {
        hilog.info(0x0000, 'MembershipService',
          'IAP query succeeded, type=%{public}d, query=%{public}d, count=%{public}d, absent=%{public}s',
          productType, type, purchaseDataList.length, String(result.purchaseDataList === undefined || result.purchaseDataList === null));
      }
      if (purchaseDataList.length + payloads.length > 200) throw new Error('Too many subscription records');
      for (const data of purchaseDataList) {
        payloads.push(data);
      }
      token = result.continuationToken || '';
      if (!token) return payloads;
      if (seen.has(token)) throw new Error('Repeated subscription continuation token');
      seen.add(token);
    }
    throw new Error('Subscription pagination limit');
  }

  private queryPage(context: common.UIAbilityContext, parameter: iap.QueryPurchasesParameter): Promise<iap.QueryPurchaseResult> {
    // 后台补发与前台核验共用同一队列，按实际调用时间节流，避免计时器同时唤醒时撞限流。
    const task = this.queryTask.then(async (): Promise<iap.QueryPurchaseResult> => {
      const delay = Math.max(0, this.queryAt + 5100 - Date.now());
      if (delay > 0) await new Promise<void>((resolve): void => { setTimeout(resolve, delay); });
      this.queryAt = Date.now();
      return this.bounded(iap.queryPurchases(context, parameter));
    });
    this.queryTask = task.then((): void => {}, (): void => {});
    return task;
  }

  private async refreshInner(context: common.UIAbilityContext): Promise<void> {
    const accountId = await this.accountForVerification(context);
    await this.checkSandbox(context);
    // 已知终身权益优先查询非消耗型商品。原来每次都先查订阅，终身会员回前台
    // 会平白等待一次 IAP 频率限制；只有终身订单已不存在时才回查订阅，避免漏掉
    // 另一台设备上的订阅权益。
    const knownLifetime = MembershipState.current.productId === LifetimePolicy.product;
    let payloads: SubscriptionPayload[] = [];
    let lifetimeOrders: LifetimeOrder[] = [];
    if (knownLifetime) {
      lifetimeOrders = await this.queryLifetime(context, iap.PurchaseQueryType.CURRENT_ENTITLEMENT);
      if (lifetimeOrders.length === 0 || this.recoverRequested) {
        payloads = await this.query(context, iap.PurchaseQueryType.CURRENT_ENTITLEMENT);
      }
    } else {
      payloads = await this.query(context, iap.PurchaseQueryType.CURRENT_ENTITLEMENT);
      lifetimeOrders = await this.queryLifetime(context, iap.PurchaseQueryType.CURRENT_ENTITLEMENT);
    }
    // 只把核验前后均由系统确认的同一账号绑定到缓存，不能把旧权益绑定到新头像账号。
    if (accountId && !await this.matchesSystemAccount(accountId)) throw new Error('IAP account changed during verification');
    this.verifiedAccountId = accountId;
    let latest: SubscriptionStatus | undefined = undefined;
    const orders: SubscriptionOrder[] = [];
    const now = Date.now();
    for (const payload of payloads) {
      const status = SubscriptionPolicy.validate(payload, this.allowSandbox, now);
      if (status) this.logSubscriptionDates(context, payload, status);
      if (status && SubscriptionPolicy.active(status, now)) {
        if (!latest || status.expiresTime > latest.expiresTime) latest = status;
        if (status.lastPurchaseOrder) orders.push(status.lastPurchaseOrder);
      }
    }
    // 先原子替换权益，再确认发货；重复查询只是覆盖到期时间，不累计增加月份。
    const state = MembershipState.current;
    state.clear();
    if (lifetimeOrders.length > 0) {
      state.productId = LifetimePolicy.product;
      state.verifiedAt = now;
      for (const order of lifetimeOrders) orders.push(order);
    } else if (latest && latest.lastPurchaseOrder) {
      state.productId = latest.lastPurchaseOrder.productId;
      state.expiresAt = latest.expiresTime;
      state.autoRenew = latest.renewalInfo?.autoRenewStatusCode === '1';
      state.verifiedAt = now;
    }
    this.entitlementRevision++;
    state.confirmedInactive = !state.active;
    state.revalidating = this.accountCheckPending;
    this.refreshedAt = now;
    this.message = state.active ? $r('app.string.membership_active') : $r('app.string.membership_inactive');
    this.scheduleRefresh(context);
    await this.persistDisplay(context, state.createDisplaySnapshot());
    if (state.confirmedInactive) await this.resetDefaults(context);
    const recoverUnfinished = this.recoverRequested;
    this.recoverRequested = false;
    this.queueConfirmation(context, orders, lifetimeOrders, recoverUnfinished);
  }

  private queueConfirmation(context: common.UIAbilityContext, orders: SubscriptionOrder[],
    lifetimeOrders: LifetimeOrder[], recoverUnfinished: boolean): void {
    const revision = this.entitlementRevision;
    // 确认串行执行，不占用页面 busy；迟到的旧账号任务不能覆盖新核验结果。
    const task = this.confirmationTask.then((): Promise<void> =>
      this.confirmOrders(context, orders, lifetimeOrders, recoverUnfinished, revision)).catch((): void => {
      if (revision === this.entitlementRevision) this.confirmationPending = true;
    });
    this.confirmationTask = task;
    if (recoverUnfinished) {
      this.recoveryTask = task;
      task.finally((): void => { if (this.recoveryTask === task) this.recoveryTask = null; });
    }
  }

  private logSubscriptionDates(context: common.UIAbilityContext, payload: SubscriptionPayload,
    status: SubscriptionStatus): void {
    const order = status.lastPurchaseOrder;
    if (!context.applicationInfo.debug || !order) return;
    // 仅记录已验签订单的日期和环境，不输出账号、订单号、token 或原始凭据。
    hilog.info(0x0000, 'MembershipService',
      'Verified subscription dates: environment=%{public}s product=%{public}s purchased=%{public}s expires=%{public}s now=%{public}s',
      payload.environment, order.productId, new Date(order.purchaseTime).toISOString(),
      new Date(status.expiresTime).toISOString(), new Date().toISOString());
  }

  private async confirmOrders(context: common.UIAbilityContext, orders: SubscriptionOrder[],
    lifetimeOrders: LifetimeOrder[], recoverUnfinished: boolean, revision: number): Promise<void> {
    if (revision !== this.entitlementRevision) return;
    this.confirmationPending = false;
    for (const order of orders) {
      if (revision !== this.entitlementRevision) return;
      await this.finish(context, order, revision);
    }
    // 日常核验只确认当前订单；手动恢复及支付结果不确定时再扫描历史未完成订单。
    if (!recoverUnfinished || revision !== this.entitlementRevision) return;
    // 补发货不覆盖 CURRENT_ENTITLEMENT 的最新状态，防止历史凭据恢复已撤销的权益。
    try {
      const unfinished = await this.query(context, iap.PurchaseQueryType.UNFINISHED);
      if (revision !== this.entitlementRevision) return;
      const state = MembershipState.current;
      for (const payload of unfinished) {
        if (revision !== this.entitlementRevision) return;
        const status = SubscriptionPolicy.validate(payload, this.allowSandbox, Date.now());
        if (!state.active || !status || !SubscriptionPolicy.active(status, Date.now()) || !status.lastPurchaseOrder) continue;
        const order = status.lastPurchaseOrder;
        const belongsToCurrent = orders.some((current: SubscriptionOrder): boolean => current.purchaseToken === order.purchaseToken);
        if (belongsToCurrent) await this.finish(context, order, revision);
      }
      if (revision !== this.entitlementRevision) return;
      const lifetimeUnfinished = await this.queryLifetime(context, iap.PurchaseQueryType.UNFINISHED);
      if (revision !== this.entitlementRevision) return;
      for (const order of lifetimeUnfinished) {
        if (revision !== this.entitlementRevision) return;
        if (state.active && lifetimeOrders.some((current: LifetimeOrder): boolean =>
          current.purchaseToken === order.purchaseToken && current.purchaseOrderId === order.purchaseOrderId)) {
          await this.finish(context, order, revision);
        }
      }
    } catch (_error) {
      if (revision === this.entitlementRevision) this.confirmationPending = true;
    }
  }

  private async finish(context: common.UIAbilityContext, order: SubscriptionOrder, revision: number): Promise<void> {
    const key = order.productType + ':' + order.purchaseToken + ':' + order.purchaseOrderId;
    if (order.finishStatus === '1' || this.finishedOrders.has(key)) return;
    try {
      await this.bounded(iap.finishPurchase(context, {
        productType: order.productType === '1' ? iap.ProductType.NONCONSUMABLE : iap.ProductType.AUTORENEWABLE,
        purchaseOrderId: order.purchaseOrderId, purchaseToken: order.purchaseToken
      }));
      if (this.finishedOrders.size >= 200) this.finishedOrders.clear();
      this.finishedOrders.add(key);
    } catch (error) {
      const failure: BusinessError = error;
      if (failure.code === iap.IAPErrorCode.PURCHASE_FINISHED) {
        if (this.finishedOrders.size >= 200) this.finishedOrders.clear();
        this.finishedOrders.add(key);
      } else if (revision === this.entitlementRevision) this.confirmationPending = true;
    }
  }

  async purchase(context: common.UIAbilityContext, id: string): Promise<void> {
    if (this.purchaseInProgress || this.busy || !this.supported ||
      !this.plans.some((plan: MembershipPlan): boolean => plan.id === id)) return;
    this.purchaseInProgress = true;
    let reconcile = false;
    try {
      // 会员中心刚核验的结果在 30 秒内复用；先等正在执行的查询，避免旧结果覆盖新购买。
      if (this.refreshTask) await this.refreshTask;
      const age = Date.now() - this.refreshedAt;
      await this.refresh(context, this.refreshedAt === 0 || age < 0 || age > 30000);
      const state = MembershipState.current;
      if (state.active) {
        if (state.lifetime) return;
        if (id !== LifetimePolicy.product) { await this.manageSubscriptions(context); return; }
      }
      if ((!state.hasAccess && !state.confirmedInactive) || state.revalidating ||
        this.refreshedAt === 0 || Date.now() < this.refreshedAt || Date.now() - this.refreshedAt > 30000) return;
      this.busy = true;
      const result = await this.bounded(iap.createPurchase(context,
        { productType: id === LifetimePolicy.product ? iap.ProductType.NONCONSUMABLE : iap.ProductType.AUTORENEWABLE,
          productId: id }), 180000);
      if (id === LifetimePolicy.product) {
        const order = LifetimePolicy.validate(await SubscriptionVerifier.verifyLifetime(context, result.purchaseData),
          this.allowSandbox, Date.now());
        if (!order) throw new Error('Invalid lifetime purchase result');
        await this.applyPurchase(context, id, 0, false);
        this.queueConfirmation(context, [order], [order], false);
      } else {
        const payload = await SubscriptionVerifier.verify(context, result.purchaseData);
        const status = SubscriptionPolicy.validate(payload, this.allowSandbox, Date.now());
        if (!status || !status.lastPurchaseOrder || status.lastPurchaseOrder.productId !== id ||
          !SubscriptionPolicy.active(status, Date.now())) {
          throw new Error('Inactive subscription purchase result');
        }
        await this.applyPurchase(context, id, status.expiresTime, status.renewalInfo?.autoRenewStatusCode === '1');
        this.logSubscriptionDates(context, payload, status);
        this.queueConfirmation(context, [status.lastPurchaseOrder], [], false);
      }
    } catch (error) {
      const failure: BusinessError = error;
      this.message = this.errorMessage(failure);
      reconcile = failure.code !== iap.IAPErrorCode.USER_CANCELED;
    } finally {
      this.busy = false;
      this.purchaseInProgress = false;
      if (this.expiryTimer === -1) this.scheduleRefresh(context);
    }
    // 只有支付结果不确定时才扫描当前/未完成订单；成功结果已经即时生效。
    if (reconcile) await this.refresh(context, true, true);
  }

  /** 将已通过 IAP 签名校验的购买结果立即写入内存和展示快照。 */
  private async applyPurchase(context: common.UIAbilityContext, id: string, expiresAt: number, autoRenew: boolean): Promise<void> {
    if (this.verifiedAccountId && !await this.matchesSystemAccount(this.verifiedAccountId)) this.verifiedAccountId = '';
    this.accountCheckPending = false;
    const now = Date.now();
    const state = MembershipState.current;
    state.clear();
    state.productId = id;
    state.expiresAt = expiresAt;
    state.autoRenew = autoRenew;
    state.verifiedAt = now;
    state.confirmedInactive = false;
    state.revalidating = false;
    this.entitlementRevision++;
    this.refreshedAt = now;
    this.purchaseReturnUntil = this.awaitingPurchaseForeground ? now + 30000 : 0;
    this.message = $r('app.string.membership_active');
    this.scheduleRefresh(context);
    this.persistDisplay(context, state.createDisplaySnapshot());
  }

  async manage(context: common.UIAbilityContext): Promise<boolean> {
    if (this.purchaseInProgress) return false;
    return this.manageSubscriptions(context);
  }

  private async manageSubscriptions(context: common.UIAbilityContext): Promise<boolean> {
    if (this.busy || !this.supported) return false;
    if (this.refreshTask) await this.refreshTask;
    if (this.busy) return false;
    this.busy = true;
    try {
      await this.bounded(iap.showManagedSubscriptions(context, { windowScreenMode: iap.WindowScreenMode.FULLSCREEN }));
    } catch (error) {
      this.message = this.errorMessage(error);
      return false;
    } finally {
      this.busy = false;
    }
    await this.refresh(context, true);
    return true;
  }

  background(): void {
    this.inForeground = false;
    this.awaitingPurchaseForeground = this.purchaseInProgress;
    this.purchaseReturnUntil = 0;
    if (this.expiryTimer !== -1) clearTimeout(this.expiryTimer);
    this.expiryTimer = -1;
  }

  private scheduleRefresh(context: common.UIAbilityContext): void {
    if (this.expiryTimer !== -1) clearTimeout(this.expiryTimer);
    this.expiryTimer = -1;
    const state = MembershipState.current;
    if (!state.active || !this.inForeground) return;
    this.expiryTimer = setTimeout((): void => {
      this.expiryTimer = -1;
      if (!state.lifetime && Date.now() >= state.expiresAt) {
        state.clear();
        state.confirmedInactive = true;
        this.persistDisplay(context, null);
        this.resetDefaults(context);
      }
      this.refresh(context, true);
    }, Math.max(1000, Math.min(state.verifiedAt + 240000,
      state.lifetime ? Number.MAX_SAFE_INTEGER : state.expiresAt) - Date.now()));
  }

  private async resetDefaults(context: common.UIAbilityContext): Promise<void> {
    if (MembershipState.current.hasAccess) return;
    // 不等待备份任务：该任务可能正在等待本次会员查询，避免互相等待。
    AutoBackupService.instance.resetMembershipDefaults(context).catch((): void => {});
    try { await PreferenceService.setSearchConcurrency(3); } catch (_error) { /* 后续读取仍按默认并发执行。 */ }
    if (!AppIconService.instance.supported || !AppIconService.instance.membershipRequired) return;
    try { await AppIconService.instance.select(''); } catch (_error) { /* 下次前台刷新重试系统图标。 */ }
  }

  private errorMessage(error: BusinessError): Resource {
    hilog.warn(0x0000, 'MembershipService', 'IAP operation failed, code=%{public}d', error.code ?? -1);
    switch (error.code) {
      case -2: return $r('app.string.membership_timeout');
      case 1001860000: return $r('app.string.membership_cancelled');
      case 1001860050: return $r('app.string.membership_login_required');
      case 1001860003: return $r('app.string.membership_products_unavailable');
      case 1001860002: return $r('app.string.membership_not_authorized');
      case 1001860004: return $r('app.string.membership_retry_later');
      case 1001860005: return $r('app.string.membership_network_error');
      case 1001860007:
      case 1001860054:
      case 801: return $r('app.string.membership_unsupported');
      default: return $r('app.string.membership_verification_failed');
    }
  }
}
