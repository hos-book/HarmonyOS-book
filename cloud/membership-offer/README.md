# 会员优惠签名云函数

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

先在 `cloud/membership-offer` 执行 `npm ci` 安装开发依赖。

1. 仓库根目录执行 `python scripts/package-membership-offer.py`，生成 `cloud/membership-offer/dist/membership-offer-agc.zip`。
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

在本目录使用 Node 22+ 执行 `npm run typecheck`、`npm test` 验证签名核心。
