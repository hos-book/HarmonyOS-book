# Repository Guidelines

## Online HarmonyOS Skill Routing

Use the entire `HarmonyOS_Skills/harmonyos-agent-skills` repository as the online skill catalog for this project, including nested skills and future additions. Select skills for the actual task; a small fixed list of local skill names must not limit discovery.

Sources:

- Repository: https://gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills
- Current index: https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/README.md
- Root directory API: https://api.gitcode.com/api/v5/repos/HarmonyOS_Skills/harmonyos-agent-skills/git/trees/main?recursive=0&per_page=100&page=1
- Raw document base: https://raw.gitcode.com/HarmonyOS_Skills/harmonyos-agent-skills/raw/main/

For each new HarmonyOS development, investigation, review, or verification task:

1. Fetch the current index and root directory metadata in memory. Match the request against all relevant areas: design, ArkTS/ArkUI, SDK capabilities, architecture, stability, performance, testing, device tools, and release workflows. Follow new categories found upstream as well. Reuse fetched content within the same task and refresh discovery when its scope changes.
2. Browse relevant directories through the tree API. For each entry with `type: tree`, request `/git/trees/{entry.sha}?recursive=0&per_page=100&page=N`; preserve the parent path because child `path` values are relative to that tree. Read pages until a page contains fewer than 100 entries. The API's default page contains only 20 entries, and a `path=` query does not select a subtree. Do not mistake either result for the whole catalog.
3. Discover actual `SKILL.md` files, including skills nested under another skill's references or SDK collection. The README is a navigation aid; use the live directory tree when a skill is missing from it or a listed link returns 404. A request for a full catalog requires traversing every directory and page; ordinary work only requires traversing the branches relevant to that task.
4. Fetch the selected `SKILL.md` from the raw document base plus its repository-relative path. Read its description and instructions, then fetch the relevant referenced documents, indexes, examples, or dependent skills. Resolve relative URLs against the document that contains them. Read enough dependencies to use the skill correctly, without downloading the entire repository.
5. Apply the project constraints below: HarmonyOS 6.0+ / minimum API 20, target API 26, ArkUI V2, phone (including foldables), tablet and 2in1 targets, existing architecture, and current product scope. Check API-version annotations against the installed SDK; APIs introduced after 20 require a version guard and a working fallback. An upstream sample or general workflow does not authorize adding unrelated features, changing project conventions, or repeating approvals already given by the user.
6. Match upstream tool names to available operations, including `check_ets_files` / `arkts_check`, `build_project`, `init_project_path`, `start_app`, and UI/log tools. Inspect the actual tool schema; a different MCP server prefix does not require another server installation. Diagnose and report any genuinely missing executable or dependency.
7. Briefly identify the selected online skills and cite the URLs actually read when explaining technical decisions. Distinguish a guide being available from its workflow having been executed or validated.

Use an available web reader, `Invoke-WebRequest`, or `Invoke-RestMethod` with a finite timeout. Parse directory responses as JSON and retrieve reference text in memory. Do not clone, reinstall, cache, or back up the online knowledge catalog into project or user skill directories. If a task genuinely needs an upstream executable/template, inspect it and materialize only the necessary files in a task-specific temporary location; remove temporary downloads after use while retaining intended project outputs. Local SDKs, compilers, and project-owned test tools remain execution dependencies.

If online discovery is unavailable, report the failed source and the resulting coverage limit. Continue using supplied evidence and installed SDK diagnostics where sufficient; do not claim the online catalog was refreshed. Public HarmonyOS entrypoints may help reach online sources but are not required for this project's catalog routing.

## Build & Run Flow

Agents should use the provided tools, not raw `hvigorw`:

1. **`arkts_check`** on changed `.ets` files — catches ArkTS strict-mode violations faster than full build
2. **`build_project`** — incremental build by default; only pass `clean=true` if cache corruption is suspected
3. **`start_app`** — launch on device/emulator; requires prior successful build

Before a release build, verify the selected SDK's `sdk/default/sdk-pkg.json` reports `releaseType: Release`. HarmonyOS Hvigor ignores `hwsdk.dir` in `local.properties`; select the SDK through `DEVECO_SDK_HOME` and use the matching IDE tools. If the MCP build tool is bound to a Beta IDE and cannot select the Release installation, use the Release IDE's Node/Hvigor CLI with `--no-daemon`. Check the produced HAR/HAP/APP metadata rather than treating build success as proof of the SDK channel.

If `arkts_check` / `check_ets_files` or `build_project` fails with ArkTS errors, use the online routing above to read the matching compilation-repair skill before retrying. Include the deprecated-interface skill for SDK migration or deprecation diagnostics.

