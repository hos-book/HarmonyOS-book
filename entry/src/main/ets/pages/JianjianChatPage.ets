import { FrostedPageHeader } from '../components/FrostedPageHeader';
import { JianjianAiConfig, JianjianAiMessage, JianjianChatItem, JianjianChatRoute,
  JianjianBookContext, JianjianCitation, JianjianExcerpt } from '../model/JianjianAi';
import { JianjianAiService } from '../service/JianjianAiService';
import { JianjianChatStore } from '../service/JianjianChatStore';
import { JianjianBookContextService } from '../service/JianjianBookContextService';
import { Book } from '../model/Book';
import { DataService } from '../service/DataService';
import { SearchCache } from '../utils/SearchCache';
import { emitter } from '@kit.BasicServicesKit';
import { EVT_READER_JUMP_CHAPTER } from '../model/TextReading';
import { AppColor, AppFont, AppRadius, AppSpace, AppTheme } from '../theme/Theme';
import { ListDataSource } from '../utils/ListDataSource';
import { WindowUtils } from '../utils/WindowUtils';

@ComponentV2
export struct JianjianChatPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param active: boolean = true;
  @Param route: JianjianChatRoute = new JianjianChatRoute();
  @Local headerHeight: number = WindowUtils.getStatusBarHeightVp() + 56;
  @Local configured: boolean = false;
  @Local loading: boolean = true;
  @Local model: string = '';
  @Local input: string = '';
  @Local message: ResourceStr = '';
  @Local sending: boolean = false;
  @Local itemCount: number = 0;
  @Local bookTitle: string = '';
  @Local scopeText: ResourceStr = '';
  @Local contextReady: boolean = false;
  @Local contextPartial: boolean = false;
  @Local clearing: boolean = false;
  private book: Book | null = null;
  private bookContext: JianjianBookContext = new JianjianBookContext();
  private historyLoaded: boolean = false;
  private sessionKey: string = '';
  private items: JianjianChatItem[] = [];
  private source: ListDataSource<JianjianChatItem> = new ListDataSource<JianjianChatItem>();
  private scroller: Scroller = new Scroller();
  private config: JianjianAiConfig = new JianjianAiConfig();
  private client: JianjianAiService = new JianjianAiService();
  private pendingText: string = '';
  private alive: boolean = false;
  private generation: number = 0;
  private nextId: number = 0;
  private scrollTimer: number = -1;

  aboutToAppear(): void {
    this.alive = true;
    this.sessionKey = JianjianChatStore.key(this.route);
    if (this.route.recap) this.input = this.getUIContext().getHostContext()?.resourceManager
      .getStringSync($r('app.string.jianjian_book_recap_question').id) ?? '';
    this.initialize();
  }
  aboutToDisappear(): void {
    this.alive = false;
    this.cancel();
    this.config = new JianjianAiConfig();
  }

  @Monitor('active')
  private onActiveChanged(): void {
    if (!this.alive) return;
    if (this.active) this.initialize();
    else this.cancel();
  }

  private async initialize(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || !this.alive || !this.active) return;
    const generation = ++this.generation;
    this.loading = true;
    try {
      const config = await JianjianAiService.loadConfig(context);
      if (!this.alive || generation !== this.generation) return;
      if (!this.historyLoaded) {
        const history = await JianjianChatStore.load(context, this.sessionKey);
        if (!this.alive || generation !== this.generation) return;
        this.items = history; this.historyLoaded = true; this.reloadItems(); this.scrollBottom();
      }
      this.config = config;
      this.model = config.model;
      this.configured = !!(config.address && config.apiKey && config.model);
      this.message = '';
      if (this.route.bookId) {
        let book = SearchCache.get(this.route.bookId);
        if (!book) book = await DataService.getBookById(context, this.route.bookId) ?? null;
        if (!this.alive || generation !== this.generation) return;
        if (!book || !JianjianBookContextService.matches(book, this.route)) throw new Error('Book unavailable');
        this.book = book;
        this.bookTitle = book.title;
        this.bookContext = await JianjianBookContextService.collect(context, book, this.route,
          (): boolean => this.alive && this.active && generation === this.generation);
        if (!this.alive || generation !== this.generation) return;
        this.contextReady = this.bookContext.excerpts.length > 0;
        this.contextPartial = this.bookContext.missingChapters > 0 || this.bookContext.limited;
        this.scopeText = this.contextReady ? $r('app.string.jianjian_book_scope',
          book.chapters[this.route.chapterIndex]?.title ?? '', this.bookContext.chapterCount) :
          $r('app.string.jianjian_book_no_context');
      }
    } catch (_error) {
      if (this.alive && generation === this.generation) {
        this.configured = false;
        this.contextReady = false;
        this.message = $r('app.string.settings_load_failed');
      }
    } finally { if (this.alive && generation === this.generation) this.loading = false; }
  }

  private reloadItems(): void {
    this.source.setItems(this.items);
    this.itemCount = this.items.length;
  }

  private scrollBottom(): void {
    if (this.scrollTimer !== -1) clearTimeout(this.scrollTimer);
    this.scrollTimer = setTimeout((): void => {
      this.scrollTimer = -1;
      if (this.alive && this.active) this.scroller.scrollEdge(Edge.Bottom);
    }, 50);
  }

  private async send(): Promise<void> {
    const text = this.input.trim();
    if (!this.alive || !this.active || this.sending || this.loading || this.clearing) return;
    if (!this.historyLoaded) { this.initialize(); return; }
    if (!this.configured) {
      this.navStack.pushPathByName('jianjianAiSettings', '');
      return;
    }
    if (!text) {
      this.message = $r('app.string.jianjian_ai_input_required');
      return;
    }
    if (this.route.bookId && !this.contextReady) {
      this.message = $r('app.string.jianjian_book_no_context');
      return;
    }
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    const generation = ++this.generation;
    this.sending = true;
    this.pendingText = text;
    this.input = '';
    this.message = '';
    const userItem = this.newItem('user', text);
    this.items.push(userItem);
    this.reloadItems(); this.scrollBottom();
    try {
      let prompt = context.resourceManager.getStringSync($r('app.string.jianjian_ai_system_prompt').id);
      let excerpts: JianjianExcerpt[] = [];
      if (this.route.bookId) {
        const recapQuestion = context.resourceManager.getStringSync($r('app.string.jianjian_book_recap_question').id);
        excerpts = JianjianBookContextService.select(this.bookContext, text, text === recapQuestion);
        prompt = context.resourceManager.getStringSync($r('app.string.jianjian_book_system_prompt').id) + '\n' +
          JianjianBookContextService.evidence(excerpts);
      }
      // Rewinding a book cannot re-send later answers as hidden context.
      const messages = this.items.filter((item: JianjianChatItem): boolean => !this.route.bookId ||
        (item.boundaryChapter >= 0 && (item.boundaryChapter < this.route.chapterIndex ||
          (item.boundaryChapter === this.route.chapterIndex && item.boundaryOffset <= this.route.charOffset))))
        .map((item: JianjianChatItem): JianjianAiMessage => new JianjianAiMessage(item.role, item.content));
      const reply = await this.client.chat(this.config, messages, prompt);
      if (!this.alive || generation !== this.generation) return;
      const assistantItem = this.newItem('assistant', reply);
      assistantItem.references = JianjianBookContextService.citations(reply, excerpts);
      this.items.push(assistantItem);
      this.items = this.items.slice(-60);
      this.pendingText = '';
      this.reloadItems(); this.scrollBottom();
      try { await JianjianChatStore.save(context, this.sessionKey, this.items); }
      catch (_error) {
        if (this.alive && generation === this.generation) this.message = $r('app.string.jianjian_chat_save_failed');
      }
    } catch (error) {
      if (this.alive && generation === this.generation) {
        this.restorePending();
        this.message = JianjianAiService.errorText(error);
      }
    } finally { if (this.alive && generation === this.generation) this.sending = false; }
  }

  private newItem(role: string, content: string): JianjianChatItem {
    const item = new JianjianChatItem(`${Date.now()}-${++this.nextId}`, role, content);
    item.boundaryChapter = this.route.chapterIndex;
    item.boundaryOffset = this.route.charOffset;
    return item;
  }

  private recap(): void {
    if (this.sending || this.loading || this.clearing) return;
    this.input = this.getUIContext().getHostContext()?.resourceManager
      .getStringSync($r('app.string.jianjian_book_recap_question').id) ?? '';
    this.send();
  }

  private jumpToReference(ref: JianjianCitation): void {
    if (!this.book || this.sending || this.clearing) return;
    const index = JianjianBookContextService.resolveCitation(this.book, ref);
    if (index < 0 || !this.navStack.getAllPathName().includes('reader')) {
      this.message = $r('app.string.jianjian_reference_unavailable'); return;
    }
    this.navStack.pop();
    emitter.emit(EVT_READER_JUMP_CHAPTER, { data: {
      bookId: this.book.id, resourceIndex: index, charOffset: ref.charOffset
    } });
  }

  private async clearHistory(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || this.sending || this.loading || this.clearing || !this.historyLoaded) return;
    this.clearing = true;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: $r('app.string.jianjian_chat_clear'), message: $r('app.string.jianjian_chat_clear_confirm'),
        buttons: [{ text: $r('app.string.common_cancel'), color: AppTheme.TextSecondary },
          { text: $r('app.string.jianjian_chat_clear'), color: AppColor.Brand }] });
      if (result.index !== 1 || !this.alive || !this.active) return;
      await JianjianChatStore.clear(context, this.sessionKey);
      if (!this.alive) return;
      this.items = []; this.reloadItems(); this.message = '';
    } catch (_error) {
      if (this.alive) this.message = $r('app.string.settings_save_failed');
    } finally { this.clearing = false; }
  }

  private restorePending(): void {
    if (!this.pendingText) return;
    if (this.items.length && this.items[this.items.length - 1].role === 'user') this.items.pop();
    this.input = this.pendingText;
    this.pendingText = '';
    this.reloadItems();
  }

  private cancel(): void {
    this.generation++;
    this.client.cancel();
    if (this.scrollTimer !== -1) { clearTimeout(this.scrollTimer); this.scrollTimer = -1; }
    this.restorePending();
    this.sending = false;
  }

  @Builder
  private companionAvatar() {
    Image($r('app.media.jianjian_red_happy')).width(36).height(36).objectFit(ImageFit.Contain)
      .backgroundColor(AppTheme.Surface).borderRadius(AppRadius.Md).padding(2)
      .accessibilityText($r('app.string.jianjian_name'))
  }

  @Builder
  private introduction() {
    Row({ space: AppSpace.Xs }) {
      this.companionAvatar()
      Column({ space: AppSpace.Xxs }) {
        Text($r('app.string.jianjian_name')).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
        Text(!this.configured ? $r('app.string.jianjian_ai_setup_hint') :
          this.route.bookId ? $r('app.string.jianjian_book_greeting') : $r('app.string.jianjian_ai_greeting'))
          .fontSize(AppFont.BodyL).fontColor(AppTheme.TextPrimary).padding(AppSpace.Sm)
          .backgroundColor(AppTheme.Surface)
          .borderRadius({ topLeft: AppRadius.Xs, topRight: AppRadius.Lg,
            bottomLeft: AppRadius.Lg, bottomRight: AppRadius.Lg })
      }.constraintSize({ maxWidth: '80%' }).alignItems(HorizontalAlign.Start)
    }.width('100%').alignItems(VerticalAlign.Top).id('jianjian-chat-introduction')
  }

  @Builder
  private chatBubble(item: JianjianChatItem) {
    Row({ space: AppSpace.Xs }) {
      if (item.role !== 'user') { this.companionAvatar() }
      Column({ space: AppSpace.Xxs }) {
        Text(item.role === 'user' ? $r('app.string.jianjian_chat_you') : $r('app.string.jianjian_name'))
          .fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
        Text(item.content).fontSize(AppFont.BodyL).fontColor(AppTheme.TextPrimary)
          .copyOption(CopyOptions.LocalDevice).padding(AppSpace.Sm)
          .backgroundColor(item.role === 'user' ? AppColor.BrandSoft : AppTheme.Surface)
          .borderRadius({ topLeft: item.role === 'user' ? AppRadius.Lg : AppRadius.Xs,
            topRight: item.role === 'user' ? AppRadius.Xs : AppRadius.Lg,
            bottomLeft: AppRadius.Lg, bottomRight: AppRadius.Lg })
        if (item.references.length > 0) {
          Text($r('app.string.jianjian_book_references')).fontSize(AppFont.Caption).fontColor(AppTheme.TextTertiary)
          ForEach(item.references, (ref: JianjianCitation) => {
            Button($r('app.string.jianjian_book_reference', ref.id, ref.chapterTitle),
              { buttonStyle: ButtonStyleMode.TEXTUAL }).fontSize(AppFont.Caption).fontColor(AppColor.Brand)
              .constraintSize({ maxWidth: '100%' }).onClick((): void => { this.jumpToReference(ref); })
          }, (ref: JianjianCitation): string => ref.id)
        }
      }.constraintSize({ maxWidth: '80%' })
        .alignItems(item.role === 'user' ? HorizontalAlign.End : HorizontalAlign.Start)
      if (item.role === 'user') {
        Text($r('app.string.jianjian_chat_you')).width(36).height(36).textAlign(TextAlign.Center)
          .fontSize(AppFont.Body).fontColor(AppColor.OnBrand).backgroundColor(AppColor.Brand)
          .borderRadius(AppRadius.Md)
      }
    }.width('100%').alignItems(VerticalAlign.Top)
      .justifyContent(item.role === 'user' ? FlexAlign.End : FlexAlign.Start)
      .id('jianjian-chat-message-' + item.id)
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column({ space: AppSpace.Sm }) {
        List({ space: AppSpace.Md, scroller: this.scroller }) {
          if (this.route.bookId) {
            ListItem() {
              Column({ space: AppSpace.Xs }) {
                Row({ space: AppSpace.Xs }) {
                  Text(this.bookTitle).fontSize(AppFont.BodyL).fontWeight(FontWeight.Medium)
                    .fontColor(AppTheme.TextPrimary).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Button($r('app.string.jianjian_book_recap'), { buttonStyle: ButtonStyleMode.TEXTUAL })
                    .fontSize(AppFont.Caption).fontColor(AppColor.Brand).onClick((): void => { this.recap(); })
                    .id('jianjian-book-recap')
                }.width('100%')
                Text(this.scopeText).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
                Text($r('app.string.jianjian_book_privacy')).fontSize(AppFont.Caption).fontColor(AppTheme.TextTertiary)
                if (this.contextPartial) {
                  Text($r('app.string.jianjian_book_partial')).fontSize(AppFont.Caption).fontColor(AppTheme.TextTertiary)
                }
              }.width('100%').alignItems(HorizontalAlign.Start)
            }
          }
          if (this.itemCount === 0 && !this.loading) {
            ListItem() { this.introduction() }
          }
          if (!this.configured && !this.loading) {
            ListItem() {
              Column({ space: AppSpace.Sm }) {
                Button($r('app.string.jianjian_ai_settings'), { buttonStyle: ButtonStyleMode.TEXTUAL }).fontColor(AppColor.Brand)
                  .onClick((): void => { this.navStack.pushPathByName('jianjianAiSettings', ''); })
              }.width('100%').padding({ left: 44 })
            }
          }
          if (this.configured && this.itemCount === 0 && !this.route.bookId) {
            ListItem() {
              Text($r('app.string.jianjian_ai_chat_hint')).fontSize(AppFont.Caption).fontColor(AppTheme.TextTertiary)
                .padding({ left: 44, right: AppSpace.Sm })
            }
          }
          LazyForEach(this.source, (item: JianjianChatItem) => {
            ListItem() {
              this.chatBubble(item)
            }
          }, (item: JianjianChatItem): string => item.id)
          if (this.sending) {
            ListItem() {
              Row({ space: AppSpace.Xs }) {
                this.companionAvatar()
                Column({ space: AppSpace.Xxs }) {
                  Text($r('app.string.jianjian_name')).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary)
                  Row({ space: AppSpace.Xs }) {
                    LoadingProgress().width(20).height(20).color(AppColor.Brand)
                    Text($r('app.string.jianjian_ai_replying')).fontSize(AppFont.Body).fontColor(AppTheme.TextSecondary)
                  }.padding(AppSpace.Sm).backgroundColor(AppTheme.Surface)
                    .borderRadius({ topLeft: AppRadius.Xs, topRight: AppRadius.Lg,
                      bottomLeft: AppRadius.Lg, bottomRight: AppRadius.Lg })
                }.constraintSize({ maxWidth: '80%' }).alignItems(HorizontalAlign.Start)
              }.width('100%').alignItems(VerticalAlign.Top).id('jianjian-chat-replying')
            }
          } else if (this.loading) {
            ListItem() {
              Row({ space: AppSpace.Sm }) {
                LoadingProgress().width(20).height(20).color(AppColor.Brand)
                Text($r('app.string.settings_loading'))
                  .fontSize(AppFont.Body).fontColor(AppTheme.TextSecondary)
              }.padding({ left: 44, top: AppSpace.Xs, bottom: AppSpace.Xs })
            }
          }
        }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring)
        if (this.message) {
          Row({ space: AppSpace.Sm }) {
            Text(this.message).fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary).layoutWeight(1)
            if (!this.configured || !this.historyLoaded) {
              Button($r('app.string.common_retry'), { buttonStyle: ButtonStyleMode.TEXTUAL }).fontColor(AppColor.Brand)
                .onClick((): void => { this.initialize(); })
            }
          }.width('100%')
        }
        Row({ space: AppSpace.Sm }) {
          TextInput({ text: this.input, placeholder: this.route.bookId ?
            $r('app.string.jianjian_book_input_hint') : $r('app.string.jianjian_ai_input_hint') })
            .maxLength(4000).layoutWeight(1).height(44).fontSize(AppFont.BodyL).fontColor(AppTheme.TextPrimary)
            .backgroundColor(AppColor.BrandSoft).borderRadius(AppRadius.Lg)
            .enabled(!this.loading && !this.sending).enterKeyType(EnterKeyType.Send)
            .onChange((value: string): void => { this.input = value; this.message = ''; })
            .onSubmit((): void => { this.send(); }).id('jianjian-chat-input')
          Button(this.sending ? $r('app.string.common_cancel') : $r('app.string.jianjian_ai_send'))
            .height(44).constraintSize({ minWidth: 64 }).fontSize(AppFont.BodyL)
            .backgroundColor(AppColor.Brand).fontColor(AppColor.OnBrand).borderRadius(AppRadius.Lg)
            .onClick((): void => { if (this.sending) this.cancel(); else this.send(); }).id('jianjian-chat-send')
        }.width('100%').padding(AppSpace.Xs).backgroundColor(AppTheme.Surface).borderRadius(AppRadius.Xl)
      }.width('100%').height('100%').padding({ left: AppSpace.Md, right: AppSpace.Md,
        top: this.headerHeight + AppSpace.Sm, bottom: WindowUtils.getBottomSafeVp() + AppSpace.Sm })
      FrostedPageHeader({ onHeightChange: (height: number): void => { this.headerHeight = height; } }) {
        Row({ space: AppSpace.Sm }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([AppTheme.TextPrimary])
          }.width(40).height(40).backgroundColor(Color.Transparent).accessibilityText($r('app.string.common_back'))
            .onClick((): void => { this.navStack.pop(); })
          Column({ space: 2 }) {
            Text($r('app.string.jianjian_name')).fontSize(AppFont.TitleL).fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary)
            if (this.model) { Text(this.model).fontSize(AppFont.Caption).fontColor(AppTheme.TextTertiary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }) }
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.trash')).fontSize(20).fontColor([AppTheme.TextSecondary])
          }.width(36).height(36).backgroundColor(Color.Transparent)
            .accessibilityText($r('app.string.jianjian_chat_clear'))
            .onClick((): void => { this.clearHistory(); }).id('jianjian-chat-clear')
          Button($r('app.string.jianjian_ai_settings'), { buttonStyle: ButtonStyleMode.TEXTUAL }).fontColor(AppColor.Brand)
            .onClick((): void => { this.navStack.pushPathByName('jianjianAiSettings', ''); })
        }.width('100%').padding({ left: AppSpace.Sm, right: AppSpace.Sm,
          top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm, bottom: AppSpace.Sm })
      }
    }.width('100%').height('100%').backgroundColor(AppTheme.SettingsBackground)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
