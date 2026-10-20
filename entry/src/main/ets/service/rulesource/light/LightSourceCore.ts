import { BookSourceScriptRunner } from './upstream/core/book/BookSourceScriptRunner';
import { BookSourceLoginWebRuntime } from './upstream/core/book/BookSourceLoginWebRuntime';
import { LightSourceLogin } from './LightSourceLogin';
import { BookSourceStageWebRuntime, StageWebRuntimeRequest } from './upstream/core/book/BookSourceStageWebRuntime';
import { SourceRuntimeStage } from './upstream/core/book/BookSourceRuntimeRouter';
import { Book, BookChapter, BookSource, SearchBook } from './upstream/model/data/Book';
import { LightSourceImport } from './upstream/LightSourceImport';
import { NativeSourceSpec } from './upstream/core/nativesource/NativeSourceSpec';
import { NativeSourceService } from './upstream/core/nativesource/NativeSourceService';
import { ChapterRuleContext } from '../ChapterRuleContext';
import { NativeSourceImport } from './upstream/core/nativesource/NativeSourceImport';
import { WebBookService } from './upstream/core/book/WebBookService';
import { SearchCoordinator } from './upstream/core/book/SearchCoordinator';
import { ExploreCoordinator } from './upstream/core/book/ExploreCoordinator';
import { ReaderActionMarker } from './upstream/core/book/ReaderActionMarker';
import { ReaderImageMarker } from './upstream/core/book/ReaderImageMarker';
import { BookTypeSupport } from './upstream/core/book/BookTypeSupport';
import { ComicImagePipeline } from './upstream/core/book/ComicImagePipeline';
import { LightAudioSupport } from './upstream/LightAudioSupport';
import { ReaderInteractionProviderRegistry } from './upstream/core/book/ReaderInteractionProvider';
import { LightSourceRuntime, LightSourceDatabase } from './LightSourceRuntime';
import { HttpClient } from './upstream/core/http/HttpClient';
import { AnalyzeUrl } from './upstream/core/rule/AnalyzeUrl';
import { VerificationSupport } from './upstream/core/http/VerificationSupport';
import { LightCookieStore } from './LightSourceRuntime';
import { LightLocalSource as LocalRuleSource } from './LightSourceHost';
import { SourceCoverLoader } from './upstream/core/nativesource/SourceCoverLoader';
import { LightSourceCoverCache } from './LightSourceCoverCache';


/** JSON boundary prevents the upstream TypeScript model leaking into ArkTS pages. */
import { LightSourceTiming } from './LightSourceTiming';
import { LightSourceRequest, LightSourceRequestPolicy } from './LightSourceRequestPolicy';

