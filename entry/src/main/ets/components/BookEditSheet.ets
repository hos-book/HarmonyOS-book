import { Book } from '../model/Book';
import { BookPresentation, BookPresentationEdit } from '../model/BookPresentation';
import { PreferenceService } from '../service/PreferenceService';
import { SourceSwitchSearch, SourceSwitchBookDataSource } from '../service/BookSourceSwitchService';
import { CoverImage } from './CoverImage';
import { AppColor } from '../theme/Theme';
import { picker, fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';

@ComponentV2
export struct BookEditSheet {
  @Require @Param book: Book;
  @Param groupOnly: boolean = false;
  @Event onSaved: (book: Book) => void = () => {};
  @Local title: string = '';
  @Local cover: string = '';
  @Local group: string = '';
  @Local groups: string[] = [];
  @Local newGroup: string = '';
  @Local searching: boolean = false;
  @Local saving: boolean = false;
  @Local error: string = '';
  private search: SourceSwitchSearch = new SourceSwitchSearch();
  private covers: SourceSwitchBookDataSource = new SourceSwitchBookDataSource();
  private alive: boolean = false;
  private ownedCover: string = '';
  private committed: boolean = false;

  private async deleteGroup(name: string): Promise<void> {
    if (this.saving) return;
    this.saving = true;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: $r('app.string.shelf_group_delete_title'),
        message: $r('app.string.shelf_group_delete_message', name),
        buttons: [
          { text: $r('app.string.common_cancel'), color: $r('sys.color.font_primary') },
          { text: $r('app.string.common_delete'), color: $r('sys.color.ohos_id_color_warning') }
        ]
      });
      if (result.index !== 1 || !this.alive) return;
      const edits = BookPresentation.edits.map((item: BookPresentationEdit): BookPresentationEdit => {
        const edit = new BookPresentationEdit();
        edit.bookId = item.bookId; edit.title = item.title; edit.cover = item.cover;
        edit.group = item.group === name ? '' : item.group;
        return edit;
      });
      const groups = BookPresentation.groups.filter((group: string): boolean => group !== name);
      await PreferenceService.saveBookPresentation(edits, groups);
      if (!this.alive) return;
      this.groups = this.groups.filter((group: string): boolean => group !== name);
      if (this.group === name) this.group = '';
    } catch (_error) {
      if (this.alive) this.error = this.message($r('app.string.rule_source_operation_failed'));
    } finally { if (this.alive) this.saving = false; }
  }

  aboutToAppear(): void {
    this.alive = true;
    this.title = this.book.title;
    this.cover = this.book.cover;
    this.group = BookPresentation.get(this.book.id)?.group ?? '';
    this.groups = BookPresentation.groups.slice();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.search.cancelled = true;
    if (!this.committed && this.ownedCover) fileIo.unlink(this.ownedCover).catch((): void => {});
  }

  private async pickCover(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context || this.saving) return;
    try {
      const options = new picker.PhotoSelectOptions();
      options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result = await new picker.PhotoViewPicker(context).select(options);
      if (!this.alive || result.photoUris.length === 0) return;
      const file = await fileIo.open(result.photoUris[0], fileIo.OpenMode.READ_ONLY);
      let source: image.ImageSource | undefined = undefined;
      let pixels: image.PixelMap | undefined = undefined;
      const packer = image.createImagePacker();
      try {
        source = image.createImageSource(file.fd);
        const info = await source.getImageInfo();
        const scale = Math.min(1, 768 / Math.max(info.size.width, info.size.height));
        pixels = await source.createPixelMap({ desiredSize: { width: Math.max(1, Math.round(info.size.width * scale)),
          height: Math.max(1, Math.round(info.size.height * scale)) } });
        const bytes = await packer.packing(pixels, { format: 'image/jpeg', quality: 85 });
        if (bytes.byteLength > 1024 * 1024) throw new Error('Cover exceeds widget image budget');
        if (!this.alive) return;
        const dir = `${context.filesDir}/edited_covers`;
        if (!await fileIo.access(dir)) await fileIo.mkdir(dir, true);
        const path = `${dir}/${Date.now()}_${Math.floor(Math.random() * 1000000)}.jpg`;
        const output = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
        try {
          let offset = 0;
          while (offset < bytes.byteLength) {
            const written = await fileIo.write(output.fd, bytes.slice(offset));
            if (written <= 0) throw new Error('Incomplete cover');
            offset += written;
          }
        } finally { await fileIo.close(output); }
        if (this.ownedCover) await fileIo.unlink(this.ownedCover).catch((): void => {});
        this.ownedCover = path;
        this.cover = `file://${path}`;
      } finally {
        if (pixels) await pixels.release();
        if (source) await source.release();
        await packer.release();
        await fileIo.close(file);
      }
    } catch (_error) { if (this.alive) this.error = this.message($r('app.string.shelf_edit_cover_failed')); }
  }

  private message(resource: Resource): string {
    return this.getUIContext().getHostContext()?.resourceManager.getStringSync(resource.id) ?? '';
  }

  private async findCovers(): Promise<void> {
    if (this.searching || this.saving) return;
    this.search.cancelled = true;
    this.search = new SourceSwitchSearch();
    this.searching = true;
    this.error = '';
    try {
      await this.search.run(this.book, (books: Book[]): void => {
        if (this.alive) this.covers.setBooks(books.filter((book: Book): boolean => !!book.cover));
      }, this.title);
      if (this.alive && this.covers.totalCount() === 0) this.error = this.message($r('app.string.rule_source_no_match'));
    } finally { if (this.alive) this.searching = false; }
  }

  private async save(): Promise<void> {
    if (this.saving || !this.title.trim()) return;
    this.saving = true;
    try {
      const edit = new BookPresentationEdit();
      const previous = BookPresentation.get(this.book.id);
      edit.bookId = this.book.id;
      edit.title = this.groupOnly ? previous?.title ?? '' : this.title.trim();
      edit.cover = this.groupOnly ? previous?.cover ?? '' : this.cover;
      edit.group = this.groupOnly ? this.group : previous?.group ?? '';
      const edits = BookPresentation.edits.filter((item: BookPresentationEdit): boolean => item.bookId !== edit.bookId);
      edits.push(edit);
      await PreferenceService.saveBookPresentation(edits, this.groupOnly ? this.groups : BookPresentation.groups.slice());
      this.committed = this.cover === `file://${this.ownedCover}`;
      const updated: Book = JSON.parse(JSON.stringify(this.book));
      BookPresentation.apply(updated);
      this.onSaved(updated);
    } catch (_error) { this.error = this.message($r('app.string.rule_source_operation_failed')); }
    finally { if (this.alive) this.saving = false; }
  }

  build() {
    Column({ space: 12 }) {
      Text(this.groupOnly ? $r('app.string.shelf_group_settings') : $r('app.string.shelf_edit_title')).fontSize(22).fontWeight(FontWeight.Bold).width('100%')
        .fontColor($r('sys.color.font_primary'))
      if (!this.groupOnly) {
      TextInput({ text: this.title, placeholder: $r('app.string.shelf_edit_name') })
        .maxLength(200).onChange((value: string): void => { this.title = value; })
      Row({ space: 12 }) {
        ForEach([this.cover], (coverUrl: string) => {
          CoverImage({ url: coverUrl, title: this.title, imgWidth: 66, imgHeight: 88, useFixedHeight: true })
        }, (coverUrl: string): string => coverUrl)
        Column({ space: 8 }) {
          Button($r('app.string.shelf_edit_local_cover')).backgroundColor(AppColor.Brand).fontColor(Color.White)
            .onClick((): void => { this.pickCover(); }).enabled(!this.saving)
          Button($r('app.string.shelf_edit_source_cover')).backgroundColor(AppColor.Brand).fontColor(Color.White)
            .onClick((): void => { this.findCovers(); })
            .enabled(!this.saving && !this.searching)
        }.layoutWeight(1)
      }.width('100%')
      } else {
      List({ space: 8 }) {
        ListItem() {
          Text($r('app.string.shelf_group_none')).width('100%').padding(16)
            .fontColor(this.group === '' ? AppColor.Brand : $r('sys.color.font_primary'))
            .backgroundColor(this.group === '' ? AppColor.BrandSoft : Color.Transparent).borderRadius(12)
            .onClick((): void => { if (!this.saving) this.group = ''; })
        }
        ForEach(this.groups, (name: string) => {
          ListItem() {
            Row({ space: 8 }) {
              Text(name).layoutWeight(1).padding(16).maxLines(2)
                .fontColor(this.group === name ? AppColor.Brand : $r('sys.color.font_primary'))
                .onClick((): void => { if (!this.saving) this.group = name; })
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.trash')).fontSize(20).fontColor([$r('sys.color.ohos_id_color_warning')])
              }.width(44).height(44).backgroundColor(Color.Transparent).enabled(!this.saving)
                .accessibilityText($r('app.string.shelf_group_delete_title'))
                .onClick((): void => { this.deleteGroup(name); })
            }.width('100%').padding({ right: 8 }).borderRadius(12)
              .backgroundColor(this.group === name ? AppColor.BrandSoft : Color.Transparent)
          }
        }, (name: string): string => name)
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
      Row({ space: 8 }) {
        TextInput({ text: this.newGroup, placeholder: $r('app.string.shelf_group_new') }).maxLength(40).layoutWeight(1)
          .onChange((value: string): void => { this.newGroup = value; })
        Button($r('app.string.common_add')).enabled(!!this.newGroup.trim() && !this.saving)
          .backgroundColor(AppColor.Brand).fontColor(Color.White)
          .onClick((): void => {
            const name = this.newGroup.trim();
            if (!this.groups.includes(name)) this.groups = this.groups.concat(name);
            this.group = name;
            this.newGroup = '';
          })
      }.width('100%')
      }
      if (this.searching) { LoadingProgress().width(24).height(24).color(AppColor.Brand) }
      if (this.error) { Text(this.error).fontColor($r('sys.color.font_secondary')).fontSize(12) }
      if (!this.groupOnly) {
      List({ space: 8 }) {
        LazyForEach(this.covers, (candidate: Book) => {
          ListItem() {
            Row({ space: 12 }) {
              CoverImage({ url: candidate.cover, imgWidth: 48, imgHeight: 64, useFixedHeight: true })
              Text(candidate.narrator).layoutWeight(1).fontColor($r('sys.color.font_primary')).maxLines(2)
            }.width('100%').onClick((): void => { this.cover = candidate.cover; })
          }
        }, (candidate: Book): string => candidate.id)
      }.layoutWeight(1).width('100%').scrollBar(BarState.Auto).padding({ right: 8 })
      }
      Button($r('app.string.common_save')).width('100%').backgroundColor(AppColor.Brand).fontColor(Color.White)
        .enabled(!this.saving && !!this.title.trim()).onClick((): void => { this.save(); })
    }.padding({ left: 24, right: 24, top: 16, bottom: 28 }).width('100%').height('100%')
  }
}
