import { BookSource, SearchRule, ExploreRule, BookInfoRule, TocRule, ContentRule } from './model/data/Book';
export class LightSourceImport {
  parseBookSource(obj: Record<string, Object>): BookSource {
    const source = new BookSource();
    source.bookSourceUrl = obj['bookSourceUrl'] as string || '';
    source.bookSourceName = obj['bookSourceName'] as string || '';
    source.bookSourceType = Number(obj['bookSourceType'] || 0);
    source.bookSourceGroup = obj['bookSourceGroup'] as string || '';
    source.bookSourceComment = obj['bookSourceComment'] as string || '';
    source.loginUrl = obj['loginUrl'] as string || '';
    source.loginUi = obj['loginUi'] as string || '';
    source.loginCheckJs = obj['loginCheckJs'] as string || '';
    source.loginHeader = obj['loginHeader'] as string || '';
    source.loginInfo = String(obj['loginInfo'] || '');
    source.rawSourceJson = JSON.stringify(obj);
    source.bookUrlPattern = obj['bookUrlPattern'] as string || '';
    source.searchUrl = obj['searchUrl'] as string || '';
    source.exploreUrl = obj['exploreUrl'] as string || '';
    source.jsLib = obj['jsLib'] as string || '';
    source.header = obj['header'] as string || '';
    source.variableComment = obj['variableComment'] as string || '';
    source.variable = obj['variable'] as string || '';
    source.enabledCookieJar = obj['enabledCookieJar'] !== false;
    source.enabled = obj['enabled'] !== false;
    source.enabledExplore = obj['enabledExplore'] !== false;
    source.isPinned = obj['isPinned'] === true;
    source.isLocked = obj['isLocked'] === true || obj['locked'] === true;
    source.weight = (obj['weight'] as number) || 0;
    source.concurrentRate = obj['concurrentRate'] as string || '';
    source.lastUpdateTime = Number(obj['lastUpdateTime'] || Date.now());
    if (!Number.isFinite(source.lastUpdateTime)) source.lastUpdateTime = Date.now();
    source.respondTime = Number(obj['respondTime'] || 180000);
    if (!Number.isFinite(source.respondTime)) source.respondTime = 180000;
    source.customOrder = Math.floor(Number(obj['customOrder'] || 0));
    source.customButton = obj['customButton'] === true;
    source.eventListener = obj['eventListener'] === true;

    // 解析 searchRule (ruleSearch)
    const ruleSearch = obj['ruleSearch'];
    if (ruleSearch && typeof ruleSearch === 'string') {
      const fields = this.parseCompactRule(ruleSearch as string);
      const rule = new SearchRule();
      this.applyRuleToSearchRule(fields, rule);
      source.searchRule = rule;
    } else if (ruleSearch && typeof ruleSearch === 'object') {
      source.searchRule = ruleSearch as SearchRule;
    } else if (obj['searchRule'] && typeof obj['searchRule'] === 'object') {
      source.searchRule = obj['searchRule'] as SearchRule;
    }

    // 解析 exploreRule (ruleExplore)
    const ruleExplore = obj['ruleExplore'];
    if (ruleExplore && typeof ruleExplore === 'string') {
      const fields = this.parseCompactRule(ruleExplore as string);
      const rule = new ExploreRule();
      this.applyRuleToSearchRule(fields, rule);
      source.exploreRule = rule;
    } else if (ruleExplore && typeof ruleExplore === 'object' && !Array.isArray(ruleExplore)) {
      source.exploreRule = ruleExplore as ExploreRule;
    } else if (obj['exploreRule'] && typeof obj['exploreRule'] === 'object') {
      source.exploreRule = obj['exploreRule'] as ExploreRule;
    }

    // 解析 bookInfoRule (ruleBookInfo)
    const ruleBookInfo = obj['ruleBookInfo'];
    if (ruleBookInfo && typeof ruleBookInfo === 'string') {
      const fields = this.parseCompactRule(ruleBookInfo as string);
      const rule = new BookInfoRule();
      this.applyRuleToBookInfoRule(fields, rule);
      source.bookInfoRule = rule;
    } else if (ruleBookInfo && typeof ruleBookInfo === 'object') {
      source.bookInfoRule = ruleBookInfo as BookInfoRule;
    } else if (obj['bookInfoRule'] && typeof obj['bookInfoRule'] === 'object') {
      source.bookInfoRule = obj['bookInfoRule'] as BookInfoRule;
    }

    // 解析 tocRule (ruleToc)
    const ruleToc = obj['ruleToc'];
    if (ruleToc && typeof ruleToc === 'string') {
      const fields = this.parseCompactRule(ruleToc as string);
      const rule = new TocRule();
      this.applyRuleToTocRule(fields, rule);
      source.tocRule = rule;
    } else if (ruleToc && typeof ruleToc === 'object') {
      source.tocRule = ruleToc as TocRule;
    } else if (obj['tocRule'] && typeof obj['tocRule'] === 'object') {
      source.tocRule = obj['tocRule'] as TocRule;
    }

    // 解析 contentRule (ruleContent)
    const ruleContent = obj['ruleContent'];
    if (ruleContent && typeof ruleContent === 'string') {
      const fields = this.parseCompactRule(ruleContent as string);
      const rule = new ContentRule();
      this.applyRuleToContentRule(fields, rule);
      source.contentRule = rule;
    } else if (ruleContent && typeof ruleContent === 'object') {
      source.contentRule = ruleContent as ContentRule;
    } else if (obj['contentRule'] && typeof obj['contentRule'] === 'object') {
      source.contentRule = obj['contentRule'] as ContentRule;
    }

    return source;
  }

