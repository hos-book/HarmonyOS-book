import { SearchResult } from './BookSource';

@ObservedV2
export class LocalRuleControl {
  id: string = '';
  title: string = '';
  type: string = 'text';
  placeholder: string = '';
  options: string[] = [];
  optionValues: string[] = [];
  action: string = '';
  url: string = '';
  group: string = '';
  discoveryFilter: boolean = false;
  @Trace value: string = '';
}

export class LocalRulePanel {
  controls: LocalRuleControl[] = [];
  entries: LocalRuleControl[] = [];
}

export class LocalRulePanelAction {
  panel: LocalRulePanel | undefined = undefined;
  message: string = '';
  searchKeyword: string = '';
  refresh: boolean = false;
  browserUrl: string = '';
  browserHtml: string = '';
  browserInjectJs: string = '';
  refreshLogin: boolean = false;
  browseUrl: string = '';
}

export class LocalRuleExploreResult {
  books: SearchResult[] = [];
  nextUrl: string = '';
}

export class LocalRuleBrowseRoute {
  sourceUrl: string = '';
  sourceName: string = '';
  title: string = '';
  moreUrl: string = '';
  keyword: string = '';
}
