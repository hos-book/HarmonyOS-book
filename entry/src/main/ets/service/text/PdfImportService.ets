import { taskpool } from '@kit.ArkTS';
import { renderPdfPages } from './PdfImportWorker';

/** 仅在确认 PDFKit 可用后动态加载本模块。 */
export class PdfImportService {
  static async render(path: string, directory: string,
    progress: (completed: number, total: number) => void): Promise<number> {
    const task = new taskpool.Task(renderPdfPages, path, directory);
    task.onReceiveData((completed: number, total: number): void => { progress(completed, total); });
    try {
      const count = Number(await taskpool.execute(task));
      if (!Number.isInteger(count) || count <= 0 || count > 2000) throw new Error('import_pdf_invalid');
      progress(count, count);
      return count;
    } finally { task.onReceiveData(); }
  }
}
