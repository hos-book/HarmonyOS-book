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
本应用 `6917615941058168740` 的 `iconMonth`、`iconYear`、`lastVip` 生成 `cheaplist` 优惠签名。
签名有效期为 5 分钟，`data` 为 `PurchaseReservedInfo` JSON 字符串，每次使用新的 UUID nonce。
仅允许上述商品；不接受客户端传入应用 ID、优惠 ID 或任意待签名内容。

构造参数为华为后台的 Issuer ID、Key ID 和对应 P-256 私钥（PKCS#8 PEM 或 Base64 DER）。
这些参数只能放在服务端密钥配置中，不得打包进 App 或提交到仓库。
`src/membership-offer-function.ts` 提供华为 FunctionGraph APIG 代理事件入口，校验请求和商品白名单，
返回 `Cache-Control: no-store`，每个函数实例每分钟最多受理 120 个签名请求。
App 展示华为返回的 `cheaplist.localPrice`，购买时向固定 HTTPS 入口获取签名，同时传入
`promotionalOfferId` 和 `jwsRepresentation`；签名失败停止下单，不退回原价。
普通商品和华为自动应用的推介促销不依赖此入口。

当前代码尚未部署，App 的 `membership_offer_endpoint` 为空，因此促销购买会明确失败、不会按原价扣款。
2026-10-22 已在登录控制台核验：应用内购买服务仍为沙盒，开通检查中的保密协议、商户服务签约、
IAP 开关已完成，《华为数字商品及联运服务协议》待完成；服务端有效密钥为 0/10，云函数未开通。
控制台链接的官方“服务与支持”文档要求该协议联系商务线下签署，应用类邮箱为
`jointoperation.HarmonyOSNEXT@huawei.com`。完成正式激活之前不能将沙盒测试视为生产付款通过。
本次后台已由用户确认：`lastVip` 常规价 CNY 69、`cheaplist` 早鸟价 CNY 39。
活动需包含 2026-12-25 当天，后台结束时间应调整为 2026-12-26 00:00（核对后台时区）；
截图原值为 2026-12-25 00:00。本地代码不写死价格或替代华为活动有效期判断。

部署步骤（未执行云端部署）：
1. 运行 `python scripts/package-membership-offer.py`，得到 `server/dist/membership-offer-function.zip`。
   ZIP 只包含签名核心和入口，无第三方运行依赖、无密钥；在仓库根目录执行。
2. 华为 FunctionGraph 创建支持 Node.js 22 的事件函数，上传 ZIP，执行入口设为 `index.handler`。
3. 服务端安全配置 `IAP_ISSUER_ID`、`IAP_KEY_ID`、`IAP_PRIVATE_KEY`，对应 AGC 优惠签名密钥。
   私钥支持 PKCS#8 PEM 或 Base64 DER，不是应用 HAP 签名证书；不得写进 App 或提交仓库。
   `IAP_OFFER_PRODUCTS=lastVip`：目前仅确认终身会员活动，其他商品默认不开放签名。
4. APIG 配置 HTTPS POST 路由并使用代理集成，向函数传递 `httpMethod/body/isBase64Encoded`；
   启用网关客户端限流，建议每客户端每分钟 10 次。此入口按活动面向所有购买者设计；
   如改为定向人群优惠，必须先增加身份核验和服务端资格判断，不能信任客户端传入的身份。
5. 将正式 HTTPS 路由填入 App 资源 `membership_offer_endpoint`，重新构建安装。
6. 真机刷新套餐，确认显示 39、划线价 69，进入华为收银台核对实付 39 后取消；
   不把本地签名测试通过当作华为密钥、活动资格或真实付款通过。

接口：`POST <配置的HTTPS路由>`，请求 `{"productId":"lastVip","offerId":"cheaplist"}`，
成功返回 `{productId, offerId, jwsRepresentation, expiresAt}`。金额只从华为商品接口获取，
接口不接受应用 ID、任意优惠 ID、价格或自定义 JWT 内容。

协议依据：
- [生成优惠签名购买参数](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/iap-server-subscribe-offer-sign)
- [PurchaseReservedInfo / OfferInfo](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/iap-server-data-model)

使用 Node 22+ 运行 `npm test -- --run test/membership-offer.test.ts` 验证签名、商品绑定、有效期及随机标识。

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
