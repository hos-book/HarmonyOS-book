/** 榜单展开卡片与现有阅读路由之间的一次性动画交接。 */
@ObservedV2
export class RankingReaderCloseState {
  @Trace closing: boolean = false;
  @Trace pushed: number = 0;
  @Trace returned: number = 0;
}

export class RankingReaderTransition {
  static readonly closeState: RankingReaderCloseState = new RankingReaderCloseState();
  private static pendingBookId: string = '';
  private static activeBookId: string = '';
  private static closeComplete: (() => void) | undefined = undefined;
  private static returning: boolean = false;

  static begin(bookId: string): void {
    RankingReaderTransition.pendingBookId = bookId;
    RankingReaderTransition.activeBookId = bookId;
    RankingReaderTransition.closeComplete = undefined;
    RankingReaderTransition.returning = false;
    RankingReaderTransition.closeState.closing = false;
  }

  static take(bookId: string): void {
    if (RankingReaderTransition.pendingBookId !== bookId) return;
    RankingReaderTransition.pendingBookId = '';
    RankingReaderTransition.closeState.pushed++;
  }

  static beginClose(bookId: string): void {
    if (RankingReaderTransition.activeBookId !== bookId || RankingReaderTransition.returning) return;
    RankingReaderTransition.returning = true;
    RankingReaderTransition.pendingBookId = '';
    RankingReaderTransition.closeState.closing = true;
    RankingReaderTransition.closeState.returned++;
  }

  static canReturn(route: string, bookId: string): boolean {
    return (route === 'reader' || route === 'comicReader') && bookId.length > 0 &&
      RankingReaderTransition.activeBookId === bookId;
  }

  /** 阅读页仍覆盖在前面时，先把原详情卡垫成满屏纯色。 */
  static prepareClose(bookId: string, onComplete?: () => void): boolean {
    if (RankingReaderTransition.activeBookId !== bookId || bookId.length === 0) return false;
    RankingReaderTransition.closeComplete = onComplete;
    RankingReaderTransition.closeState.closing = true;
    return true;
  }

  /** 整页收回、详情恢复之后才允许导航移除阅读页。 */
  static completeClose(): void {
    if (!RankingReaderTransition.returning) return;
    const complete: (() => void) | undefined = RankingReaderTransition.closeComplete;
    RankingReaderTransition.closeComplete = undefined;
    RankingReaderTransition.activeBookId = '';
    RankingReaderTransition.returning = false;
    RankingReaderTransition.closeState.closing = false;
    complete?.();
  }

  static cancelClose(bookId: string): void {
    if (RankingReaderTransition.activeBookId !== bookId) return;
    RankingReaderTransition.closeComplete = undefined;
    RankingReaderTransition.returning = false;
    RankingReaderTransition.closeState.closing = false;
  }

  static clear(): void {
    RankingReaderTransition.pendingBookId = '';
    RankingReaderTransition.activeBookId = '';
    RankingReaderTransition.closeComplete = undefined;
    RankingReaderTransition.returning = false;
    RankingReaderTransition.closeState.closing = false;
  }
}
