/** 随发布渠道打包；使用 scripts/set-release-channel.py 切换，不读取用户偏好。 */
export class ReleasePolicy {
  static readonly showPodcastEntry: boolean = false;
  static readonly membershipPurchaseEnabled: boolean = true;
}