export class LightSourceCore {
  /** App prefetch reuses the upstream bounded image transport and source cookie scope. */
  static async cacheComicImages(localJson: string, urlsJson: string, request?: LightSourceRequest): Promise<string> {
    const local = JSON.parse(localJson) as LocalRuleSource;
    const source = this.source(local);
    LightSourceRequestPolicy.bind(source, request);
    const urls = JSON.parse(urlsJson) as string[];
    return LightSourceRuntime.run(source, local, async () => {
      const paths: string[] = [];
      for (let start = 0; start < urls.length; start += 4) {
        if (request?.isCancelled()) throw new Error('Comic image prefetch cancelled');
        const batch = urls.slice(start, start + 4);
        const result = await Promise.all(batch.map(async url => {
          if (!/^https?:\/\//i.test(url)) return url;
          // An explicit image request also materializes ordinary URLs; protected
          // URLs keep their own options. No upstream-managed file is modified.
          const spec = ComicImagePipeline.parse(url);
          const raw = spec.hasOptions ? url : `${url},{"headers":{}}`;
          try { return await ComicImagePipeline.materialize(new HttpClient(), source, raw); }
          catch (_) { return url; }
        }));
        paths.push(...result);
      }
      if (request?.isCancelled()) throw new Error('Comic image prefetch cancelled');
      return JSON.stringify(paths);
    });
  }

  static async cover(localJson: string, raw: string, revision: number): Promise<string> {
    const local = JSON.parse(localJson) as LocalRuleSource;
    const source = this.source(local);
    return LightSourceCoverCache.materialize(`${revision}\n${source.jsLib}\n${raw}`,
      () => LightSourceRuntime.run(source, local, () => SourceCoverLoader.load(new HttpClient(), source, raw)));
  }
  static async voices(localJson: string): Promise<string> {
    const local = JSON.parse(localJson) as LocalRuleSource;
    const source = this.source(local);
    return LightSourceRuntime.run(source,local,async () => JSON.stringify(NativeSourceService.voices(source)));
  }
  static async readerAction(localJson: string, address: string, context: string): Promise<string> {
    const local = JSON.parse(localJson) as LocalRuleSource;
    const source = this.source(local);
    return LightSourceRuntime.run(source,local,async () => {
      if (NativeSourceService.isNative(source) && NativeSourceService.isReaderAction(address)) {
        return JSON.stringify({message:await NativeSourceService.runReaderAction(source,new HttpClient(),address)});
      }
      const expanded = ReaderInteractionProviderRegistry.expandAction(source,address);
      const panel = ReaderInteractionProviderRegistry.buildPanel(expanded);
      if (panel) return JSON.stringify({html:panel.html,url:panel.baseUrl});
      const code = ReaderActionMarker.sourceScript(expanded);
      if (!code) return JSON.stringify({url:expanded,html:''});
      const variables = JSON.parse(context) as Record<string,string>;
      const request = new StageWebRuntimeRequest();
      request.applyStageBudget(SourceRuntimeStage.READER_ACTION);
      request.source = source;
      request.book = this.book(source,variables.bookUrl || '',variables);
      request.chapter = new BookChapter();
      request.chapter.url = variables.chapterUrl || '';
      request.chapter.title = variables.chapterName || '';
      request.chapter.variable = context;
      request.variables = variables;
      request.baseUrl = request.chapter.url || source.bookSourceUrl;
      request.code = code;
      const result = await BookSourceStageWebRuntime.get().execute(request);
      return JSON.stringify({url:result.requestedUrl,html:result.requestedHtml,value:result.value,message:result.toastMessage});
    });
  }
  static async fetch(localJson: string, address: string): Promise<string> {
    const local = JSON.parse(localJson) as LocalRuleSource;
    const source = this.source(local);
    return LightSourceRuntime.run(source,local,async () => {
      const response = await new AnalyzeUrl(source,new HttpClient()).fetch(address);
      return JSON.stringify({ok:response.success,statusCode:response.statusCode,requestUrl:response.url,
        headers:response.headers,body:response.body,errorMessage:response.error || ''});
    });
  }
  static normalizeDefinition(raw: string): string {
    const value = JSON.parse(raw) as Record<string, Object>;
    const source = NativeSourceSpec.isDefinitionObject(value) ? NativeSourceImport.importObject(value) :
      new LightSourceImport().parseBookSource(value);
    return JSON.stringify(source);
  }
  private static source(local: LocalRuleSource): BookSource {
    LightSourceRuntime.parseDefinition = value => NativeSourceSpec.isDefinitionObject(value) ?
      NativeSourceImport.importObject(value) : new LightSourceImport().parseBookSource(value);
    const raw = local.definition || local.rawSourceJson;
    const value = JSON.parse(raw) as Record<string, Object>;
    return NativeSourceSpec.isDefinitionObject(value) ? NativeSourceImport.importObject(value) :
      new LightSourceImport().parseBookSource(value);
  }
  private static book(source: BookSource, url: string, vars: Record<string, string>): Book {
    const book = new Book();
    // Preserve the SearchBook context passed by the upstream detail page.
    if (vars['__lightBook']) Object.assign(book, JSON.parse(vars['__lightBook']));
    book.origin = source.bookSourceUrl;
    book.originName = source.bookSourceName;
    book.bookUrl = vars['bookUrl'] || book.bookUrl || url;
    book.tocUrl = vars['tocUrl'] || book.tocUrl || url;
    book.name = book.name || vars['bookName'] || vars['name'] || '';
    book.author = book.author || vars['author'] || '';
    // App-only catalog revision contains the entire source definition. It must not
    // enter rule variables and be copied into every chapter returned by the engine.
    const ruleVariables = {...vars};
    delete ruleVariables.__audioTocDefinition;
    book.variable = JSON.stringify(ruleVariables);
    BookTypeSupport.applyBookType(book, source);
    if (vars['__lightBookType']) book.type = Number(vars['__lightBookType']);
    return book;
  }
  private static snapshot(item: SearchBook | Book): string {
    return JSON.stringify({name:item.name,author:item.author,coverUrl:item.coverUrl,
      kind:item.kind,status:item.status,intro:item.intro,wordCount:item.wordCount,
      latestChapterTitle:item.latestChapterTitle,updateTime:item.updateTime,
      bookUrl:item.bookUrl,tocUrl:item.tocUrl});
  }
  private static result(item: SearchBook, source: BookSource): Object {
    const snapshot = this.snapshot(item);
    return { name: item.name, author: item.author, coverUrl: item.coverUrl, bookUrl: item.bookUrl,
      intro: item.intro, kind: item.kind, lastChapter: item.latestChapterTitle, completed: /完结|完本|已完成|completed|finished/i.test(item.status || ''), wordCount: item.wordCount,
      updateTime: item.updateTime, sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl,
      contentType: BookTypeSupport.isImage(item) ? 'comic' : BookTypeSupport.isAudio(item) ? 'audio' : 'text', mediaType: BookTypeSupport.isVideo(item) ? 'video' : BookTypeSupport.isImage(item) ? 'comic' : BookTypeSupport.isAudio(item) ? 'audio' : 'text', variables: {...JSON.parse(item.variable || '{}'), __lightBook:snapshot, __lightBookType:String(item.type || 0)} };
  }
  static async panel(localJson: string, login: boolean, saveLabel: string, loginLabel: string): Promise<string> {
    const local = JSON.parse(localJson) as LocalRuleSource;
    const source = this.source(local);
    return LightSourceRuntime.run(source, local, async () => {
      if (!NativeSourceService.isNative(source)) {
        if (login) {
          let items = BookSourceScriptRunner.loginItems(source);
          const dynamic = BookSourceScriptRunner.dynamicLoginUiScript(source);
          if (!items.length && dynamic) items = BookSourceScriptRunner.parseLoginItems((await LightSourceLogin.execute(source, dynamic)).resultValue);
          const saved = BookSourceLoginWebRuntime.parseRecord(source.loginInfo);
          const controls = items.map(item => ({id:`light-login:${item.name}`,title:item.viewName || item.name,
            type:item.type || (item.action ? 'button' : 'text'), value:saved[item.name] ??
              (item.value || item.defaultValue || item.chars[0] || ''),
            placeholder:item.placeholder, options:item.chars,optionValues:item.chars,action:item.action,group:item.name}));
          if (items.some(item => ['text','input','password','select','toggle','number','email'].includes(item.type))) {
            controls.push({id:'light-login-save',title:saveLabel,type:'button',value:'',placeholder:'',options:[],optionValues:[],
              action:'light-login-save',group:''});
          }
          if (!items.length && source.loginUrl.trim()) {
            const address = /^https?:\/\//i.test(source.loginUrl.trim()) ? source.loginUrl.trim() : '';
            controls.push({id:'light-login-open',title:loginLabel,type:'button',value:'',placeholder:'',options:[],
              optionValues:[],action:address || 'light-login-run',group:''});
          }
          return JSON.stringify({controls,entries:[]});
        }
        const coordinator = new ExploreCoordinator();
        const menus = await coordinator.getEntries('',source.bookSourceUrl);
        const controls = coordinator.getDiscoveredFilters(source.bookSourceUrl).map(item => ({
          id:`light-filter:${item.title}`,title:item.title,type:'select',options:item.options,optionValues:item.options,
          value:item.selected,action:`light-filter:${item.title}`}));
        if (!menus.length && coordinator.getNoticeMessage()) throw new Error(coordinator.getNoticeMessage());
        return JSON.stringify({controls,entries:menus.map(item => ({id:`${item.title}:${item.url}`,title:item.title,
          url:item.url,type:'category',group:item.groupTitle || ''}))});
      }
      const definition = NativeSourceSpec.unpack(source.jsLib);
      const controls: Object[] = NativeSourceService.varItems(source).map(item => {
        const dynamic = definition?.vars?.some(spec => spec.key === item.key && !!spec.optionsScript) ?? false;
        const options = item.options;
        return {
        id: `light-native-var:${item.key}`, title: item.label,
        type: dynamic ? 'dynamic-select' : options.length ? 'select' : item.key === 'token' ? 'password' : 'text',
        options, optionValues: options, value: item.value,
        placeholder: '',
        action: dynamic || options.length ? `light-native-set:${item.key}` : ''
      };});
      if (controls.length) controls.push({id:'light-native-save',title:saveLabel,type:'button',action:'light-native-save'});
      const spec = NativeSourceService.loginSpec(source);
      const form = NativeSourceService.loginForm(source);
      for (const field of form) {
        controls.push({id:`light-native-form:${field.key}`,title:field.label || field.key,
          type:field.secret ? 'password' : 'text',value:'',group:field.key});
      }
      if (form.length) {
        if (spec?.sendCode) controls.push({id:'light-native-send-code',title:spec.sendCode.label,
          type:'button',action:'light-native-send-code'});
        controls.push({id:'light-native-submit',title:loginLabel,type:'button',action:'light-native-submit'});
      }
      if (spec?.url) controls.push({id:'light-native-login',title:loginLabel,type:'button',action:'light-native-login'});
      for (const item of await NativeSourceService.actions(source,new HttpClient())) {
        controls.push({id:`light-native-action:${item.index}`,title:item.label,type:'button',
          action:`light-native-action:${item.index}`});
      }
      const menuStarted = Date.now();
      const menus = login ? [] : await NativeSourceService.exploreMenus(source, new HttpClient());
      console.info(`[LightNativeTiming] stage=menus count=${menus.length} elapsedMs=${Date.now() - menuStarted}`);
      let group = '';
      const entries = menus.map(menu => {
        if (!menu.target) group = menu.title;
        return {id:`${menu.title}:${menu.target}`,title:menu.title,url:menu.target,
          type:menu.target ? 'category' : 'group', group};
      });
      return JSON.stringify({controls,entries});
    });
  }
  static async panelOptions(localJson: string, controlId: string): Promise<string> {
    const local = JSON.parse(localJson) as LocalRuleSource;
    const source = this.source(local);
    if (!controlId.startsWith('light-native-var:')) throw new Error('未知原生书源变量');
    const key = controlId.substring('light-native-var:'.length);
    return LightSourceRuntime.run(source, local, async () => {
      const item = NativeSourceService.varItems(source).find(value => value.key === key);
      if (!item) throw new Error('未知原生书源变量');
      const dynamic = (await NativeSourceService.varOptions(source, new HttpClient(), key))[key];
      if (dynamic?.options.length) return JSON.stringify(dynamic.options);
      if (item.options.length) return JSON.stringify(item.options);
      throw new Error(dynamic?.error || '没有拿到选项');
    });
  }
  static async panelAction(localJson: string, actionJson: string, controlsJson: string): Promise<string> {
    const local = JSON.parse(localJson) as LocalRuleSource;
    const source = this.source(local);
    return LightSourceRuntime.run(source, local, async () => {
      const action = JSON.parse(actionJson) as {action:string; url:string; type:string; id:string;title:string;value:string};
      if (action.type === 'category' && action.url) return JSON.stringify({browseUrl:action.url});
      if (!NativeSourceService.isNative(source)) {
        if (action.action.startsWith('light-filter:')) {
          const coordinator = new ExploreCoordinator();
          await coordinator.getEntries('',source.bookSourceUrl);
          if (!await coordinator.applyExploreFilter(source.bookSourceUrl,action.title,action.value)) throw new Error('书源筛选项保存失败');
          return JSON.stringify({refresh:true});
        }
        if (/^https?:\/\//i.test(action.action)) return JSON.stringify({browserUrl:action.action});
        const inputs = JSON.parse(controlsJson) as {id:string;group:string;title:string;value:string;type:string}[];
        const values = BookSourceLoginWebRuntime.parseRecord(source.loginInfo);
        for (const input of inputs) {
          if (['text','input','password','number','email','select','toggle'].includes(input.type)) values[input.group || input.title] = input.value;
        }
        source.loginInfo = BookSourceLoginWebRuntime.mergeRecord(source.loginInfo,values);
        await LightSourceDatabase.getInstance(source).updateBookSourceLoginRuntime(source.bookSourceUrl,source.variable,source.loginHeader,source.loginInfo);
        const code = action.action === 'light-login-save' || action.action === 'light-login-run' ?
          (/(?:function\s+login\s*\(|login\s*=\s*function)/.test(source.loginUrl) ? "if(typeof login==='function')login();'';" : "'';") : action.action;
        const result = await LightSourceLogin.execute(source,code);
        if (action.action === 'light-login-run' && !result.requestedUrl && !result.pendingBrowserAwait) {
          result.requestedUrl = VerificationSupport.resolveBookSourceLoginUrl(source);
        }
        return JSON.stringify({message:result.toastMessage || result.logMessage,refresh:true,
          browserUrl:result.requestedUrl,browserHtml:result.requestedHtml,browserInjectJs:result.requestedInjectJs,
          refreshLogin:result.refreshLoginRequested,searchKeyword:result.requestedSearchKeyword});
      }
      if (action.action === 'light-native-login') {
        const spec = NativeSourceService.loginSpec(source);
        if (!spec?.url || !/^https:\/\//i.test(spec.url)) throw new Error('书源未声明有效的 HTTPS 登录地址');
        return JSON.stringify({browserUrl:spec.url});
      }
      if (action.action === 'light-native-submit' || action.action === 'light-native-send-code') {
        const inputs = JSON.parse(controlsJson) as {id:string;value:string}[];
        const form: Record<string,string> = {};
        for (const field of NativeSourceService.loginForm(source)) {
          form[field.key] = inputs.find(item => item.id === `light-native-form:${field.key}`)?.value || '';
        }
        if (action.action === 'light-native-send-code') {
          return JSON.stringify({message:await NativeSourceService.sendLoginCode(source,new HttpClient(),form)});
        }
        const result = await NativeSourceService.submitLogin(source,new HttpClient(),form);
        if (result.ok) {
          const info = NativeSourceService.loginInfoWith(source,result.token,result.user);
          await LightSourceDatabase.getInstance(source).updateBookSourceLoginRuntime(
            source.bookSourceUrl,source.variable,source.loginHeader,info);
        }
        // Only the returned credential is persisted. Form inputs, including passwords, stay transient.
        return JSON.stringify({message:result.message,refresh:result.ok,refreshLogin:result.ok});
      }
      if (action.action.startsWith('light-native-action:')) {
        const index = Number(action.action.substring('light-native-action:'.length));
        const item = (await NativeSourceService.actions(source,new HttpClient())).find(value => value.index === index);
        if (!item) throw new Error('未知原生书源面板动作');
        if (item.open) {
          if (!/^https:\/\//i.test(item.open)) throw new Error('书源未声明有效的 HTTPS 登录地址');
          return JSON.stringify({browserUrl:item.open});
        }
        return JSON.stringify({message:await NativeSourceService.runAction(source,new HttpClient(),index),refresh:true});
      }
      if (action.action.startsWith('light-native-set:')) {
        if (typeof action.value !== 'string') throw new Error('书源选项值未传入解析引擎');
        const key = action.action.substring('light-native-set:'.length);
        const items = NativeSourceService.varItems(source);
        const item = items.find(value => value.key === key);
        if (!item) throw new Error('未知原生书源变量');
        const dynamic = (await NativeSourceService.varOptions(source,new HttpClient(),key))[key];
        const options = dynamic && !dynamic.error && dynamic.options.length ? dynamic.options : item.options;
        if (options.length && !options.includes(action.value)) throw new Error('原生书源变量选项无效');
        item.value = action.value;
        const variable = NativeSourceService.variableWithValues(source,[item]);
        if (variable) await LightSourceDatabase.getInstance(source).updateBookSourceVariable(source.bookSourceUrl,variable);
        return JSON.stringify({refresh:true});
      }
      if (action.action !== 'light-native-save') throw new Error('未知原生书源面板动作');
      const inputs = JSON.parse(controlsJson) as {id:string;value:string}[];
      const items = NativeSourceService.varItems(source);
      for (const item of items) {
        const input = inputs.find(value => value.id === `light-native-var:${item.key}`);
        if (!input || input.value === item.value) continue;
        const dynamic = (await NativeSourceService.varOptions(source,new HttpClient(),item.key))[item.key];
        const options = dynamic && !dynamic.error && dynamic.options.length ? dynamic.options : item.options;
        if (options.length && !options.includes(input.value)) throw new Error('原生书源变量选项无效');
        item.value = input.value;
      }
      await LightSourceDatabase.getInstance(source).updateBookSourceVariable(source.bookSourceUrl,
        NativeSourceService.variableWithValues(source, items));
      return JSON.stringify({refresh:true});
    });
  }
  static async checkLogin(localJson: string, content: string, baseUrl: string): Promise<boolean> {
    const local = JSON.parse(localJson) as LocalRuleSource;
    const source = this.source(local);
    return LightSourceRuntime.run(source,local,async () => {
      if (NativeSourceService.isNative(source)) {
        // Browser cookies are no longer part of the upstream native cache key.
        // This is the login completion boundary, including cookie-only login.
        NativeSourceService.clearCache(source.bookSourceUrl);
        const spec = NativeSourceService.loginSpec(source);
        return spec?.check ? (await NativeSourceService.checkLogin(source,new HttpClient())).ok :
          NativeSourceService.hasLoginCookies(source);
      }
      const saved = JSON.parse(await LightSourceRuntime.host.readState(source.bookSourceUrl) || '{}');
      if (saved.lightLoginPending) {
        const resumed = await LightSourceLogin.execute(source,'light-login-resume',content);
        if (resumed.pendingBrowserAwait) throw new Error('登录动作仍等待后续网页确认');
      }
      if (!source.loginCheckJs.trim()) return true;
      const request = new StageWebRuntimeRequest();
      request.source = source;
      request.applyStageBudget(SourceRuntimeStage.LOGIN);
      request.content = content;
      request.contextContent = content;
      request.baseUrl = baseUrl;
      request.code = source.loginCheckJs.replace(/^\s*@?js:\s*/i,'').replace(/^\s*<js>|<\/js>\s*$/gi,'');
      return (await BookSourceStageWebRuntime.get().execute(request)).value.trim().toLowerCase() !== 'false';
    });
  }
  static async checkNativeLogin(localJson: string): Promise<boolean> {
    return this.checkLogin(localJson,'','');
  }
  static async clearLogin(localJson: string): Promise<void> {
    const local = JSON.parse(localJson) as LocalRuleSource;
    const source = this.source(local);
    await LightSourceRuntime.run(source,local,async () => {
      if (NativeSourceService.isNative(source)) NativeSourceService.clearCache(source.bookSourceUrl);
      LightCookieStore.forSource(source.bookSourceUrl).clearAll();
      await LightSourceDatabase.getInstance(source).updateBookSourceLoginRuntime(source.bookSourceUrl,source.variable,'','');
      await LightSourceRuntime.updateState(source.bookSourceUrl,state => { delete state.lightLoginPending; });
    });
  }
  static async search(localJson: string, keyword: string, page: number): Promise<string> {
    const local = JSON.parse(localJson) as LocalRuleSource;
    const source = this.source(local);
    return LightSourceRuntime.run(source, local, async () => {
      const coordinator = new SearchCoordinator(1);
      const items = await coordinator.search(keyword, () => {}, { targetSources: [source], maxResultsPerSource: 50, page });
      if (!items.length && coordinator.getLastFailureReason()) throw new Error(coordinator.getLastFailureReason());
      return JSON.stringify(items.map(item => this.result(item, source)));
    });
  }
  static async explore(localJson: string, address: string, page: number, limit: number): Promise<string> {
    const started = Date.now();
    const local = JSON.parse(localJson) as LocalRuleSource;
    const source = this.source(local);
    return LightSourceRuntime.run(source, local, async () => {
      const coordinator = new ExploreCoordinator();
      const items = await coordinator.explore({ title: '', url: address,
        sourceUrl: source.bookSourceUrl, sourceName: source.bookSourceName }, page, limit);
      if (!items.length && coordinator.getNoticeMessage()) throw new Error(coordinator.getNoticeMessage());
      console.info(`[LightNativeTiming] stage=explore count=${items.length} elapsedMs=${Date.now() - started}`);
      return JSON.stringify({ books: items.map(item => this.result(item, source)), nextUrl: items.length ? address : '' });
    });
  }
  static async detail(localJson: string, url: string, context: string): Promise<string> {
    const local = JSON.parse(localJson) as LocalRuleSource;
    const source = this.source(local);
    return LightSourceRuntime.run(source, local, async () => {
      AppStorage.setOrCreate('bookSourceStageLastError', '');
      const input = this.book(source, url, JSON.parse(context));
      // The clicked detail URL is authoritative; old chapter variables can contain another URL.
      input.bookUrl = url;
      const book = await new WebBookService().getBookInfo(source, input);
      const failure = LightSourceRuntime.getError(source);
      if (failure) throw new Error(failure);
      return JSON.stringify({ name: book.name, author: book.author, coverUrl: book.coverUrl, intro: book.intro,
        kind: book.kind, wordCount: book.wordCount, lastChapter: book.latestChapterTitle,
        tocUrl: book.tocUrl, completed: /完结|完本|已完成|completed|finished/i.test(book.status || ''), updateTime: book.updateTime, variables: {...JSON.parse(book.variable || '{}'),bookUrl:book.bookUrl,tocUrl:book.tocUrl,__lightBook:this.snapshot(book),__lightBookType:String(book.type || 0)} });
    });
  }
  static async toc(localJson: string, url: string, context: string): Promise<string> {
    const local = JSON.parse(localJson) as LocalRuleSource;
    const source = this.source(local);
    return LightSourceRuntime.run(source, local, async () => {
      const book = this.book(source, url, JSON.parse(context));
      book.tocUrl = url;
      const items = await new WebBookService().getChapterList(source, book);
      const failure = LightSourceRuntime.getError(source);
      if (!items.length && failure) throw new Error(failure);
      const bookVariables = JSON.parse(book.variable || '{}') as Record<string, string>;
      delete bookVariables.__audioTocDefinition;
      return JSON.stringify(items.map(item => {
        const variables = ChapterRuleContext.create(item.title, item.index,
          {...bookVariables, ...JSON.parse(item.variable || '{}'),__lightBookType:String(book.type || 0), chapterName:item.title});
        delete variables.__audioTocDefinition;
        return {name:item.title,url:item.url,isVip:item.isVip,isPay:item.isPay,isVolume:!!(item as BookChapter & {isVolume?:boolean}).isVolume,
          updateTime:String(variables.updateTime || ''),duration:Number(variables.duration || 0),variables};
      }));
    });
  }
  static async content(localJson: string, url: string, context: string, timingId: number = 0,
    request?: LightSourceRequest): Promise<string> {
    const sourceStartedAt = Date.now();
    const local = JSON.parse(localJson) as LocalRuleSource;
    const source = this.source(local);
    LightSourceTiming.bind(source, timingId);
    LightSourceRequestPolicy.bind(source, request);
    LightSourceTiming.end(timingId, 'source-decode', sourceStartedAt);
    return LightSourceRuntime.run(source, local, async () => {
      const vars = JSON.parse(context) as Record<string, string>;
      const book = this.book(source, url, vars);
      const chapter = new BookChapter();
      chapter.url = url;
      chapter.bookUrl = book.bookUrl;
      chapter.title = vars['chapterName'] || vars['title'] || '';
      chapter.index = Number(vars['chapterIndex'] || 0);
      chapter.variable = context;
      const ruleStartedAt = Date.now();
      let content = '';
      try { content = await new WebBookService().getContent(source, book, chapter,
        () => LightSourceRequestPolicy.isCancelled(source)); }
      finally { LightSourceTiming.end(timingId, 'content-rule', ruleStartedAt); }
      const mediaStartedAt = Date.now();
      const failure = LightSourceRuntime.getError(source);
      if (!content && failure) throw new Error(failure);
      const audio = BookTypeSupport.isAudio(book);
      const video = BookTypeSupport.isVideo(book);
      const interactions: Object[] = [];
      let cursor = 0;
      let action = ReaderActionMarker.findFirst(content, cursor);
      while (action) {
        interactions.push({offset:action.start,label:action.data.label,url:action.data.url,title:action.data.title});
        cursor = action.end;
        action = ReaderActionMarker.findFirst(content, cursor);
      }
      const imageUrls: string[] = [];
      const body = ReaderActionMarker.strip(content);
      const plain = body.replace(/\[\[LEGADO_EPUB_IMAGE:[\s\S]*?\]\]/g, marker => {
        imageUrls.push(ReaderImageMarker.parse(marker).source);
        return '';
      });
      const media = ComicImagePipeline.parse(audio || video ? content : '');
      if (audio) {
        const support = new LightAudioSupport();
        media.url = support.resolveAudioUrl(content, chapter.url || book.bookUrl || source.bookSourceUrl);
        media.headers = support.audioHeaders(media.url, source, content);
        if (!media.url) throw new Error(support.invalidAudioAddressMessage(content));
      }
      const result = JSON.stringify({ title: chapter.title, content: audio || video ? '' : plain,
        audioUrl: audio ? media.url : '', videoUrl: video ? media.url : '', richContent: content,
        imageUrls, nextContentUrl: '', requestHeaders: media.headers, variables: {...JSON.parse(book.variable || '{}'),__lightBookType:String(book.type || 0)},
        interactions, hasInteractions: ReaderActionMarker.has(content), mediaType: video ? 'video' :
          (book.type & 64) !== 0 ? 'comic' : audio ? 'audio' : 'text' });
      LightSourceTiming.end(timingId, 'media-extract-encode', mediaStartedAt);
      return result;
    });
  }
}
