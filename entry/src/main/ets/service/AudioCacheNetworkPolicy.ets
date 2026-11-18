import { connection } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { GeneralSettings } from '../model/GeneralSettings';

/** 仅约束额外的音频缓存与下载；播放器的主动拉流不经过此策略。 */
export class AudioCacheNetworkPolicy {
  static readonly WAITING_WIFI: string = 'audio_cache_waiting_wifi';
  private static readonly instance: AudioCacheNetworkPolicy = new AudioCacheNetworkPolicy();
  private observer: connection.NetConnection | null = null;
  private observingReady: boolean = false;
  private allowed: boolean = true;
  private listeners: Set<() => void> = new Set<() => void>();

  static getInstance(): AudioCacheNetworkPolicy { return AudioCacheNetworkPolicy.instance; }

  isAllowed(): boolean { return this.allowed; }

  /** 每次实际发起额外传输前重查默认网络，查询失败时保持仅 WLAN 策略。 */
  canTransfer(): boolean {
    this.refresh();
    return this.allowed;
  }

  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    this.refresh();
    return (): void => { this.listeners.delete(listener); };
  }

  refresh(): void {
    if (!GeneralSettings.current.audioCacheWifiOnly) {
      const observer = this.observer;
      this.observer = null;
      this.observingReady = false;
      if (observer !== null) {
        try { observer.unregister((_error: BusinessError): void => {}); } catch (_error) { /* 已释放。 */ }
      }
      this.setAllowed(true);
      return;
    }
    this.observeDefaultNetwork();
    if (!this.observingReady) { this.setAllowed(false); return; }
    let allowed = false;
    try {
      const network = connection.getDefaultNetSync();
      if (network.netId > 0) {
        const capabilities = connection.getNetCapabilitiesSync(network);
        allowed = capabilities.bearerTypes.includes(connection.NetBearType.BEARER_WIFI) &&
          !capabilities.bearerTypes.includes(connection.NetBearType.BEARER_CELLULAR);
      }
    } catch (_error) { /* 无网络信息时不能转用流量下载。 */ }
    this.setAllowed(allowed);
  }

  private setAllowed(allowed: boolean): void {
    if (this.allowed === allowed) return;
    this.allowed = allowed;
    for (const listener of this.listeners) listener();
  }

  private observeDefaultNetwork(): void {
    if (this.observer !== null) return;
    try {
      const observer = connection.createNetConnection();
      this.observer = observer;
      this.observingReady = false;
      observer.on('netAvailable', (_network: connection.NetHandle): void => this.refresh());
      observer.on('netCapabilitiesChange', (_info: connection.NetCapabilityInfo): void => this.refresh());
      observer.on('netLost', (_network: connection.NetHandle): void => {
        // 默认 WLAN 断开时先停额外传输，再重新判断系统已选中的网络。
        if (GeneralSettings.current.audioCacheWifiOnly) this.setAllowed(false);
        this.refresh();
      });
      observer.on('netUnavailable', (): void => {
        if (GeneralSettings.current.audioCacheWifiOnly) this.setAllowed(false);
      });
      observer.register((error: BusinessError): void => {
        if (this.observer !== observer) return;
        if (!error) { this.observingReady = true; this.refresh(); return; }
        this.observer = null;
        this.observingReady = false;
        if (GeneralSettings.current.audioCacheWifiOnly) this.setAllowed(false);
      });
    } catch (_error) {
      this.observer = null;
      this.observingReady = false;
      this.setAllowed(false);
    }
  }
}
