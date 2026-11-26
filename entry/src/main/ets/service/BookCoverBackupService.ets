import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { BookPresentation, BookPresentationEdit } from '../model/BookPresentation';
import { PreferenceService } from './PreferenceService';

export class BookCoverBackup {
  bookId: string = '';
  cover: string = '';
  imageBase64: string = '';
}

export class BookCoverBackupService {
  static async capture(): Promise<BookCoverBackup[]> {
    const covers: BookCoverBackup[] = [];
    for (const edit of BookPresentation.edits) {
      if (!edit.cover) continue;
      const saved = new BookCoverBackup();
      saved.bookId = edit.bookId;
      if (edit.cover.startsWith('file://') || edit.cover.startsWith('/')) {
        const path = edit.cover.startsWith('file://') ? edit.cover.substring('file://'.length) : edit.cover;
        const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
        try {
          const bytes = new Uint8Array((await fileIo.stat(file.fd)).size);
          if (await fileIo.read(file.fd, bytes.buffer) !== bytes.byteLength) {
            throw new Error('Cover read incomplete');
          }
          saved.imageBase64 = new util.Base64Helper().encodeToStringSync(bytes);
        } finally {
          await fileIo.close(file);
        }
      } else {
        saved.cover = edit.cover;
      }
      covers.push(saved);
    }
    return covers;
  }

  static async restore(context: common.Context, covers: BookCoverBackup[]): Promise<void> {
    if (covers.length === 0) return;
    const edits: BookPresentationEdit[] = JSON.parse(JSON.stringify(BookPresentation.edits));
    for (const saved of covers) {
      let cover = saved.cover;
      if (saved.imageBase64) {
        const bytes = new util.Base64Helper().decodeSync(saved.imageBase64);
        const dir = `${context.filesDir}/edited_covers`;
        if (!await fileIo.access(dir)) await fileIo.mkdir(dir, true);
        const path = `${dir}/${util.generateRandomUUID(false)}.img`;
        const file = await fileIo.open(path,
          fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
        try {
          if (await fileIo.write(file.fd, bytes.buffer) !== bytes.byteLength) {
            throw new Error('Cover write incomplete');
          }
        } finally {
          await fileIo.close(file);
        }
        cover = `file://${path}`;
      }
      let edit = edits.find((item: BookPresentationEdit): boolean => item.bookId === saved.bookId);
      if (!edit) {
        edit = new BookPresentationEdit();
        edit.bookId = saved.bookId;
        edits.push(edit);
      }
      edit.cover = cover;
    }
    await PreferenceService.saveBookPresentation(edits, BookPresentation.groups.slice());
  }
}
