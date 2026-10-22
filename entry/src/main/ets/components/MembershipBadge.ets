/** 月/年/终身 VIP 横版透明标识，按素材比例和指定高度显示。 */
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
            .aspectRatio(this.productId === 'lastVip' ? 512 / 229 :
              this.productId === 'iconMonth' ? 220 / 256 : 259 / 256)
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
        .aspectRatio(this.productId === 'lastVip' ? 2238 / 825 :
          this.productId === 'iconMonth' ? 2745 / 1181 : 2336 / 938)
        .objectFit(ImageFit.Contain)
        .flexShrink(0)
        .accessibilityText(this.productId === 'lastVip' ? $r('app.string.membership_lifetime') :
          this.productId === 'iconMonth' ? $r('app.string.membership_month') : $r('app.string.membership_year'))
      }
    }
  }
}
