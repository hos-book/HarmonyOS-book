@ObservedV2
export class ComicImagePlugin {
  readonly id: string;
  @Trace installed: boolean = false;
  @Trace active: boolean = false;
  @Trace version: number = 0;
  @Trace bytes: number = 0;

  constructor(id: string) { this.id = id; }
}

@ObservedV2
export class ComicImagePluginState {
  @Trace plugins: ComicImagePlugin[] = [new ComicImagePlugin('comic-watermarks'), new ComicImagePlugin('edge-banners')];
  @Trace busyId: string = '';
  @Trace revision: number = 0;
  @Trace ready: boolean = false;
  @Trace hasActive: boolean = false;
}

export class ComicImagePluginPackage {
  format: number = 1;
  id: string = '';
  version: number = 0;
  abi: string = '';
  parameters: string = '{}';
  wasm: string = '';
}
