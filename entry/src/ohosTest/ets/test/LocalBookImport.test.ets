import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { describe, expect, it } from '@ohos/hypium';
import { LocalBookImportService, LocalImportFile } from '../../../main/ets/service/LocalBookImportService';
import { OnlineTextPaginator } from '../../../main/ets/service/text/OnlineTextPaginator';
import { DiagnosticLogService } from '../../../main/ets/service/DiagnosticLogService';

const EPUB_FIXTURE: string = 'UEsDBBQAAAAAAKRRNl1vYassFAAAABQAAAAIAAAAbWltZXR5cGVhcHBsaWNhdGlvbi9lcHViK3ppcFBLAwQUAAAAAACkUTZdHgvXyd0AAADdAAAAFgAAAE1FVEEtSU5GL2NvbnRhaW5lci54bWw8P3htbCB2ZXJzaW9uPSIxLjAiPz48Y29udGFpbmVyIHZlcnNpb249IjEuMCIgeG1sbnM9InVybjpvYXNpczpuYW1lczp0YzpvcGVuZG9jdW1lbnQ6eG1sbnM6Y29udGFpbmVyIj48cm9vdGZpbGVzPjxyb290ZmlsZSBmdWxsLXBhdGg9Ik9FQlBTL2NvbnRlbnQub3BmIiBtZWRpYS10eXBlPSJhcHBsaWNhdGlvbi9vZWJwcy1wYWNrYWdlK3htbCIvPjwvcm9vdGZpbGVzPjwvY29udGFpbmVyPlBLAwQUAAAAAACkUTZdQyqb3PMCAADzAgAAEQAAAE9FQlBTL2NvbnRlbnQub3BmPD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0idXRmLTgiPz48cGFja2FnZSB2ZXJzaW9uPSIyLjAiIHVuaXF1ZS1pZGVudGlmaWVyPSJpZCIgeG1sbnM9Imh0dHA6Ly93d3cuaWRwZi5vcmcvMjAwNy9vcGYiPjxtZXRhZGF0YSB4bWxuczpkYz0iaHR0cDovL3B1cmwub3JnL2RjL2VsZW1lbnRzLzEuMS8iPjxkYzp0aXRsZT7nroDlkKxFUFVC6aqM6K+BPC9kYzp0aXRsZT48ZGM6Y3JlYXRvcj7mnKzlnLDmtYvor5U8L2RjOmNyZWF0b3I+PGRjOmxhbmd1YWdlPnpoLUNOPC9kYzpsYW5ndWFnZT48ZGM6aWRlbnRpZmllciBpZD0iaWQiPmhzZGEtZml4dHVyZTwvZGM6aWRlbnRpZmllcj48bWV0YSBuYW1lPSJjb3ZlciIgY29udGVudD0iY292ZXItaW1hZ2UiLz48L21ldGFkYXRhPjxtYW5pZmVzdD48aXRlbSBpZD0ibmN4IiBocmVmPSJ0b2MubmN4IiBtZWRpYS10eXBlPSJhcHBsaWNhdGlvbi94LWR0Ym5jeCt4bWwiLz48aXRlbSBpZD0iYzEiIGhyZWY9ImMxLnhodG1sIiBtZWRpYS10eXBlPSJhcHBsaWNhdGlvbi94aHRtbCt4bWwiLz48aXRlbSBpZD0iYzIiIGhyZWY9ImMyLnhodG1sIiBtZWRpYS10eXBlPSJhcHBsaWNhdGlvbi94aHRtbCt4bWwiLz48aXRlbSBpZD0iY292ZXItaW1hZ2UiIGhyZWY9IkltYWdlcy9jb3Zlci5wbmciIG1lZGlhLXR5cGU9ImltYWdlL3BuZyIvPjwvbWFuaWZlc3Q+PHNwaW5lIHRvYz0ibmN4Ij48aXRlbXJlZiBpZHJlZj0iYzEiLz48aXRlbXJlZiBpZHJlZj0iYzIiLz48L3NwaW5lPjwvcGFja2FnZT5QSwMEFAAAAAAApFE2XSDnyM3YAQAA2AEAAA0AAABPRUJQUy90b2MubmN4PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0idXRmLTgiPz48bmN4IHhtbG5zPSJodHRwOi8vd3d3LmRhaXN5Lm9yZy96Mzk4Ni8yMDA1L25jeC8iIHZlcnNpb249IjIwMDUtMSI+PGhlYWQ+PG1ldGEgbmFtZT0iZHRiOnVpZCIgY29udGVudD0iaHNkYS1maXh0dXJlIi8+PC9oZWFkPjxkb2NUaXRsZT48dGV4dD7nroDlkKxFUFVC6aqM6K+BPC90ZXh0PjwvZG9jVGl0bGU+PG5hdk1hcD48bmF2UG9pbnQgaWQ9Im4xIiBwbGF5T3JkZXI9IjEiPjxuYXZMYWJlbD48dGV4dD7nrKzkuIDnq6Ag5rWL6K+VPC90ZXh0PjwvbmF2TGFiZWw+PGNvbnRlbnQgc3JjPSJjMS54aHRtbCIvPjwvbmF2UG9pbnQ+PG5hdlBvaW50IGlkPSJuMiIgcGxheU9yZGVyPSIyIj48bmF2TGFiZWw+PHRleHQ+56ys5LqM56ugIOWujOaIkDwvdGV4dD48L25hdkxhYmVsPjxjb250ZW50IHNyYz0iYzIueGh0bWwiLz48L25hdlBvaW50PjwvbmF2TWFwPjwvbmN4PlBLAwQUAAAAAACkUTZdVu0a1cEAAADBAAAADgAAAE9FQlBTL2MxLnhodG1sPD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0idXRmLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCI+PGhlYWQ+PHRpdGxlPuesrDHnq6A8L3RpdGxlPjwvaGVhZD48Ym9keT48aDE+56ysMeeroDwvaDE+PHA+6L+Z5pivIEVQVUIg5a+85YWl6aqM6K+B56ysMeeroOOAgjwvcD48L2JvZHk+PC9odG1sPlBLAwQUAAAAAACkUTZd/LujEMEAAADBAAAADgAAAE9FQlBTL2MyLnhodG1sPD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0idXRmLTgiPz48aHRtbCB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCI+PGhlYWQ+PHRpdGxlPuesrDLnq6A8L3RpdGxlPjwvaGVhZD48Ym9keT48aDE+56ysMueroDwvaDE+PHA+6L+Z5pivIEVQVUIg5a+85YWl6aqM6K+B56ysMueroOOAgjwvcD48L2JvZHk+PC9odG1sPlBLAwQUAAAAAACkUTZdn07eCaMAAACjAAAAFgAAAE9FQlBTL0ltYWdlcy9jb3Zlci5wbmeJUE5HDQoaCgAAAA1JSERSAAAAPAAAAFoIAgAAAGszomIAAABqSURBVHic7c4BCQAgEAAxq9nCtGYzhvcwWICtu8846/tAOkxaWjpAWlo6QFpaOkBaWjpAWlo6QFpaOkBaWjpAWlo6QFpaOkBaWjpAWlo6QFpaOkBaWjpAWlo6QFpaOkBaWjpAWlo6YGT6AQaIRM224tKnAAAAAElFTkSuQmCCUEsBAhQAFAAAAAAApFE2XW9hqywUAAAAFAAAAAgAAAAAAAAAAAAAAIABAAAAAG1pbWV0eXBlUEsBAhQAFAAAAAAApFE2XR4L18ndAAAA3QAAABYAAAAAAAAAAAAAAIABOgAAAE1FVEEtSU5GL2NvbnRhaW5lci54bWxQSwECFAAUAAAAAACkUTZdQyqb3PMCAADzAgAAEQAAAAAAAAAAAAAAgAFLAQAAT0VCUFMvY29udGVudC5vcGZQSwECFAAUAAAAAACkUTZdIOfIzdgBAADYAQAADQAAAAAAAAAAAAAAgAFtBAAAT0VCUFMvdG9jLm5jeFBLAQIUABQAAAAAAKRRNl1W7RrVwQAAAMEAAAAOAAAAAAAAAAAAAACAAXAGAABPRUJQUy9jMS54aHRtbFBLAQIUABQAAAAAAKRRNl38u6MQwQAAAMEAAAAOAAAAAAAAAAAAAACAAV0HAABPRUJQUy9jMi54aHRtbFBLAQIUABQAAAAAAKRRNl2fTt4JowAAAKMAAAAWAAAAAAAAAAAAAACAAUoIAABPRUJQUy9JbWFnZXMvY292ZXIucG5nUEsFBgAAAAAHAAcAsAEAACEJAAAAAA==';

