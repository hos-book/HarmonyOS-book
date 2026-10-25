/** 用户导入的 HTTP 语音配置；表达式只在有界 QuickJS 中执行。 */
export class CustomTtsConfig {
  id: string = '';
  name: string = '';
  enabled: boolean = true;
  url: string = '';
  method: string = 'GET';
  body: string = '';
  header: string = '{}';
  contentType: string = '';
}

export class CustomTtsImportResult {
  configs: CustomTtsConfig[] = [];
  failedFiles: number = 0;
}
