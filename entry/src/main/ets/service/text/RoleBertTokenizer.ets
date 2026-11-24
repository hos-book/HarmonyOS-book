import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

export class RoleBertPiece {
  id: number = 0;
  start: number = 0;
  end: number = 0;
}

export class RoleBertEncoding {
  inputIds: number[] = [];
  tokenTypes: number[] = [];
  attentionMask: number[] = [];
  contextModelPositions: number[] = [];
  contextStarts: number[] = [];
  contextEnds: number[] = [];
}

class RoleBertWord {
  characters: string[] = [];
  starts: number[] = [];
  ends: number[] = [];
}

export class RoleBertTokenizer {
  static readonly SEQUENCE_LENGTH: number = 512;
  private vocabulary: Map<string, number> = new Map<string, number>();
  private unknownId: number = -1;
  private paddingId: number = -1;
  private classId: number = -1;
  private separatorId: number = -1;

  private constructor(vocabulary: Map<string, number>) {
    this.vocabulary = vocabulary;
    this.unknownId = vocabulary.get('[UNK]') ?? -1;
    this.paddingId = vocabulary.get('[PAD]') ?? -1;
    this.classId = vocabulary.get('[CLS]') ?? -1;
    this.separatorId = vocabulary.get('[SEP]') ?? -1;
  }

  static async fromResource(context: common.Context): Promise<RoleBertTokenizer> {
    const raw = await context.resourceManager.getRawFileContent('role_speech/vocab.txt');
    const text = util.TextDecoder.create('utf-8').decodeToString(raw);
    const vocabulary: Map<string, number> = new Map<string, number>();
    const rows = text.split(/\r?\n/);
    for (let index = 0; index < rows.length; index++) {
      if (rows[index].length > 0) vocabulary.set(rows[index], index);
    }
    const tokenizer = new RoleBertTokenizer(vocabulary);
    if (tokenizer.unknownId < 0 || tokenizer.paddingId < 0 || tokenizer.classId < 0 || tokenizer.separatorId < 0) {
      throw new Error('role_tokenizer_invalid');
    }
    return tokenizer;
  }

  encode(question: string, context: string): RoleBertEncoding {
    const query = this.tokenize(question).slice(0, 64);
    const contextLimit = RoleBertTokenizer.SEQUENCE_LENGTH - query.length - 3;
    const passage = this.tokenize(context).slice(0, contextLimit);
    return this.combine(query, passage);
  }

  encodeDialogue(pieces: RoleBertPiece[], start: number, end: number): RoleBertEncoding {
    const first = pieces.findIndex((piece: RoleBertPiece): boolean => piece.end > start);
    let after = pieces.findIndex((piece: RoleBertPiece): boolean => piece.start >= end);
    if (after < 0) after = pieces.length;
    const dialogue = pieces.slice(first, after);
    const query = dialogue.length <= 64 ? dialogue : dialogue.slice(0, 48).concat(dialogue.slice(-16));
    const target = dialogue.length <= 128 ? dialogue : dialogue.slice(0, 64).concat(dialogue.slice(-64));
    const remaining = RoleBertTokenizer.SEQUENCE_LENGTH - query.length - target.length - 3;
    let left = Math.max(0, first - Math.floor(remaining / 2));
    const right = Math.min(pieces.length, after + remaining - (first - left));
    left = Math.max(0, first - (remaining - (right - after)));
    const passage = pieces.slice(left, first).concat(target).concat(pieces.slice(after, right));
    return this.combine(query, passage);
  }