  parseCompactRule(ruleStr: string): Record<string, string> {
    const result: Record<string, string> = {};

    let content = ruleStr.trim();
    if (content.startsWith('@{')) {
      content = content.substring(2);
    }
    if (content.endsWith('}')) {
      content = content.substring(0, content.length - 1);
    }

    let depth = 0;
    let inString = false;
    let stringChar = '';
    let inJsValue = false; // 是否在 @js: 值内部

    const pairs: string[] = [];
    let current = '';

    for (let i = 0; i < content.length; i++) {
      const ch = content[i];

      if (inString) {
        current += ch;
        if (ch === '\\') {
          i++;
          if (i < content.length) current += content[i];
        } else if (ch === stringChar) {
          inString = false;
        }
        continue;
      }

      if (ch === '"' || ch === "'") {
        inString = true;
        stringChar = ch;
        current += ch;
        continue;
      }

      if (ch === '(' || ch === '[' || ch === '{') {
        depth++;
        current += ch;
        continue;
      }

      if (ch === ')' || ch === ']' || ch === '}') {
        if (depth > 0) depth--;
        current += ch;
        continue;
      }

      // 检测当前是否在 @js: 值中（值以 @js: 开头时禁用分号拆分）
      if (!inJsValue && current.trim().includes('=@js:')) {
        inJsValue = true;
      }

      // 在非 @js: 值中，分号且深度为0时作为分隔符
      if (ch === ';' && depth === 0 && !inJsValue) {
        pairs.push(current.trim());
        current = '';
        continue;
      }

      // 在 @js: 值中，分号+换行可能表示新字段开始
      if (ch === ';' && depth === 0 && inJsValue) {
        // 检查后续是否是新字段: ;\s*keyword=
        const rest = content.substring(i + 1);
        const nextFieldMatch = rest.match(/^\s*(\w+)=/);
        if (nextFieldMatch) {
          // 是新字段开始，结束当前 @js: 值
          pairs.push(current.trim());
          current = '';
          inJsValue = false;
          // 跳过空白
          while (i + 1 < content.length && (content[i + 1] === ' ' || content[i + 1] === '\n' || content[i + 1] === '\r')) {
            i++;
          }
          continue;
        }
      }

      current += ch;
    }

    if (current.trim()) {
      pairs.push(current.trim());
    }

    for (const pair of pairs) {
      const eqIdx = pair.indexOf('=');
      if (eqIdx > 0) {
        const field = pair.substring(0, eqIdx).trim();
        let value = pair.substring(eqIdx + 1).trim();

        if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
          value = value.substring(1, value.length - 1);
        }

        result[field] = value;
      }
    }

    return result;
  }

  applyRuleToSearchRule(fields: Record<string, string>, rule: SearchRule): void {
    rule.bookList = fields['bookList'] || fields['booklist'] || '';
    rule.name = fields['name'] || '';
    rule.author = fields['author'] || '';
    rule.coverUrl = fields['coverUrl'] || '';
    rule.intro = fields['intro'] || fields['desc'] || '';
    rule.kind = fields['kind'] || '';
    rule.status = fields['status'] || '';
    rule.lastChapter = fields['lastChapter'] || fields['lastchapter'] || '';
    rule.bookUrl = fields['bookUrl'] || fields['bookurl'] || '';
    rule.wordCount = fields['wordCount'] || fields['wordcount'] || '';
  }

  applyRuleToTocRule(fields: Record<string, string>, rule: TocRule): void {
    rule.chapterList = fields['chapterList'] || fields['chapterlist'] || '';
    rule.chapterName = fields['chapterName'] || fields['chaptername'] || '';
    rule.chapterUrl = fields['chapterUrl'] || fields['chapterurl'] || '';
    rule.nextTocUrl = fields['nextTocUrl'] || fields['nexttocurl'] || '';
    rule.isVip = fields['isVip'] || fields['isvip'] || '';
    rule.isPay = fields['isPay'] || fields['ispay'] || '';
    rule.updateTime = fields['updateTime'] || fields['updatetime'] || '';
  }

  applyRuleToContentRule(fields: Record<string, string>, rule: ContentRule): void {
    rule.content = fields['content'] || '';
    rule.title = fields['title'] || '';
    rule.images = fields['images'] || '';
    rule.sourceRegex = fields['sourceRegex'] || fields['sourceregex'] || '';
    rule.audioUrl = fields['audioUrl'] || fields['audiourl'] || '';
    rule.nextContentUrl = fields['nextContentUrl'] || fields['nextcontenturl'] || '';
    rule.replaceRegex = fields['replaceRegex'] || fields['replaceregex'] || '';
    rule.imageDecode = fields['imageDecode'] || fields['imagedecode'] || '';
    rule.imageStyle = fields['imageStyle'] || fields['imagestyle'] || '';
    rule.payAction = fields['payAction'] || fields['payaction'] || '';
    rule.callBackJs = fields['callBackJs'] || fields['callbackjs'] || '';
  }

  applyRuleToBookInfoRule(fields: Record<string, string>, rule: BookInfoRule): void {
    rule.init = fields['init'] || '';
    rule.name = fields['name'] || '';
    rule.author = fields['author'] || '';
    rule.coverUrl = fields['coverUrl'] || '';
    rule.intro = fields['intro'] || fields['desc'] || '';
    rule.kind = fields['kind'] || '';
    rule.lastChapter = fields['lastChapter'] || fields['lastchapter'] || '';
    rule.wordCount = fields['wordCount'] || fields['wordcount'] || '';
    rule.updateTime = fields['updateTime'] || fields['updatetime'] || '';
    rule.tocUrl = fields['tocUrl'] || fields['tocurl'] || '';
  }
}