Raw commands (if tools unavailable):
- `ohpm install` — install HarmonyOS deps from `oh-package.json5`
- `hvigorw assembleHap --mode module -p product=default` — debug HAP
- `hvigorw assembleHap --mode module -p product=release` — release HAP
- `hvigorw clean` — remove build artifacts

## ArkTS Strict-Mode Constraints

ArkTS is **not** TypeScript. These rules trip up agents most often:

- **No `any` or `unknown`** — use explicit types
- **No `as` type assertions** — use explicit class constructors or conversion methods
- **No structural typing** — use explicit `class extends` / `implements`
- **No dynamic property access** (`obj[dynamicKey]`) — use typed accessors
- **Object literals must have explicit type context** — assign to typed variable or pass as typed parameter
- **Use `class` not `interface` for data carriers** — ArkTS requires instantiable types; see `IBuiltInSource.ets` for the pattern
- Before the first `.ets` edit, use the online routing above to read the applicable ArkTS grammar and ArkUI guidance.

## ArkUI V2 Only

Never mix V1 and V2 decorators:

- **Use**: `@ComponentV2`, `@Local`, `@Param`, `@Event`, `@ObservedV2`, `@Trace`
- **Never use**: `@Component`, `@State`, `@Prop`, `@Link`, `@Provide`, `@Consume`, `@Watch`, `@ObjectLink`

Pages hold `@Local` state + Service singletons. No V1 viewmodel layer exists.

## Critical Coding Rules

- **沉浸光感阴影（重复问题记忆）**：阅听记录的“累计阅听 / 连续阅听”统计胶囊必须保留沉浸材质且无外溢阴影。`HdsTabs.barFloatingStyle` 的内部阴影不能靠宿主 `.shadow(0)` 消除；参照 `ImmersiveSummaryTag`、`ImmersiveCircleButton`，在最外层按实际高度一半设置 `borderRadius(radius, RenderStrategy.OFFSCREEN)` 并 `clip(true)`（经 `PlatformCompat.floatingTabs` 守卫，旧 API 普通圆角裁剪）。不要再次删除此裁剪，也不要用不透明底色遮阴影；修改后须在实机查看胶囊下缘，构建通过不等于视觉验证。

- **Loading indicators**: always set `.color(AppColor.Brand)` — never rely on HarmonyOS default brand blue
- **Long lists**: `LazyForEach` + stable keys (e.g. `bookUrl`). Never use index as key
- **UI copy**: change resource strings only; do not rename `.ets` files to match label text
- **Content sources**: extend `service/rulesource/` and the existing imported-source dispatchers; native protocol adapters must remain tied to user-imported source definitions
- **Rule execution**: use the bounded QuickJS facade; do not expose unrestricted platform or network capabilities

## Content Architecture (read this first)

The App obtains online content from user-imported sources stored in encrypted `rule_sources.db`:

| Source kind | Entry | How it works |
|---|---|---|
| Legado-compatible imported rules | `LocalRuleDispatcher → light/LightSourceBridge` | Pinned upstream Light Page extraction, URL/HTTP, script replay and media parsing |
| Light Page `sourceFormat: native` | Same bridge → upstream `NativeSourceService` | Upstream vars, discovery, login, search/detail/toc/content and interactions |

The old local rule engine, `jianting.source` engine and domain-specific content adapters have been removed. Unsupported historical definitions remain inert data. Preserve app pages, playback, reader and encrypted storage.

`SourceDataService` lists imported sources only and excludes `builtin://` addresses. Database failures return empty source lists or unresolved lookups. Search runs enabled sources with required search rules in batches of six and deduplicates by `sourceUrl + bookUrl`; one source failure must not stop other sources. Home recommendations and categories use the enabled imported text/audio source selected in RuleSourcePage and persisted in PreferenceService. HomeSourceService reads source-defined discovery categories and previews, including TingYou through the general rule chain. Enabled text and audio sources with discovery rules are eligible; missing home content shows an empty state.

`BookSourceService` dispatches to imported-source adapters and rules. The old TingYou built-in implementation and registration entrypoint have been removed. Search does not run a separate `KkBiqugeTextSource` task. Some `service/builtin/` utilities remain referenced; file presence alone does not make a source active.

Import capability messages and test status are diagnostic, not a blanket enablement gate. Batch tests offer search and discovery/reading modes with up to six concurrent tasks, retain failures, and preserve enabled state. Discovery/reading requires sampled content from public chapters. Cancellation preserves unfinished results. Single-source tests also validate content when results exist. Disabling search preserves installed definitions for existing favorites; deleting a source removes its sessions and cookies. Locked sources reject definition changes, reimport, group changes, enablement changes and deletion, while testing and ordering remain available.

