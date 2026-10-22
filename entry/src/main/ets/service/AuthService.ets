/**
 * 华为账号登录：通过 profile 授权获取身份、昵称和头像，仅在本机缓存账号资料。
 * getHuaweiIDState 从 API 12 起可用，不依赖网络，用于恢复时核对系统账号。
 * AGC 应用级 Client ID、应用包名和实际签名公钥指纹需一致。
 */
import lazy { authentication } from '@kit.AccountKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { PreferenceService, HwAccount } from './PreferenceService';
import { AccountAvatarService } from './AccountAvatarService';
import { MedalService } from './MedalService';

const TAG = 'AuthService';
const DOMAIN = 0x0000;

export enum HwAuthErrorCode {
  LOGIN_OUT = 1001502001,
  NOT_AUTHORIZED = 1001502002,
  INVALID_PARAMETER = 1001502003,
  NETWORK = 1001502005,
  INTERNAL = 1001502009,
  USER_CANCEL = 1001502012,
  PERMISSION_DENIED = 1001502014,
  SYSTEM_SERVICE = 12300001,
  REQUEST_REFUSE = 1001500002,
  CERT_INVALID = 1001500001,
  NOT_SUPPORTED = 1001500003,
  INVALID_RESPONSE = -1,
  STORAGE = -2
}

export class HwAuthError extends Error implements BusinessError {
  code: number;

  constructor(code: number) {
    super('Huawei account operation failed');
    this.code = code;
  }
}

@ObservedV2
export class AuthService {
  private static _instance: AuthService | null = null;

  static get instance(): AuthService {
    if (!AuthService._instance) AuthService._instance = new AuthService();
    return AuthService._instance;
  }

  @Trace isLoggedIn: boolean = false;
  @Trace unionID: string = '';
  @Trace openID: string = '';
  @Trace loginAt: number = 0;
  @Trace nickName: string = '';
  @Trace avatarUri: string = '';
  @Trace dataOperation: boolean = false;
  /** 登录和退出串行进行，防止重复请求。 */
  @Trace logging: boolean = false;
  @Trace restoring: boolean = false;

  private restoreTask: Promise<void> | null = null;
  private accountContext: common.Context | null = null;
  private avatarFile: string = '';

  /** 启动、进入个人中心和前台恢复时检查；无缓存时不发起账号请求或弹出授权。 */
  restore(context: common.Context): Promise<void> {
    if (this.logging) return Promise.resolve();
    if (this.restoreTask) return this.restoreTask;
    this.restoring = true;
    this.restoreTask = this.restoreAccount(context).catch(async (error: BusinessError): Promise<void> => {
      // 系统服务临时失败时保留落盘身份供下次重试，不把未核验的缓存当成已登录。
      await this.resetAccount();
      hilog.warn(DOMAIN, TAG, 'Huawei account restore failed, code=%{public}d', error.code ?? 0);
    }).finally((): void => {
      this.restoring = false;
      this.restoreTask = null;
    });
    return this.restoreTask;
  }

  private async restoreAccount(context: common.Context): Promise<void> {
    this.accountContext = context;
    await PreferenceService.ensureReady(context);
    const account = await PreferenceService.getHwAccount();
    if (!account) {
      await this.resetAccount();
      return;
    }
    const request: authentication.StateRequest = {
      idType: authentication.IdType.OPEN_ID,
      idValue: account.openID
    };
    const result = await new authentication.HuaweiIDProvider().getHuaweiIDState(request);
    if (result.state === authentication.State.AUTHORIZED) {
      await this.applyAccount(context, account);
    } else if (result.state === authentication.State.UNLOGGED_IN ||
      result.state === authentication.State.UNAUTHORIZED) {
      await this.resetAccount();
      await PreferenceService.clearHwAccount();
      await AccountAvatarService.remove(context, account.avatarFile);
    } else {
      throw new HwAuthError(HwAuthErrorCode.INVALID_RESPONSE);
    }
  }

  /** 同一应用授权可由系统恢复时静默登录；不把手机传来的资料当作身份凭证。 */
  async restoreSharedAccount(context: common.Context): Promise<boolean> {
    if (!canIUse('SystemCapability.AuthenticationServices.HuaweiID.Auth')) return false;
    await this.restore(context);
    if (this.isLoggedIn) return true;
    try {
      await this.login(context, false);
      return true;
    } catch (_error) {
      return false;
    }
  }

