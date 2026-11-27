import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { CustomTtsConfig } from '../../model/CustomTtsConfig';
import { JianjianAiConfig, JianjianAiError, JianjianAiErrorCode, JianjianAiMessage } from '../../model/JianjianAi';
import { RoleAiState, RoleInferenceRequest, RoleModelAnswer, RoleSpeaker,
  RoleVoiceMatch, RoleVoiceOption, RoleVoiceRequest } from '../../model/RoleSpeech';
import { JianjianAiService } from '../JianjianAiService';
import { RoleVoiceMetadata } from './RoleVoiceMetadata';
import { RoleVoiceMatcher } from './RoleVoiceMatcher';

/** 复用已有 AI 配置，根据人物上下文与音色资料安排角色声音。 */
export class RoleAiService {
  static readonly instance: RoleAiService = new RoleAiService();
  readonly state: RoleAiState = new RoleAiState();
  private store: preferences.Preferences | null = null;
  private context: common.Context | null = null;
  private config: JianjianAiConfig = new JianjianAiConfig();
  private client: JianjianAiService = new JianjianAiService();
  private readonly voicePrompt: string = 'voices 是已启用音色目录，id 是真实音色 ID，description 是名称、分组与已有性别资料，' +
    'gender 是音色明确性别，ages 是适用听感年龄数组，pending 和空数组表示资料待确认。' +
    '年龄统一为 child 儿童、teen 少年、young 青年、middle 中年、senior 老年、pending 待确认。' +
    '人物年龄采用当前外貌与声音体现的听感年龄，仙侠寿命等设定单独放在 profile；先依据上下文明确证据，再沿用已有年龄。' +
    'usedCount 是本书其他人物已使用该音色的数量，preferred 表示当前优先候选。先依据原文与人物 profile 确定性别、年龄和声线特点，' +
    '再选匹配音色：明确性别优先，其次年龄、声线和语气，匹配程度相当时优先 preferred 音色并兼顾角色声音区分。' +
    '音色只提供编号或姓名时，仅采用其明确资料；人物特征缺少依据时在 profile 中标记待确认。' +
    'voiceId 只填写 voices 中的 id，目录为空或匹配依据欠缺时填空字符串，沿用默认对白声音。' +
    '匹配程度相当时优先 usedCount 较少的声音，并在本批新增人物之间分配有区分的声音。' +
    '人物 gender 只填 male、female、pending，按原文证据判断；证据待补充时填 pending。' +
    'genderSource 为 manual 的人物沿用已保存 gender，并以该性别选声。' +
    'ageSource 为 manual 的人物沿用已保存 age，并以该年龄选声。' +
    '后文出现更明确的性别、年龄证据时补全人物资料；自动绑定与新资料冲突时重新选声，manual 音色绑定由应用保留。' +
    'profile 用 60 字以内概括原文支持的性别、年龄和声线特征。';

