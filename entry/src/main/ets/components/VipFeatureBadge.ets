/** 标识会员功能，不代表当前账号已开通会员。 */
@ComponentV2
export struct VipFeatureBadge {
  build() {
    Text($r('app.string.membership_vip_label'))
      .fontSize(10)
      .fontWeight(FontWeight.Bold)
      .fontColor('#55432C')
      .backgroundColor('#EAD5AE')
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .borderRadius(4)
      .maxLines(1)
      .flexShrink(0)
      .accessibilityText($r('app.string.membership_icon_exclusive'))
  }
}