Local rule scripts must run through `light/LightSourceSandbox` → `LocalRuleQuickJsRuntime` in a taskpool, with independent contexts, native interrupt timeout, heap/stack/pending-job/input/output budgets, and guaranteed release. Do not expose unrestricted QuickJS APIs, direct `fetch`/XHR/WebSocket, platform objects, files, or databases. Upstream web rendering and audio sniffing use ArkUI V2 incognito hosts protected by the global Web session lease. Source website login uses the routed HTTPS-only incognito page with no platform bridge; cookies must be copied into the encrypted source+origin store before the Web session is cleared. HTTP Set-Cookie attributes are persisted per source in encrypted lightCookieRecords; preserve Domain/Path and absolute expiry when restoring. Browser header-only cookies cannot expose all original attributes. Scripted browser waits release and reacquire the Web lease; native login.check must run on completion. Source import permits 25 MiB per file/subscription and 10 files/250 MiB per local batch, without the old 1000-source truncation.

Source contracts and upgrade steps are in `docs/BOOK_SOURCE_RULES.md` and `docs/LIGHT_SOURCE_SYNC.md`. Update upstream-managed files via `scripts/sync-light-source.cjs`. Source mode/filter saves invalidate Home caches and emit the Home source event.

Online novels use `OnlineTextPaginator` and local reading preferences. ReaderKit handles the existing EPUB-path branch; `ImportPage` imports audio, TXT, EPUB, MOBI, HTML/HTM and ZIP bundles. MOBI supports unencrypted MOBI6 with uncompressed/PalmDOC records (including the legacy part of hybrid files), up to 128 MiB per file and 32 MiB of expanded text; encrypted, HUFF/CDIC and standalone KF8 files report explicit errors. Imported ebooks are converted into bounded local text chapters for the existing paginator and speech service; embedded MOBI/EPUB covers are saved separately, while original body images/layout are not preserved. Local chapter catalogs live in durable filesDir/imported_toc rather than Preferences.

External file-open requests route JSON to source import and TXT/EPUB/MOBI/HTML/HTM/ZIP to the local import screen with the original granted URI preselected. Filename extensions take precedence; MIME/UTD supplies the format for extensionless provider URIs. Cold and warm launches use the same pending/event route and consume it once.


The optional `server/` project is not registered or configurable as an App content source. Do not reintroduce an App API-base setting without an explicit product decision.

## Project Structure

Single HarmonyOS module (`entry/`) + optional Node server (`server/`):

- `entry/src/main/ets/pages/` — routed screens
- `entry/src/main/ets/service/` — business services (singular `service/`, not `services/`)
- `entry/src/main/ets/service/builtin/` — protocol/Web utilities and registry implementations; not the active source-list entry
- `entry/src/main/ets/service/rulesource/` — imported-source persistence, testing, accounts, native adapters, HTTP, extraction and QuickJS dispatch
- `entry/src/main/ets/service/text/` — online text pagination, reading progress/settings and parser utilities
- `entry/libs/quickjs.har` — locally built arm64-v8a/x86_64 bounded QuickJS dependency
- `entry/src/main/ets/model/` — domain types (`Book`, `BookSource`, `LocalRuleSource`, `PlayerState`, `TextReading`, `ReaderTheme`)
- `entry/src/main/ets/components/` — reusable widgets
- `entry/src/main/ets/theme/` — theme tokens (`AppColor`, `AppMaterial`)
- `entry/src/main/ets/widget/` — desktop form widget
- `server/` — 简听 cloud API + Vue admin + Docker deploy
- `third_party/quickjs/` / `scripts/build-quickjs.ps1` — QuickJS source, licenses and reproducible HAR build

Generated dirs (never edit, never commit): `build/`, `.hvigor/`, `oh_modules/`, `server/node_modules/`, `server/dist/`, `third_party/quickjs/.hvigor/`, `third_party/quickjs/oh_modules/`, `third_party/quickjs/quickjs/.cxx/`, `third_party/quickjs/quickjs/build/`, `third_party/quickjs/quickjs/oh_modules/`

## Testing

