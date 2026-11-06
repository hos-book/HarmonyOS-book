import { taskpool } from '@kit.ArkTS';
import { extractCbaPages } from './CbaImportWorker';

export class CbaImportService {
  static async extract(uri: string, directory: string,
    progress: (completed: number, total: number) => void): Promise<number> {
    const task = new taskpool.Task(extractCbaPages, uri, directory);
    task.onReceiveData((completed: number, total: number): void => { progress(completed, total); });
    try {
      const count = Number(await taskpool.execute(task));
      if (!Number.isInteger(count) || count <= 0 || count > 50000) throw new Error('import_cba_invalid');
      return count;
    } finally { task.onReceiveData(); }
  }
}
