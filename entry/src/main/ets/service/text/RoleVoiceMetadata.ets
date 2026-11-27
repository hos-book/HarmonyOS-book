import { CustomTtsConfig } from '../../model/CustomTtsConfig';
import { SHENGQIAO_PROVIDER } from '../../model/ShengqiaoPlugin';

export class RoleVoiceTraits {
  key: string;
  gender: string;
  age: string;
  description: string;

  constructor(key: string, gender: string, age: string = '', description: string = '') {
    this.key = key; this.gender = gender; this.age = age; this.description = description;
  }
}

/** 华为资料沿用上游音色表，微软性别依据官方 Speech 音色目录。 */
export class RoleVoiceMetadata {
  private static readonly shengqiao: RoleVoiceTraits[] = [
    new RoleVoiceTraits('cl_14', 'female', '', '经典女声，温婉亲切'),
    new RoleVoiceTraits('cl_16', 'female', '青年', '台湾口音'),
    new RoleVoiceTraits('cl_24', 'female', '青年', '爽朗'),
    new RoleVoiceTraits('cl_32', 'female', '青年', '活泼灵动'),
    new RoleVoiceTraits('cl_100', 'female', '青年', '可爱'),
    new RoleVoiceTraits('cl_101', 'male', '青年', '理性'),
    new RoleVoiceTraits('cl_102', 'male', '青年', '谦逊'),
    new RoleVoiceTraits('cl_103', 'female', '青年', '大气'),
    new RoleVoiceTraits('cl_104', 'female', '青年', '文静'),
    new RoleVoiceTraits('cl_105', 'female', '青年', '活泼'),
    new RoleVoiceTraits('cl_106', 'female', '青年', '耐心'),
    new RoleVoiceTraits('cl_107', 'female', '青年', '理性'),
    new RoleVoiceTraits('cl_108', 'female', '儿童', '调皮'),
    new RoleVoiceTraits('cl_110', 'male', '青年', '天津口音'),
    new RoleVoiceTraits('cl_111', 'male', '青年', '东北口音'),
    new RoleVoiceTraits('sg', 'male', '', '叙事'),
    new RoleVoiceTraits('by_f', 'female', '', '播音'),
    new RoleVoiceTraits('by_m', 'male', '', '播音'),
    new RoleVoiceTraits('csm', 'male', '成年', '成熟'),
    new RoleVoiceTraits('cxd', 'male', '成年', '磁性'),
    new RoleVoiceTraits('wrn', 'male', '', '温柔'),
    new RoleVoiceTraits('ygsn', 'male', '少年', '阳光'),
    new RoleVoiceTraits('zxn', 'female', '', '知性'),
    new RoleVoiceTraits('zxyj', 'female', '', '率性'),
    new RoleVoiceTraits('qcsn', 'female', '少女', '清纯'),
    new RoleVoiceTraits('ygns', 'female', '', '阳光'),
    new RoleVoiceTraits('rmzt', 'male', '儿童', '软萌'),
    new RoleVoiceTraits('kena', 'male', '儿童', '可爱'),
    new RoleVoiceTraits('kent', 'female', '儿童', '可爱'),
    new RoleVoiceTraits('e_xx2', 'female', '', '温柔叙事'),
    new RoleVoiceTraits('e_xx', 'female', '', '明亮'),
    new RoleVoiceTraits('e_xc', 'female', '', '诵读'),
    new RoleVoiceTraits('e_xy', 'female', '', '治愈'),
    new RoleVoiceTraits('e_xh', 'female', '', '亲和'),
    new RoleVoiceTraits('e_you', 'female', '', '故事'),
    new RoleVoiceTraits('e_yx', 'male', '', '温润'),
    new RoleVoiceTraits('e_yxia', 'male', '', '阳光'),
    new RoleVoiceTraits('e_yh', 'male', '', '低语'),
    new RoleVoiceTraits('e_yf', 'male', '', '旁白'),
    new RoleVoiceTraits('e_mai_bo', 'male'),
    new RoleVoiceTraits('e_mai_mei', 'female'),
    new RoleVoiceTraits('e_mai_lan', 'female'),
    new RoleVoiceTraits('e_mai_wei', 'male'),
    new RoleVoiceTraits('e_mai_bo_f', 'male'),
    new RoleVoiceTraits('e_mai_mei_f', 'female')
  ];

  static traits(config: CustomTtsConfig): RoleVoiceTraits | undefined {
    return config.provider === SHENGQIAO_PROVIDER ?
      RoleVoiceMetadata.shengqiao.find((item: RoleVoiceTraits): boolean => item.key === config.modelId) : undefined;
  }

  static readonly ages: string[] = ['child', 'teen', 'young', 'middle', 'senior'];

  static age(value: string | undefined): string {
    return value !== undefined && RoleVoiceMetadata.ages.includes(value) ? value : 'pending';
  }

  static gender(value: string | undefined): string {
    return value === 'male' || value === 'female' ? value : 'pending';
  }

  static ageLabel(age: string): Resource {
    if (age === 'child') return $r('app.string.role_age_child');
    if (age === 'teen') return $r('app.string.role_age_teen');
    if (age === 'young') return $r('app.string.role_age_young');
    if (age === 'middle') return $r('app.string.role_age_middle');
    if (age === 'senior') return $r('app.string.role_age_senior');
    return $r('app.string.role_age_pending');
  }

  static genderLabel(gender: string): Resource {
    if (gender === 'male') return $r('app.string.role_gender_male');
    if (gender === 'female') return $r('app.string.role_gender_female');
    return $r('app.string.role_gender_pending');
  }

  static ageOptions(): SelectOption[] {
    return ['pending', ...RoleVoiceMetadata.ages].map((age: string): SelectOption => {
      return { value: RoleVoiceMetadata.ageLabel(age) };
    });
  }

  static genderOptions(): SelectOption[] {
    return ['pending', 'male', 'female'].map((gender: string): SelectOption => {
      return { value: RoleVoiceMetadata.genderLabel(gender) };
    });
  }

  static voiceAges(description: string): string[] {
    if (description === '儿童') return ['child'];
    if (description === '少年' || description === '少女') return ['teen'];
    if (description === '青年') return ['young'];
    if (description === '成年') return ['young', 'middle'];
    if (description === '中年') return ['middle'];
    if (description === '老年') return ['senior'];
    return [];
  }
}
