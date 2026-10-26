# 简听音频源服务

可选的独立音频聚合服务，将来源的搜索、书籍、章节和播放地址统一为 HTTP API，并提供 Vue 运维后台。当前手机 App 在设备端处理用户导入的书源，没有接入本服务或配置其地址。

## 组成

- Express + TypeScript 标准 API
- SQLite WAL 缓存、来源版本和审计记录
- Reader/Legado 服务端音频规则引擎
- 免费听书王专有音频 API Provider（匿名会话、签名、令牌自动刷新）
- YCKCEO、AOAOSTAR、Yiove 网络目录每日同步
- Vue 3 运维后台
- Caddy HTTPS 入口

默认启用开放播客目录，LibriVox 公版音频目录保留为可选来源。阅读书源仅允许 `bookSourceType = 1`，
且只能由后台管理员导入。

“免费听书王”作为独立来源接入，不转换成 Legado JSON。服务器仅在配置 `GUOWEI_SIGNING_KEY` 时首次启用，
签名值属于部署环境配置，不得提交到仓库。

## 调用结构

服务端聚合已配置的阅读音频书源。搜索按来源并发、独立失败并按 `sourceUrl + bookUrl` 去重；详情、目录和播放解析仍按结果所属来源分发。

| 页面或流程 | 标准接口 | 主要数据表 |
| --- | --- | --- |
| API 调用方聚合搜索 | `GET /api/v1/audio-books/search` | `sources`、`books`、`cache_entries` |
| 书籍详情 | `GET /api/v1/audio-books/:id` | `books` |
| 章节目录 | `GET /api/v1/audio-books/:id/chapters` | `books`、`chapters` |
| 播放和下载前解析 | `POST /api/v1/audio-chapters/:id/resolve` | `chapters`、`sources` |
| 来源管理和检测 | `/api/admin/sources` | `sources`、`source_versions`、`health_events` |
| 操作记录 | `GET /api/admin/logs` | `audit_logs` |

标准书籍字段为 `id/title/author/narrator/cover/intro/category/chapterCount/totalDuration`；章节字段为
`id/bookId/title/index/duration`；播放解析返回 `url/headers/format/expiresAt`。公共 API 输出解析结果，
规则由服务端 Provider 和 Reader 引擎处理；手机 App 的本地规则导入与执行是独立流程。

## 本地开发

### 会员优惠签名核心

`src/membership-offer.ts` 提供 `MembershipOfferSigner`，按华为 IAP 的 ES256 JWT 协议为
本应用 `6917615941058168740` 的 `lastVip` 生成 `lifetime_half_2026` 优惠签名；月度和年度会员不参与此活动。
签名有效期为 5 分钟，`data` 为 `PurchaseReservedInfo` JSON 字符串，每次使用新的 UUID nonce。
仅允许上述商品；不接受客户端传入应用 ID、优惠 ID 或任意待签名内容。

构造参数为华为后台的 Issuer ID、Key ID 和对应 P-256 私钥（PKCS#8 PEM 或 Base64 DER）。
这些参数只能放在服务端密钥配置中，不得打包进 App 或提交到仓库。
`src/membership-offer-function.ts` 提供请求校验和限流核心；`src/membership-offer-agc.cjs`
适配开发者中心云函数 Node.js 20 的 `context.env`、`HTTPResponse` 和 callback 协议。
每个函数实例每分钟最多受理 120 个签名请求，返回 `Cache-Control: no-store`。

2026-10-26 已部署到项目 `101653523864988082` 的中国区：
- 函数 `membership-offer`，已发布版本 `1`，入口 `index.handler`，Node.js 20.x。
- HTTP POST 触发器 `/functions/59jlwe1l/membership-offer-1`；客户端鉴权 `apigw-client` / `HDA-SYSTEM`，启用 decode。
- 超时 10 秒、实例并发 10；四个环境变量已配置：`IAP_ISSUER_ID`、`IAP_KEY_ID`、`IAP_PRIVATE_KEY`、`IAP_OFFER_PRODUCTS=lastVip`。
- IAP 专用密钥名 `jianting_membership_offer_2026`。云函数环境使用无换行 PKCS#8 Base64；私钥仅存服务端配置和本机仓库外安全目录，不进入部署 ZIP 或 App。
- 云端测试实际返回 200、正确商品/优惠及 ES256 JWT；这不等于华为收银台已接受签名或已完成扣款。

App 使用 `CloudFoundationKit.cloudFunction.call` 调用固定版本 `1`，函数名称由
`membership_offer_function=membership-offer` 配置。系统完成应用鉴权，不向 App 下发服务端密钥。
PC/2in1 需 API 23+ 且具有对应系统能力；不支持的设备明确提示优惠不可用，不按原价静默下单。
App 接受 AGC 返回的数字或十进制字符串形式的毫秒有效期，同时校验商品、优惠、JWT 格式及到期时间。
价格仍由华为商品接口返回；购买时同时传入 `promotionalOfferId` 和 `jwsRepresentation`。