  async initialize(context: common.Context): Promise<void> {
    this.context = context;
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

  private async chat(client: JianjianAiService, messages: JianjianAiMessage[], prompt: string): Promise<string> {
    const context = this.context;
    if (context === null) throw new JianjianAiError(JianjianAiErrorCode.CONFIG);
    return client.chat(context, messages, prompt, (config: JianjianAiConfig): void => {
      this.config = config;
      this.state.model = config.model;
    });
  }

  static voiceOptions(configs: CustomTtsConfig[], selected: string): RoleVoiceOption[] {
    return configs.filter((item: CustomTtsConfig): boolean => item.enabled).map((item: CustomTtsConfig): RoleVoiceOption => {
      const voice = new RoleVoiceOption();
      voice.id = item.id;
      voice.description = item.group ? `${item.name}；${item.group}` : item.name;
      const traits = RoleVoiceMetadata.traits(item);
      if (item.voiceTraitsSource === 'manual') {
        voice.gender = RoleVoiceMetadata.gender(item.voiceGender); voice.ages = item.voiceAges.slice();
        if (item.voiceDescription) voice.description += '；' + item.voiceDescription;
      } else if (traits) {
        voice.gender = traits.gender; voice.ages = RoleVoiceMetadata.voiceAges(traits.age);
        if (traits.description) voice.description += '；' + traits.description;
      }
      voice.preferred = item.id !== selected;
      return voice;
    });
  }

  static gender(value: string | undefined): string {
    return RoleVoiceMetadata.gender(value);
  }

  private static voicePayload(voices: RoleVoiceOption[], known: RoleSpeaker[], roleId: string = ''):
    [string, string, string, string[], number, boolean][] {
    return voices.map((voice: RoleVoiceOption): [string, string, string, string[], number, boolean] => {
      const usedCount = known.filter((speaker: RoleSpeaker): boolean =>
        speaker.id !== roleId && speaker.voiceId === voice.id).length;
      return [voice.id, voice.description, voice.gender, voice.ages, usedCount, voice.preferred && usedCount === 0];
    });
  }

  static voiceMatch(answer: RoleVoiceMatch, voices: RoleVoiceOption[]): RoleVoiceMatch {
    if (answer === null || typeof answer.profile !== 'string' || typeof answer.voiceId !== 'string') {
      throw new JianjianAiError(JianjianAiErrorCode.INVALID);
    }
    const match = new RoleVoiceMatch();
    match.profile = answer.profile.trim(); match.voiceId = answer.voiceId.trim();
    match.gender = RoleAiService.gender(answer.gender);
    match.age = RoleVoiceMetadata.age(answer.age);
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
      'voices 中每行为 [id, description, gender, ages, usedCount, preferred]。' + this.voicePrompt +
      '已有角色的已保存 voiceId 位于 voices 且符合当前性别与年龄时返回原 voiceId；' +
      'voiceSource 为 manual 且原绑定为空时沿用默认对白声音，voiceId 填空字符串。' +
      'voiceSource 为 ai 且原绑定为空时，结合本次明确的人物资料重新选声。' +
      '已有角色原绑定的 voiceId 已移出 voices 时，结合原文、人物性别与 profile 重新匹配并返回新 voiceId；' +
      'voiceSource 为 manual 的仍可用绑定由应用持续保留。' +
      '同一人物在本次所有对白中使用同一 gender、age 和 voiceId；新人物按特征选声。' +
      '只返回 JSON 数组，每个元素为 {"id":对白编号,"speaker":"人物名或?","gender":"male或female或pending",' +
      '"age":"child或teen或young或middle或senior或pending","profile":"人物特征","voiceId":"音色ID或空字符串"}。' +
      '每个对白编号恰好返回一次，保持原文完整，回复直接以 [ 开始、以 ] 结束。';
    const payload = new RoleAiPayload();
    payload.context = request.context;
    payload.lines = request.lines;
    payload.known = known;
    payload.voices = RoleAiService.voicePayload(voices, known);
    const reply = await this.chat(this.client, [new JianjianAiMessage('user', JSON.stringify(payload))], prompt);
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
      'voices 中每行为 [id, description, gender, ages, usedCount, preferred]。' +
      '只返回 {"gender":"male或female或pending","age":"child或teen或young或middle或senior或pending",' +
      '"profile":"人物特征","voiceId":"音色ID或空字符串"}，回复直接以 { 开始、以 } 结束。';
    const payload = new RoleVoicePayload();
    payload.speaker = request.speaker; payload.context = request.context; payload.known = request.known;
    payload.voices = RoleAiService.voicePayload(request.voices, request.known, request.speaker.id);
    const reply = await this.chat(client, [new JianjianAiMessage('user', JSON.stringify(payload))], prompt);
    try {
      const answer: RoleVoiceMatch = JSON.parse(reply);
      const match = RoleAiService.voiceMatch(answer, request.voices);
      if (request.speaker.genderSource === 'manual' || match.gender === 'pending') {
        match.gender = RoleAiService.gender(request.speaker.gender);
      }
      if (request.speaker.ageSource === 'manual' || match.age === 'pending') {
        match.age = RoleVoiceMetadata.age(request.speaker.age);
      }
      match.voiceId = RoleVoiceMatcher.choose(match.voiceId, request.voices, match.gender, match.age,
        request.known, request.speaker.id);
      return match;
    } catch (_error) { throw new JianjianAiError(JianjianAiErrorCode.INVALID); }
  }
}

class RoleAiPayload extends RoleInferenceRequest {
  known: RoleSpeaker[] = [];
  voices: [string, string, string, string[], number, boolean][] = [];
}

class RoleVoicePayload {
  speaker: RoleSpeaker = new RoleSpeaker();
  context: string = '';
  known: RoleSpeaker[] = [];
  voices: [string, string, string, string[], number, boolean][] = [];
}