const MOBI_FIXTURE: string = 'Rml4dHVyZQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQk9PS01PQkkAAAAAAAAAAAAJAAAAmAAAAAAAAAHKAAAAAAAAAesAAAAAAAACDAAAAAAAAAItAAAAAAAAAk4AAAAAAAACbwAAAAAAAAKQAAAAAAAAApUAAAAAAAAAAgAAAAAAsgAHEAAAAAAATU9CSQAAAOgAAAACAAD96QAAAAAAAAAGAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEkAAAADgAAAAAAAAAAAAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEVYVEgAAAAsAAAAAgAAAGQAAAAU5rWL6K+V5L2c6ICFAAAAyQAAAAwAAAAATU9CSSDmtYvor5XkuaYIPGh0bWw+PGgIZWFkPjx0aXQIbGU+5b+955UFpTwvdGkIdGxlPjwvaGUIYWQ+PGJvZHkIPjxoMT7nrKwF5LiA56sIoCDliJ3op4EIPC9oMT48cD4I5Lit5paH8J8FmIAgJmEIbXA7IOato+YIloc8L3A+PG0IYnA6cGFnZWIFcmVhay8IPjxoMj7nrKwI5LqM56ugIOkIh43pgKI8L2gFMj48cD4I56ys5LqM56sIoOWGheWuuTwIL3A+PC9ib2QFeT48L2gEdG1sPolQTkcNChoKAAAADUlIRFIAAAA8AAAAWggCAAAAazOiYgAAAGpJREFUeJztzlEJACAQQDGjGNXS/hvDdzBYgK179jjr+0A6TFpaOkBaWjpAWlo6QFpaOkBaWjpAWlo6QFpaOkBaWjpAWlo6QFpaOkBaWjpAWlo6QFpaOkBaWjpAWlo6QFpaOkBaWjpgZPoBl+Rg6Bn05UQAAAAASUVORK5CYII=';

