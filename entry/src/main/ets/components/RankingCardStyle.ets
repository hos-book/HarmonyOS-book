import { PlatformCompat } from '../utils/PlatformCompat';

/** 把占位、图片和装饰先合成为同一张圆角卡，避免缩放后露出方形底边。 */
export class RankingCardClip implements AttributeModifier<CommonAttribute> {
  applyNormalAttribute(node: CommonAttribute): void {
    if (PlatformCompat.supports(22)) node.borderRadius(RankingCardStyle.RADIUS, RenderStrategy.OFFSCREEN);
    else node.borderRadius(RankingCardStyle.RADIUS);
    node.clip(true);
  }
}

/**
 * 榜单卡片的统一规格：书架横向卡片、点开的详情卡片、音频榜单卡片共用。
 * 圆角是"屏幕上看到的圆角"，展开卡片会按当前缩放反推，保证放大前后一致。
 */
export class RankingCardStyle {
  static readonly RADIUS: number = 16;
  static readonly SHADOW_RADIUS: number = 18;
  static readonly SHADOW_COLOR: string = '#4D000000';
  static readonly SHADOW_OFFSET_Y: number = 8;
  /** 封面统一按书架卡片的长宽比取景（88:118）。 */
  static readonly COVER_ASPECT: number = 88 / 118;
}
