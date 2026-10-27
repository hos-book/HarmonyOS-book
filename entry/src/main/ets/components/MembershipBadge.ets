/** 声页会员图标；昵称小标收紧透明边距，按图案原始比例显示。 */
@ComponentV2
export struct MembershipBadge {
  @Param productId: string = '';
  @Param badgeHeight: number = 28;
  @Param compact: boolean = false;
  @Param showLabel: boolean = true;

  build() {
    if (this.productId === 'iconMonth' || this.productId === 'iconYear' || this.productId === 'lastVip') {
      if (this.compact) {
        Row({ space: 4 }) {
          Image(this.productId === 'lastVip' ? $r('app.media.vip_life_symbol') :
            this.productId === 'iconMonth' ? $r('app.media.vip_month_symbol') : $r('app.media.vip_year_symbol'))
            .height(this.badgeHeight)
            .aspectRatio(this.productId === 'lastVip' ? 225 / 128 :
              this.productId === 'iconMonth' ? 122 / 128 : 156 / 128)
            .objectFit(ImageFit.Contain).flexShrink(0)
            .accessibilityText(this.productId === 'lastVip' ? $r('app.string.membership_lifetime') :
              this.productId === 'iconMonth' ? $r('app.string.membership_month') : $r('app.string.membership_year'))
          if (this.showLabel) {
            Text(this.productId === 'lastVip' ? $r('app.string.membership_lifetime') :
              this.productId === 'iconMonth' ? $r('app.string.membership_month') : $r('app.string.membership_year'))
              .fontSize(12).fontColor($r('sys.color.font_secondary'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
      } else {
        Image(this.productId === 'lastVip' ? $r('app.media.vip_life_badge') :
          this.productId === 'iconMonth' ? $r('app.media.vip_month_badge') : $r('app.media.vip_year_badge'))
          .height(this.badgeHeight)
          .aspectRatio(1)
          .objectFit(ImageFit.Contain)
          .flexShrink(0)
          .accessibilityText(this.productId === 'lastVip' ? $r('app.string.membership_lifetime') :
            this.productId === 'iconMonth' ? $r('app.string.membership_month') : $r('app.string.membership_year'))
      }
    }
  }
}
