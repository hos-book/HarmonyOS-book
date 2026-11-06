import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { taskpool } from '@kit.ArkTS';
import { extract } from 'libcba_archive.so';

/** ACE 解码与图片检查均在任务池执行；原始文件名仅用于排序。 */
@Concurrent
export async function extractCbaPages(uri: string, directory: string): Promise<number> {
  const source = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
  let paths: string[];
  try {
    paths = extract(source.fd, directory, (completed: number, total: number): void => {
      taskpool.Task.sendData(completed, total);
    });
  } finally { await fileIo.close(source); }
  if (paths.length === 0 || paths.length > 50000) throw new Error('import_cba_no_images');
  for (let index = 0; index < paths.length; index++) {
    const file = await fileIo.open(paths[index], fileIo.OpenMode.READ_ONLY);
    try {
      const decoder = image.createImageSource(file.fd);
      try {
        const size = (await decoder.getImageInfo()).size;
        if (size.width <= 0 || size.height <= 0 || size.width * size.height > 32 * 1024 * 1024) {
          throw new Error('import_cba_limit');
        }
      } finally { await decoder.release(); }
    } catch (error) {
      if (error instanceof Error && error.message === 'import_cba_limit') throw error;
      throw new Error('import_cba_image');
    } finally { await fileIo.close(file); }
  }
  return paths.length;
}