  private combine(query: RoleBertPiece[], passage: RoleBertPiece[]): RoleBertEncoding {
    const result = new RoleBertEncoding();
    result.inputIds.push(this.classId);
    result.tokenTypes.push(0);
    result.attentionMask.push(1);
    for (const piece of query) {
      result.inputIds.push(piece.id);
      result.tokenTypes.push(0);
      result.attentionMask.push(1);
    }
    result.inputIds.push(this.separatorId);
    result.tokenTypes.push(0);
    result.attentionMask.push(1);
    for (const piece of passage) {
      result.contextModelPositions.push(result.inputIds.length);
      result.contextStarts.push(piece.start);
      result.contextEnds.push(piece.end);
      result.inputIds.push(piece.id);
      result.tokenTypes.push(1);
      result.attentionMask.push(1);
    }
    result.inputIds.push(this.separatorId);
    result.tokenTypes.push(1);
    result.attentionMask.push(1);
    while (result.inputIds.length < RoleBertTokenizer.SEQUENCE_LENGTH) {
      result.inputIds.push(this.paddingId);
      result.tokenTypes.push(0);
      result.attentionMask.push(0);
    }
    return result;
  }

  tokenize(text: string): RoleBertPiece[] {
    const result: RoleBertPiece[] = [];
    for (const word of this.basicWords(text)) {
      const pieces = this.wordPieces(word);
      for (const piece of pieces) result.push(piece);
    }
    return result;
  }

  private basicWords(text: string): RoleBertWord[] {
    const result: RoleBertWord[] = [];
    let current: RoleBertWord | null = null;
    for (let offset = 0; offset < text.length;) {
      const code = text.charCodeAt(offset);
      const width = code >= 0xD800 && code <= 0xDBFF ? 2 : 1;
      const character = text.substring(offset, offset + width);
      const end = offset + width;
      if (RoleBertTokenizer.isWhitespace(code)) {
        current = null;
      } else if (RoleBertTokenizer.isChinese(code) || RoleBertTokenizer.isPunctuation(character)) {
        current = null;
        const word = new RoleBertWord();
        word.characters.push(character); word.starts.push(offset); word.ends.push(end);
        result.push(word);
      } else {
        if (current === null) {
          current = new RoleBertWord();
          result.push(current);
        }
        current.characters.push(character.toLowerCase());
        current.starts.push(offset); current.ends.push(end);
      }
      offset = end;
    }
    return result;
  }

  private wordPieces(word: RoleBertWord): RoleBertPiece[] {
    if (word.characters.length === 0) return [];
    if (word.characters.length > 100) return [this.unknownPiece(word)];
    const result: RoleBertPiece[] = [];
    let start = 0;
    while (start < word.characters.length) {
      let end = word.characters.length;
      let foundId = -1;
      while (end > start) {
        const body = word.characters.slice(start, end).join('');
        const token = start === 0 ? body : `##${body}`;
        const tokenId = this.vocabulary.get(token);
        if (tokenId !== undefined) { foundId = tokenId; break; }
        end--;
      }
      if (foundId < 0) return [this.unknownPiece(word)];
      const piece = new RoleBertPiece();
      piece.id = foundId; piece.start = word.starts[start]; piece.end = word.ends[end - 1];
      result.push(piece);
      start = end;
    }
    return result;
  }

  private unknownPiece(word: RoleBertWord): RoleBertPiece {
    const piece = new RoleBertPiece();
    piece.id = this.unknownId;
    piece.start = word.starts[0]; piece.end = word.ends[word.ends.length - 1];
    return piece;
  }

  private static isWhitespace(code: number): boolean {
    return code === 0x20 || code === 0x09 || code === 0x0A || code === 0x0D || code === 0x202F || code === 0x3000;
  }

  private static isChinese(code: number): boolean {
    return (code >= 0x4E00 && code <= 0x9FFF) || (code >= 0x3400 && code <= 0x4DBF) ||
      (code >= 0xF900 && code <= 0xFAFF) || (code >= 0x2E80 && code <= 0x2EFF) ||
      (code >= 0x3000 && code <= 0x303F);
  }

  private static isPunctuation(character: string): boolean {
    return '!”#$%&\'()*+,-./:;<=>?@[\\]^_`{|}~，。！？；：、（）［］【】《》〈〉「」『』…—～·‘’“”'.includes(character);
  }
}