  async login(context: common.Context, forceAuthorization: boolean = true): Promise<HwAccount> {
    if (this.logging || this.dataOperation) throw new HwAuthError(HwAuthErrorCode.REQUEST_REFUSE);
    this.logging = true;
    try {
      // 等待已有恢复完成，防止迟到的恢复覆盖新登录。
      if (this.restoreTask) await this.restoreTask;
      await PreferenceService.ensureReady(context);
      this.accountContext = context;
      const previous = await PreferenceService.getHwAccount();
      const request = new authentication.HuaweiIDProvider().createAuthorizationWithHuaweiIDRequest();
      request.scopes = ['profile'];
      request.forceAuthorization = forceAuthorization;
      request.state = util.generateRandomUUID();
      const controller = new authentication.AuthenticationController(context);
      const account = await controller.executeRequest(request)
        .then(async (response: authentication.AuthorizationWithHuaweiIDResponse): Promise<HwAccount> => {
          // state 缺失也必须拒绝；不记录身份、授权码或完整响应。
          if (!response || response.state !== request.state || !response.data) {
            throw new HwAuthError(HwAuthErrorCode.INVALID_RESPONSE);
          }
          const result = new HwAccount();
          result.unionID = response.data.unionID ?? '';
          result.openID = response.data.openID ?? '';
          result.loginAt = Date.now();
          if (!HwAccount.isValid(result)) throw new HwAuthError(HwAuthErrorCode.INVALID_RESPONSE);
          result.nickName = typeof response.data.nickName === 'string'
            ? response.data.nickName.trim().substring(0, 256) : '';
          result.avatarFile = await AccountAvatarService.download(context, response.data.avatarUri ?? '');
          return result;
        });
      try {
        await PreferenceService.setHwAccount(account);
      } catch (_error) {
        await AccountAvatarService.remove(context, account.avatarFile);
        throw new HwAuthError(HwAuthErrorCode.STORAGE);
      }
      await this.applyAccount(context, account);
      if (previous) await AccountAvatarService.remove(context, previous.avatarFile);
      hilog.info(DOMAIN, TAG, 'Huawei ID login succeeded');
      return account;
    } catch (error) {
      const failure: BusinessError = error;
      const code = failure.code ?? HwAuthErrorCode.INTERNAL;
      if (code !== HwAuthErrorCode.USER_CANCEL && code !== HwAuthErrorCode.REQUEST_REFUSE) {
        hilog.error(DOMAIN, TAG, 'Huawei ID login failed, code=%{public}d', code);
      }
      throw new HwAuthError(code);
    } finally {
      this.logging = false;
    }
  }

  /** 仅退出简听，不退出系统华为账号，不删除书架、阅读记录或书源会话。 */
  async logout(): Promise<void> {
    if (this.logging || this.dataOperation) throw new HwAuthError(HwAuthErrorCode.REQUEST_REFUSE);
    this.logging = true;
    try {
      if (this.restoreTask) await this.restoreTask;
      await PreferenceService.clearHwAccount();
      if (this.accountContext) await AccountAvatarService.remove(this.accountContext, this.avatarFile);
      await this.resetAccount();
    } catch (_error) {
      throw new HwAuthError(HwAuthErrorCode.STORAGE);
    } finally {
      this.logging = false;
    }
  }

  /** 备份、恢复期间禁止退出或重新授权；系统账号状态检查仍可执行。 */
  beginDataOperation(requireLogin: boolean = true): void {
    if (this.logging || this.restoring || this.dataOperation) throw new HwAuthError(HwAuthErrorCode.REQUEST_REFUSE);
    if (requireLogin && !this.isLoggedIn) throw new HwAuthError(HwAuthErrorCode.LOGIN_OUT);
    this.dataOperation = true;
  }

  endDataOperation(): void {
    this.dataOperation = false;
  }

  private async applyAccount(context: common.Context, account: HwAccount): Promise<void> {
    const avatarUri = await AccountAvatarService.localUri(context, account.avatarFile);
    try {
      await MedalService.instance.bindAccount(context, account.openID);
    } catch (_error) {
      MedalService.instance.failed = true;
      hilog.warn(DOMAIN, TAG, 'Account achievements unavailable; retry on next account restore');
    }
    this.unionID = account.unionID;
    this.openID = account.openID;
    this.loginAt = account.loginAt;
    this.nickName = account.nickName;
    this.avatarFile = account.avatarFile;
    this.avatarUri = avatarUri;
    this.isLoggedIn = true;
  }

  private async resetAccount(): Promise<void> {
    const clearing = MedalService.instance.clearAccount();
    this.isLoggedIn = false;
    this.unionID = '';
    this.openID = '';
    this.loginAt = 0;
    this.nickName = '';
    this.avatarFile = '';
    this.avatarUri = '';
    await clearing;
  }

  maskedId(): string {
    const id = this.openID;
    if (id.length <= 10) return '****';
    return `${id.substring(0, 4)}****${id.substring(id.length - 4)}`;
  }
}