export default function localBookImportTest(): void {
  // 由 scripts/create-epub-benchmark.py 临时生成测试资源；不进入正式 HAP。
  describe('LocalBookImportBenchmark', (): void => {
    it('imports_generated_epub', 0, async (): Promise<void> => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const context = delegator.getAppContext();
      let bytes: Uint8Array;
      try {
        bytes = await context.createModuleContext('entry_test').resourceManager.getRawFileContent('import-benchmark.epub');
      } catch (_missingFixture) { return; }
      const id = 'import_benchmark_' + Date.now();
      const source = context.cacheDir + '/' + id + '.epub';
      const output = await fileIo.open(source, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      try { await fileIo.write(output.fd, bytes.buffer); } finally { await fileIo.close(output); }
      let previewDirectory = '';
      DiagnosticLogService.init(context.createModuleContext('entry'));
      const logging = DiagnosticLogService.isEnabled();
      await DiagnosticLogService.setEnabled(true);
      try {
        const file = new LocalImportFile();
        file.uri = source; file.ext = '.epub'; file.name = 'EPUB benchmark';
        const started = Date.now();
        await delegator.print('EPUB_BENCH preview_start\n');
        const preview = await LocalBookImportService.preview(context, file);
        previewDirectory = preview.directory;
        const previewMs = Date.now() - started;
        await delegator.print(`EPUB_BENCH preview_done ms=${previewMs}\n`);
        const book = await LocalBookImportService.importBook(context, file, id,
          preview.title, preview.author, preview.cover, (progress: string): void => {
            if (progress.endsWith('00/5000')) delegator.print(progress + '\n');
          });
        const totalMs = Date.now() - started;
        expect(book.chapters.length).assertEqual(5000);
        for (const index of [0, 2499, 4999]) {
          expect(book.chapters[index].title).assertEqual(`第${index + 1}章 原书目录`);
          expect(await fileIo.readText(book.chapters[index].source.value)).assertContain(`章节正文-${index + 1}`);
        }
        await delegator.print(`EPUB_BENCH chapters=${book.chapters.length}; previewMs=${previewMs}; ` +
          `importMs=${totalMs - previewMs}; totalMs=${totalMs}\n`);
      } finally {
        await DiagnosticLogService.setEnabled(logging);
        try { await fileIo.unlink(source); } catch (_error) {}
        try { await fileIo.rmdir(context.filesDir + '/ebooks/' + id); } catch (_error) {}
        if (previewDirectory) { try { await fileIo.rmdir(previewDirectory); } catch (_error) {} }
      }
    });
  });
  describe('LocalBookImportDevice', (): void => {
    it('keeps native multi-paragraph scroll rows distinct', 0, (): void => {
      const text = Array.from({ length: 40 }, (_value: number, index: number): string =>
        `正文第${index}段，这是用于检查跨行和跨段显示的独立内容。`).join('\n\n');
      const pages = OnlineTextPaginator.paginate(text, 700, 1, 40, 1.9);
      expect(pages.length > 40).assertTrue();
      for (let index = 1; index < pages.length; index++) {
        expect(pages[index].startOffset >= pages[index - 1].endOffset).assertTrue();
        expect(pages[index].firstLine > pages[index - 1].firstLine).assertTrue();
        expect(pages[index].layoutTop > pages[index - 1].layoutTop).assertTrue();
      }
    });
    it('opens external ebooks and ZIP in the local import screen', 0, async (): Promise<void> => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const context = delegator.getAppContext();
      const driver = Driver.create();
      for (const ext of ['.txt', '.mobi', '.zip']) {
        const name = 'external_import_' + Date.now() + ext;
        const path = context.cacheDir + '/' + name;
        const output = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
        try {
          if (ext === '.mobi') {
            await fileIo.write(output.fd, new util.Base64Helper().decodeSync(MOBI_FIXTURE).buffer);
          } else {
            await fileIo.write(output.fd, '第一章 测试\n外部文件导入');
          }
        } finally { await fileIo.close(output); }
        try {
          const want: Want = {
            bundleName: 'com.huan.listenbook', abilityName: 'EntryAbility',
            action: 'ohos.want.action.viewData', uri: fileUri.getUriFromPath(path),
            type: ext === '.txt' ? 'general.plain-text' : ext === '.mobi' ? 'com.amazon.mobi' : 'general.zip-archive'
          };
          await delegator.startAbility(want);
          const selected = await driver.waitForComponent(ON.text(name), 8000);
          expect(selected !== null).assertTrue();
          const action = await driver.waitForComponent(ON.text('开始导入'), 3000);
          expect(action !== null).assertTrue();
          await driver.pressBack();
        } finally { await fileIo.unlink(path); }
      }
    });
    it('imports MOBI PalmDOC with Chinese metadata and local chapters', 0, async (): Promise<void> => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      const id = 'import_mobi_device_' + Date.now();
      const path = context.cacheDir + '/' + id + '.mobi';
      let previewDirectory = '';
      const output = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      try {
        const bytes = new util.Base64Helper().decodeSync(MOBI_FIXTURE);
        await fileIo.write(output.fd, bytes.buffer);
      } finally { await fileIo.close(output); }
      try {
        const picked = new LocalImportFile();
        picked.uri = path; picked.ext = '.mobi'; picked.name = 'MOBI fixture';
        const preview = await LocalBookImportService.preview(context, picked);
        previewDirectory = preview.directory;
        expect(preview.cover.endsWith('/cover.jpg')).assertTrue();
        const coverImage = image.createImageSource(preview.cover);
        try {
          const info = await coverImage.getImageInfo();
          expect(info.size.width).assertEqual(60);
          expect(info.size.height).assertEqual(90);
        } finally { await coverImage.release(); }
        expect(preview.title).assertEqual('MOBI 测试书');
        expect(preview.author).assertEqual('测试作者');
        const book = await LocalBookImportService.importBook(context, picked, id,
          preview.title, preview.author, preview.cover, (): void => {});
        expect(book.cover.endsWith('/cover.jpg')).assertTrue();
        expect((await fileIo.stat(book.cover)).size > 0).assertTrue();
        expect(book.contentType).assertEqual('text');
        expect(book.chapters.length).assertEqual(2);
        expect(book.chapters[0].title).assertEqual('第一章 初见');
        expect(await fileIo.readText(book.chapters[0].source.value)).assertContain('中文😀 & 正文');
        expect(await fileIo.readText(book.chapters[1].source.value)).assertContain('第二章内容');
      } finally {
        try { await fileIo.unlink(path); } catch (_error) {}
        try { await fileIo.rmdir(context.filesDir + '/ebooks/' + id); } catch (_error) {}
        if (previewDirectory.length > 0) {
          try { await fileIo.rmdir(previewDirectory); } catch (_error) {}
        }
      }
    });
    it('imports real EPUB with the system parser and reads local chapters', 0, async (): Promise<void> => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      const id = `import_device_test_${Date.now()}`;
      const path = `${context.cacheDir}/${id}.epub`;
      const output = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      try {
        const bytes = new util.Base64Helper().decodeSync(EPUB_FIXTURE);
        await fileIo.write(output.fd, bytes.buffer);
      } finally { await fileIo.close(output); }
      try {
        const picked = new LocalImportFile();
        picked.uri = path; picked.ext = '.epub'; picked.name = 'EPUB fixture';
        const preview = await LocalBookImportService.preview(context, picked);
        expect(preview.title).assertEqual('简听EPUB验证');
        expect(preview.author).assertEqual('本地测试');
        expect(preview.cover.endsWith('/cover.jpg')).assertTrue();
        const book = await LocalBookImportService.importBook(context, picked, id,
          preview.title, preview.author, preview.cover, (): void => {});
        await fileIo.rmdir(preview.directory);
        expect(book.contentType).assertEqual('text');
        expect(book.cover.endsWith('/cover.jpg')).assertTrue();
        expect((await fileIo.stat(book.cover)).size > 0).assertTrue();
        expect(book.chapters.length).assertEqual(2);
        const first = await fileIo.readText(book.chapters[0].source.value);
        const second = await fileIo.readText(book.chapters[1].source.value);
        expect(first).assertContain('EPUB 导入验证第1章');
        expect(second).assertContain('EPUB 导入验证第2章');
      } finally {
        try { await fileIo.unlink(path); } catch (_error) {}
        try { await fileIo.rmdir(`${context.filesDir}/ebooks/${id}`); } catch (_error) {}
      }
    });
  });
}
