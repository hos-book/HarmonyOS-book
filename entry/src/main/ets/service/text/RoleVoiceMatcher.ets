import { RoleSpeaker, RoleVoiceOption } from '../../model/RoleSpeech';
import { RoleVoiceMetadata } from './RoleVoiceMetadata';

/** 性别与年龄先确定候选，声线建议与使用数量安排同档声音。 */
export class RoleVoiceMatcher {
  static candidates(voices: RoleVoiceOption[], gender: string, age: string): RoleVoiceOption[] {
    let candidates = voices;
    if (gender !== 'pending') {
      const same = candidates.filter((voice: RoleVoiceOption): boolean => voice.gender === gender);
      candidates = same.length > 0 ? same :
        candidates.filter((voice: RoleVoiceOption): boolean => voice.gender === 'pending');
    }
    if (age === 'pending' || candidates.length === 0) return candidates;
    let nearest = Number.MAX_VALUE;
    for (const voice of candidates) nearest = Math.min(nearest, RoleVoiceMatcher.ageDistance(voice.ages, age));
    return candidates.filter((voice: RoleVoiceOption): boolean => RoleVoiceMatcher.ageDistance(voice.ages, age) === nearest);
  }

  private static ageDistance(ages: string[], age: string): number {
    if (ages.includes(age)) return 0;
    if (ages.length === 0) return 1;
    const position = RoleVoiceMetadata.ages.indexOf(age);
    let distance = Number.MAX_VALUE;
    for (const candidate of ages) {
      distance = Math.min(distance, Math.abs(RoleVoiceMetadata.ages.indexOf(candidate) - position));
    }
    return distance + 1;
  }

  static choose(suggested: string, voices: RoleVoiceOption[], gender: string, age: string,
    known: RoleSpeaker[], roleId: string): string {
    if (!suggested) return '';
    const candidates = RoleVoiceMatcher.candidates(voices, gender, age);
    if (candidates.some((voice: RoleVoiceOption): boolean => voice.id === suggested)) return suggested;
    let selected = '';
    let usedCount = Number.MAX_VALUE;
    let preferred = false;
    for (const voice of candidates) {
      const count = known.filter((speaker: RoleSpeaker): boolean => speaker.id !== roleId && speaker.voiceId === voice.id).length;
      if (count < usedCount || (count === usedCount && voice.preferred && !preferred)) {
        selected = voice.id; usedCount = count; preferred = voice.preferred;
      }
    }
    return selected;
  }
}
