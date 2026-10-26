import { pdfService } from '@kit.PDFKit';
import { image } from '@kit.ImageKit';
import { fileIo, statfs } from '@kit.CoreFileKit';
import { taskpool } from '@kit.ArkTS';

/** 在任务池内逐页渲染，不在 UI 线程解析 PDF，也不同时保留多页像素。 */
@Concurrent
export async function renderPdfPages(path: string, directory: string): Promise<number> {
  const document = new pdfService.PdfDocument();
  try {
    const result = document.loadDocument(path);
    if (result === pdfService.ParseResult.PARSE_ERROR_PASSWORD) throw new Error('import_pdf_password');
    if (result !== pdfService.ParseResult.PARSE_SUCCESS) throw new Error('import_pdf_invalid');
    const count = document.getPageCount();
    if (!Number.isInteger(count) || count <= 0) throw new Error('import_pdf_invalid');
    if (count > 2000) throw new Error('import_pdf_limit');
    taskpool.Task.sendData(0, count);
    let totalBytes = 0;
    for (let index = 0; index < count; index++) {
      const page = document.getPage(index);
      try {
        const width = page.getWidth();
        const height = page.getHeight();
        if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
          throw new Error('import_pdf_invalid');
        }
        const scale = Math.min(2, 3072 / Math.max(width, height), Math.sqrt(4 * 1024 * 1024 / (width * height)));
        const targetWidth = Math.max(1, Math.floor(width * scale));
        const targetHeight = Math.max(1, Math.floor(height * scale));
        const matrix = new pdfService.PdfMatrix();
        matrix.x = 0; matrix.y = 0;
        matrix.width = scale; matrix.height = scale;
        // PDF 自带的页面旋转由渲染器处理，此处不叠加旋转。
        matrix.rotate = 0;
        const options = new pdfService.PixelOptions();
        options.isGray = false; options.drawAnnotations = true; options.isTransparent = false;
        const pixels = page.getAreaPixelMapWithOptions(matrix, targetWidth, targetHeight, options);
        let bytes: ArrayBuffer;
        try {
          const packer = image.createImagePacker();
          try { bytes = await packer.packToData(pixels, { format: 'image/jpeg', quality: 92 }); }
          finally { await packer.release(); }
        } finally { await pixels.release(); }
        totalBytes += bytes.byteLength;
        if (bytes.byteLength === 0) throw new Error('import_pdf_invalid');
        if (bytes.byteLength > 8 * 1024 * 1024 || totalBytes > 512 * 1024 * 1024) {
          throw new Error('import_pdf_limit');
        }
        if (await statfs.getFreeSize(directory) < bytes.byteLength + 256 * 1024 * 1024) {
          throw new Error('import_pdf_space');
        }
        const output = await fileIo.open(`${directory}/image_${index}_0.img`,
          fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
        try {
          let offset = 0;
          while (offset < bytes.byteLength) {
            const written = await fileIo.write(output.fd, bytes.slice(offset));
            if (written <= 0) throw new Error('import_pdf_write_failed');
            offset += written;
          }
        } finally { await fileIo.close(output); }
      } finally { page.release(); }
      taskpool.Task.sendData(index + 1, count);
    }
    return count;
  } finally { document.releaseDocument(); }
}
