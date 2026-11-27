/** HTTP 导入音色与已安装插件的音色配置。 */
export class CustomTtsConfig {
  provider: string = 'http';
  modelId: string = '';
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
  voiceGender: string = 'pending';
  voiceAges: string[] = [];
  voiceDescription: string = '';
  voiceTraitsSource: string = '';
}

export class CustomTtsImportResult {
  configs: CustomTtsConfig[] = [];
  failedFiles: number = 0;
}
