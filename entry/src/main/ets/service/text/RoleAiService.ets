import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { CustomTtsConfig } from '../../model/CustomTtsConfig';
import { isOfflineTtsProvider } from '../../model/OfflineTtsCatalog';
import { JianjianAiConfig, JianjianAiError, JianjianAiErrorCode, JianjianAiMessage } from '../../model/JianjianAi';
import { RoleAiState, RoleInferenceRequest, RoleModelAnswer, RoleSpeaker,
  RoleVoiceMatch, RoleVoiceOption, RoleVoiceRequest } from '../../model/RoleSpeech';
import { JianjianAiService } from '../JianjianAiService';

/** 复用已有 AI 配置，根据人物上下文与音色资料安排角色声音。 */
export class RoleAiService {
  static readonly instance: RoleAiService = new RoleAiService();
  readonly state: RoleAiState = new RoleAiState();
  private store: preferences.Preferences | null = null;
  private config: JianjianAiConfig = new JianjianAiConfig();
  private client: JianjianAiService = new JianjianAiService();
  private readonly voicePrompt: string = 'voices 是已启用音色目录，id 是真实音色 ID，description 是名称、分组与已有性别资料，' +
    'preferred 表示兼顾当前音色系列与角色区分的优先候选。先依据原文与人物 profile 确定性别、年龄和声线特点，' +
    '再选匹配音色：明确性别优先，其次年龄、声线和语气，匹配程度相当时优先 preferred 音色并兼顾角色声音区分。' +
    '音色只提供编号或姓名时，仅采用其明确资料；人物特征缺少依据时在 profile 中标记待确认。' +
    'voiceId 只填写 voices 中的 id，目录为空或匹配依据欠缺时填空字符串，沿用默认对白声音。' +
    'profile 用 60 字以内概括原文支持的性别、年龄和声线特征。';

  async initialize(context: common.Context): Promise<void> {
    if (this.store === null) {
      this.store = await preferences.getPreferences(context, { name: 'role_speech_model' });
      this.state.enabled = this.store.getSync('enabled', false) === true;
    }
    this.config = await JianjianAiService.loadConfig(context);
    this.state.configured = this.config.address.length > 0 && this.config.apiKey.length > 0 && this.config.model.length > 0;
    this.state.model = this.config.model;
  }

  async setEnabled(enabled: boolean): Promise<void> {
    if (this.store === null) return;
    if (enabled) JianjianAiService.normalize(this.config, true);
    await this.store.put('enabled', enabled);
    await this.store.flush();
    this.state.enabled = enabled;
    if (!enabled) this.cancel();
  }

  cancel(): void { this.client.cancel(); }

  static voiceOptions(configs: CustomTtsConfig[], selected: string): RoleVoiceOption[] {
    const current = configs.find((item: CustomTtsConfig): boolean => item.id === selected);
    return configs.filter((item: CustomTtsConfig): boolean => item.enabled).map((item: CustomTtsConfig): RoleVoiceOption => {
      const voice = new RoleVoiceOption();
      voice.id = item.id;
      voice.description = item.group ? `${item.name}；${item.group}` : item.name;
      if (item.provider === 'local-kokoro') voice.description += item.speakerId <= 57 ? '；女声' : '；男声';
      voice.preferred = item.id !== selected && (!current || !isOfflineTtsProvider(current.provider) ||
        item.provider === current.provider);
      return voice;
    });
  }

  static voiceMatch(answer: RoleVoiceMatch, voices: RoleVoiceOption[]): RoleVoiceMatch {
    if (answer === null || typeof answer.profile !== 'string' || typeof answer.voiceId !== 'string') {
      throw new JianjianAiError(JianjianAiErrorCode.INVALID);
    }
    const match = new RoleVoiceMatch();
    match.profile = answer.profile.trim(); match.voiceId = answer.voiceId.trim();
    if (match.voiceId && !voices.some((voice: RoleVoiceOption): boolean => voice.id === match.voiceId)) {
      throw new JianjianAiError(JianjianAiErrorCode.INVALID);
    }
    return match;
  }

  async infer(request: RoleInferenceRequest, known: RoleSpeaker[], voices: RoleVoiceOption[]): Promise<RoleModelAnswer[]> {
    const prompt = '你是小说角色配音分析助手。用户提供的 context 是小说原文，lines 是待识别对白的编号、位置与 text 原文，' +
      'known 是本书已有角色的姓名、人物特征与已保存音色。只分析这些素材，依据对白前后叙述、称呼和人物关系确定说话人。' +
      '人物姓名优先沿用 known 中的 name，新增人物使用原文中出现的明确姓名或称呼；身份待确认时 speaker 填问号。' +
      '位置采用 JavaScript UTF-16 字符串的 start（含）与 end（开区间）。' +
      'voices 中每行为 [id, description, preferred]。' + this.voicePrompt +
      '已有角色由应用沿用已保存音色，本次 voiceId 填空字符串；voiceSource 为 manual 时代表用户手动选择。' +
      '同一人物在本次所有对白中使用同一 voiceId；新人物按特征选声。' +
      '只返回 JSON 数组，每个元素为 {"id":对白编号,"speaker":"人物名或?","profile":"人物特征","voiceId":"音色ID或空字符串"}。' +
      '每个对白编号恰好返回一次，保持原文完整，回复直接以 [ 开始、以 ] 结束。';
    const payload = new RoleAiPayload();
    payload.context = request.context;
    payload.lines = request.lines;
    payload.known = known;
    payload.voices = voices.map((voice: RoleVoiceOption): [string, string, boolean] =>
      [voice.id, voice.description, voice.preferred]);
    const reply = await this.client.chat(this.config, [new JianjianAiMessage('user', JSON.stringify(payload))], prompt);
    try {
      const answers: RoleModelAnswer[] = JSON.parse(reply);
      if (!Array.isArray(answers)) throw new Error('role_ai_response');
      return answers;
    } catch (_error) { throw new JianjianAiError(JianjianAiErrorCode.INVALID); }
  }

  async reassign(request: RoleVoiceRequest, client: JianjianAiService): Promise<RoleVoiceMatch> {
    const prompt = '你是小说角色配音助手。为 speaker 指定的单个人物重新匹配音色。' +
      'context 是该人物所在的正文片段，known 是本书已有角色资料。结合原文和已有 profile 判断人物特点。' +
      this.voicePrompt + '本次用户主动要求重新选声，请依据人物特点重新评估 speaker 的现有音色。' +
      '只返回 {"profile":"人物特征","voiceId":"音色ID或空字符串"}，回复直接以 { 开始、以 } 结束。';
    const reply = await client.chat(this.config, [new JianjianAiMessage('user', JSON.stringify(request))], prompt);
    try {
      const answer: RoleVoiceMatch = JSON.parse(reply);
      return RoleAiService.voiceMatch(answer, request.voices);
    } catch (_error) { throw new JianjianAiError(JianjianAiErrorCode.INVALID); }
  }
}

class RoleAiPayload extends RoleInferenceRequest {
  known: RoleSpeaker[] = [];
  voices: [string, string, boolean][] = [];
}
