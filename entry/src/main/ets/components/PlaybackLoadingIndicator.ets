import { InfinityLoadingIndicator } from './InfinityLoadingIndicator';

/** 播放入口复用全局主题色 Infinity 加载动画。 */
@ComponentV2
export struct PlaybackLoadingIndicator {
  @Param indicatorSize: number = 36;

  build() {
    InfinityLoadingIndicator({ indicatorSize: this.indicatorSize })
  }
}
