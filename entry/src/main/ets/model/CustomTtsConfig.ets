/** HTTP 导入音色或已安装的本地模型音色；本地项不接受用户提供的文件路径。 */
export class CustomTtsConfig {
  provider: string = 'http';
  modelId: string = '';
  speakerId: number = -1;
  id: string = '';
  name: string = '';
  group: string = '';
  tier: string = '';
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