- **App unit tests**: `entry/src/test/*.test.ets` (Hypium framework) — source persistence and management, bulk testing, search history/cache, pagination/themes, playback progress and download policies
- **Node service regression scripts**: `node scripts/test-*.cjs` (reader progress/preferences/statusbar, reader-playback-sync, audio-commands, local-book-import, stats-persistence, source-web-session, text-content-cache, text-to-speech). Each requires `DEVECO_HOME` pointing to the installed Release IDE (they transpile real `entry/src/main/ets` services with the IDE's bundled TypeScript) and runs against temporary files with simulated platform APIs. `scripts/local-rule-http-fixture.cjs` is a shared fixture helper, not a test.
- **App device tests**: `entry/src/ohosTest/ets/test/*.test.ets`
- **Server tests**: `cd server && npm test` (Vitest) — 7 test files covering catalog, providers, auth, DB, sync; `npm run typecheck` for `tsc --noEmit`. Node >= 22, ESM. Vue admin lives in `server/admin` (`npm run admin:install`, `npm run admin:build`, `npm run build:all`)
- **CI**: no build/test CI exists; the only workflow (`.github/workflows/app-gallery-pages.yml`) publishes `docs/app-gallery/**` to GitHub Pages on push to main. Never rely on CI to catch errors
- After changing playback/source adapters/download: smoke-test search → detail → chapter → play on device, then verify resume, download and export
- After changing local rule import/runtime/dispatch: verify no-source empty states, then import → single/bulk test → search → detail → read/play; disabled sources must leave existing favorites resolvable and one failed rule must not stop other sources
- After changing reading: verify chapter/character-position restore, pagination after font or window changes, settings persistence and safe-area handling
- After changing Home/Record UI: verify skeleton loading, pull-to-refresh, double-tap-to-top, edit/long-press selection

## Security & Config

- **`build-profile.json5` contains signing secrets** (key passwords, cert paths) and is git-tracked — never commit changes to this file; signing is machine-specific and configured via DevEco Studio. `build-profile.template.json5` is the shareable template; `signing/` is gitignored
- `code-linter.json5` enforces crypto security rules (no unsafe AES/RSA/DSA/DH/3DES) on all `.ets` files
- The App has no configurable cloud API base; `server/` remains an optional independent project and must not become an implicit runtime dependency
- QuickJS business code may call only `LocalRuleQuickJsRuntime.execute()`; that facade invokes native `evaluateBounded`. Keep the upstream license files and `THIRD_PARTY_NOTICES.md` when updating `entry/libs/quickjs.har`
- Server's Reader/Legado engine must stay internal to Docker; never expose `/reader3` to the public internet

## Reference Documents

- **`CLAUDE.md`** — product/architecture source of truth (content model, services, page flow, SDK baseline)
- **`docs/APP_UI.md`** — current UI interaction baseline and regression checklist
- **`docs/BOOK_SOURCE_RULES.md`** — 书源规则编写指南 for imported rule sources; keep aligned with the actual import parser and rule runtime
- **`server/README.md`** — server deployment and operations guide
- Keep these documents aligned with active code paths. Remove superseded one-off plans and fix notes; Git retains their history.

## Language

- **回复语言**: 始终使用中文回复用户

## Conventions

- **Commits**: Conventional Commits (`feat:`, `fix:`, `fix(player):`, `feat(server):` …); Chinese or English summaries OK
- **Git 推送**: GitHub 远端使用 SSH 地址 `git@github.com:end-web/HarmonyOS-book.git`，优先使用本机 `C:\Users\ylwang112\.ssh\id_ed25519` 密钥推送；不要切回 HTTPS 推送。
- **Naming**: `XxxPage`, `XxxService`, `XxxComponent` (PascalCase + suffix); camelCase for fields/methods
- **SDK**: HarmonyOS 6.0+; `targetSdkVersion = 26.0.0`, `compatibleSdkVersion = 6.0.0(20)` for both App products and the QuickJS HAR; `bundleName: com.huan.listenbook`. Build with a verified Release SDK; Beta/Canary artifacts must not be published. Use `PlatformCompat` for newer APIs and lazy imports for newer system modules.
- **Device types**: phone (including foldables), tablet, HarmonyOS PC and standard wearable (`deviceTypes: ["phone", "tablet", "2in1", "wearable"]`). Layout follows the actual container/window in vp, not device type or default display size. Reuse `AdaptiveLayout` and ArkUI V2; resizing must preserve reading character position. Device declarations and successful builds do not replace real-device validation.

## Wearable Scope

Standard `wearable` uses `WearablePage` and `WearableRuntime` for independent audio books (API 20+, arm64-v8a; x86_64 emulator library is also packaged). Reuse imported sources, bounded rule hosts, downloads and AudioService. Do not route wearable startup through the phone Index, TTS, widgets or automatic cloud backup. Account recovery uses Account Kit with `forceAuthorization=false`; only a system-validated identity is accepted. Same-account cloud restore is user initiated and confirmed before replacement; it does not transfer local audio files or provide real-time synchronization. `liteWearable` and devices below API 20 are not covered. WATCH/GT marketing names are not capability checks. No watch hardware validation has yet been performed; never describe phone validation as watch validation.