后台价格：月度 CNY 6、年度 CNY 60、`lastVip` 常规价 CNY 120、活动价 CNY 60。
`lifetime_half_2026` 活动至 2026-12-26 00:00，覆盖 12 月 25 日全天，旧 `cheaplist` 已结束。
三个商品在本次配置价格时仍待提交审核；商户服务已开通、境内收款账户已生效。
实际付款仍需确认商品审核和 IAP 正式服务状态。邀测可验证页面及云函数调用；沙盒购买另需调试签名和已配置的沙盒测试账号。

更新与验证：
1. 仓库根目录执行 `python scripts/package-membership-offer.py`，生成 `server/dist/membership-offer-agc.zip`。
   原 FunctionGraph 适配包仍单独生成，但当前实际部署采用 AGC 包。
2. 执行 `python scripts/test-membership-offer-package.py` 验证实际 ZIP 的 callback、环境变量、签名及非法请求处理。
3. 更新云函数代码后先云端测试，再发布新版本及其 HTTP 触发器，最后同步 App 的固定版本。
4. 邀测检查终身优惠展示 60 / 原价 120，进入收银台核对实付 60；实际扣款及退款未在本次执行。

请求参数：`{"productId":"lastVip","offerId":"lifetime_half_2026"}`；
成功返回 `{productId, offerId, jwsRepresentation, expiresAt}`，不接受客户端传入应用 ID、价格或任意 JWT 内容。

协议依据：
- [生成优惠签名购买参数](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/iap-server-subscribe-offer-sign)
- [Node.js 云函数运行协议](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/cloudfoundation-develop-function-nodejs)
- [App 调用云函数](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/cloudfoundation-call-function)

使用 Node 22+ 运行 `npm test -- --run test/membership-offer.test.ts test/membership-offer-function.test.ts` 验证签名核心。

```bash
npm install
npm --prefix admin install
npm run typecheck
npm test
npm run admin:build
```

生成后台密码哈希：

```bash
node -e "const{randomBytes,scryptSync}=require('crypto');const p=process.argv[1],s=randomBytes(16).toString('base64url');console.log('scrypt$'+s+'$'+scryptSync(p,s,64).toString('base64url'))" "change-this-password"
```

复制 `deploy/.env.example` 为 `deploy/.env`，填入密码哈希和随机 `SESSION_SECRET`。
如已获得该 API 的合法接入授权，再填写 `GUOWEI_SIGNING_KEY`；未填写时来源会保留为停用状态。

## Docker 部署

```bash
cd deploy
docker compose -f compose.yml up -d --build
docker compose -f compose.yml ps
```

公网入口和 HTTPS 证书由部署环境配置，Caddy 负责自动续期。Reader
和 API 均只在 Docker 内网暴露，公网仅开放 80/443。不要把 Reader 原始 `/reader3` 接口映射到公网。

## 公共 API

- `GET /api/v1/audio-books/search?q=Alice&page=1`
- `GET /api/v1/audio-books/:id`
- `GET /api/v1/audio-books/:id/chapters`
- `POST /api/v1/audio-chapters/:id/resolve`
- `GET /api/v1/health`
- `GET /api/v1/sources`

所有响应使用 `{ code, data, requestId, serverTime }` 包络。聚合搜索按来源独立超时，单个来源失败时返回
其他来源结果，并通过 `partial` 标记部分失败。

## 运维

- 后台：`/admin/`
- 来源导入默认不启用，检测通过后再启用。
- 服务启动 20 秒后执行一次网络目录同步，之后每天北京时间 04:20 自动更新。
- 自动目录只保留 `bookSourceType = 1`，按 `bookSourceUrl` 去重；规则未变化时不重复创建版本。
- 新来源先保持停用，再按每日检测预算自动启用搜索、章节和首章解析均通过的来源；人工启用状态不会被后续同步覆盖。
- Yiove 官方接口单页最多 100 条，服务端会自动抓取前两页，对应网页的 `page_size=200`。
- 三个目录独立记录成功或失败，一个目录被 Cloudflare 或上游故障拦截时不会影响另外两个目录。
- 目录文件下载默认允许 120 秒，适配 AOAOSTAR 的大合集；可通过 `SOURCE_SYNC_FETCH_TIMEOUT_MS` 调整。
- 播放地址按需解析，不代理或持久化音频文件。
- `deploy/backup.sh` 使用 SQLite 在线快照备份数据库和 Reader 配置，默认保留 14 天。
- 备份定时任务需在部署环境自行配置；仓库不保证生产服务器已安装定时任务。
- 升级 Reader 前固定镜像摘要并在测试来源上执行搜索、目录和播放解析，不使用无人值守自动更新。
