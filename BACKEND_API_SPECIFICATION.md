# 后端 API 接口规范

> 文档版本：1.0.0  
> 适用客户端：`flutter_app`  
> 当前客户端 API 根地址：`https://api.xxblqaq.cn/api`  
> 协议状态：实施基线

## 1. 目标与范围

本文档基于 Flutter 客户端已存在的 Dio 与 Socket.IO 调用整理，供后端独立搭建服务、数据库、实时网关及联调使用。服务端以本规范为准实现统一响应、鉴权、对象级授权、幂等与实时同步。

### 1.1 已纳入本期后端范围

- 手机号注册、登录、短信验证码、密码重置与修改、登出、用户资料。
- 头像目录、好友关系、好友邀请码。
- 私聊、群聊消息、会话列表、增量同步、聊天设置、通知设置。
- 远程震动授权和触发审计。
- 首页横幅、功能卡片删除、应用版本及发布记录。
- 鸡尾酒配方、配方互动、个人笔记。
- 国际跳棋房间、走棋、协商、重赛及实时事件。

### 1.2 明确不属于本期必做 API

下列功能当前在客户端没有调用本项目业务后端，不应虚构接口或阻塞本期交付：

| 功能 | 当前实现 | 后端结论 |
|---|---|---|
| 动态（Moments） | 占位界面 | 后续需求确认后设计发布、评论、点赞、媒体接口 |
| 出行规划 | SharedPreferences 本地保存 | 不做云同步 |
| 调酒台库存 | SharedPreferences 本地保存 | 不做云同步 |
| 邮编查询 | 本地 JSON 资产 | 不做在线服务 |
| 首页卡片新增、编辑、排序 | SharedPreferences 本地保存 | 当前仅对删除调用后端 |
| Minecraft 查询 | TCP 直连及第三方公开 API | 不纳入业务后端 |

`minecraft_query_io.dart` 中的明文 `http://192.168.3.6:7777/event` 调试上报不是业务 API，生产环境必须移除，或迁移至受认证、HTTPS 保护的可观测平台。

## 2. 服务边界与基础约定

### 2.1 推荐部署结构

- HTTP API：Node.js 20+、TypeScript、Express/Fastify 或等价框架。
- 实时层：Socket.IO 4.x，和 HTTP API 使用同一域名。
- 关系数据库：PostgreSQL 16+（推荐）或 MySQL 8+。
- Redis 7+：限流、Socket 适配器、短期验证码、幂等锁、缓存。
- 对象存储/CDN：头像、横幅、APK 等静态资源；业务 API 仅保存 URL 和校验值。
- 反向代理：Nginx、Caddy 或云负载均衡器，负责 TLS 与 WebSocket Upgrade。

### 2.2 域名、路径与版本策略

客户端当前根地址为 `https://api.xxblqaq.cn/api`，因此本文列出的 `POST /auth/login` 实际完整地址是：

```text
https://api.xxblqaq.cn/api/auth/login
```

新接口逻辑版本为 `v1`，推荐规范地址为 `/api/v1/*`。为兼容当前已发布 Flutter 客户端，服务端必须在 API 网关保留以下等价路由，至少维护至所有活跃客户端升级：

```text
/api/*     -> /api/v1/*
/api/v1/*  -> /api/v1/*
```

- 同一主版本内仅增加可选字段或新资源，不改变已有字段语义。
- 删除字段、改变字段类型、改变鉴权或响应结构时新建 `/api/v2`。
- 废弃接口返回 `Deprecation: true` 和 `Sunset: <RFC 1123 date>` 响应头，并提前至少两个客户端发布周期公告。
- Flutter 若切至版本路径，将 `API_BASE_URL` 配置为 `https://api.xxblqaq.cn/api/v1`；在此之前默认 `/api` 兼容路由不可移除。

### 2.3 HTTP 头与编码

所有 JSON 请求和响应采用 UTF-8：

```http
Accept: application/json
Content-Type: application/json; charset=utf-8
Authorization: Bearer <access-token>
X-Request-Id: <UUID，可选，推荐>
Idempotency-Key: <UUID，指定写接口必填>
```

- `Authorization`：除明示公开接口外必填。服务端从 JWT 提取用户，不接受请求体中的用户 ID 作为身份依据。
- `X-Request-Id`：客户端可传；未传时网关生成并在响应中返回，日志必须关联该值。
- `Idempotency-Key`：发送消息、创建邀请码、兑换邀请码、创建棋局房间、走棋等写入操作推荐或要求提供。聊天客户端已有 `clientMessageId` 时，以该字段为消息幂等键。
- 所有时间字段为 UTC ISO 8601 字符串，例如 `2026-09-16T08:30:00Z`。
- 所有 ID 使用 UUID/ULID 字符串，禁止暴露数据库自增主键。

### 2.4 统一响应与错误模型

除文件下载外，成功响应统一如下：

```json
{
  "data": {},
  "meta": {
    "requestId": "01J..."
  }
}
```

列表响应：

```json
{
  "data": [],
  "meta": {
    "requestId": "01J...",
    "offset": 0,
    "limit": 20,
    "nextCursor": "可选游标"
  }
}
```

错误响应：

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "请求参数不正确",
    "details": [
      {"field": "phone", "reason": "格式不正确"}
    ],
    "requestId": "01J..."
  }
}
```

客户端当前对登录和注册兼容根级 `token`、`user`，但新服务必须返回 `data.token`、`data.user`；不得在其他新接口使用多种响应包裹格式。

### 2.5 状态码与错误码

| HTTP | 错误码示例 | 使用场景 |
|---|---|---|
| 200 | - | 查询、更新、操作成功 |
| 201 | - | 资源创建成功 |
| 204 | - | 删除成功，无响应体 |
| 400 | BAD_REQUEST | JSON 无法解析、请求格式错误 |
| 401 | UNAUTHORIZED、TOKEN_EXPIRED | 未登录、JWT 无效或过期 |
| 403 | FORBIDDEN、REMOTE_VIBRATION_DENIED | 已登录但无对象访问或操作权限 |
| 404 | NOT_FOUND | 资源不存在或不对当前用户可见 |
| 409 | CONFLICT、DUPLICATE_MESSAGE、GAME_VERSION_CONFLICT | 唯一冲突、重复操作、并发状态冲突 |
| 410 | INVITE_CODE_EXPIRED | 已失效的邀请码 |
| 422 | VALIDATION_ERROR、ILLEGAL_MOVE | 参数合法但不满足业务规则 |
| 429 | RATE_LIMITED | 超过频率或配额 |
| 500 | INTERNAL_ERROR | 未处理服务错误，不泄露堆栈 |
| 503 | SERVICE_UNAVAILABLE | 依赖不可用或维护中 |

服务端必须记录完整异常、`requestId`、当前用户 ID（如有），但客户端错误消息不得含 SQL、堆栈、密钥或内部地址。

## 3. 身份认证与安全

### 3.1 JWT 方案

- 登录、注册成功后签发短期 access token，建议有效期 15 分钟。
- 同时签发 refresh token，建议有效期 30 天；刷新 token 仅以 HttpOnly、Secure、SameSite=Lax Cookie 保存，或另设受保护的设备会话接口。当前 Flutter 未调用刷新接口，首期可在 access token 过期后要求重新登录；新增刷新接口时再同步客户端。
- Access token 使用 `Authorization: Bearer`，签名算法推荐 RS256/EdDSA，密钥通过 Secret Manager 管理并支持 `kid` 轮换。
- JWT Claims 至少包含：`sub`（用户 ID）、`sid`（会话 ID）、`iat`、`exp`、`iss`、`aud`、`jti`。
- 登出时撤销 `sid` 或 `jti` 至 Redis，过期时间不短于 token 剩余有效期；Socket 连接需同时断开。
- 密码使用 Argon2id（推荐）或 bcrypt，绝不保存明文、可逆加密密码或验证码。

### 3.2 授权规则

每个资源查询与修改必须执行对象级授权（IDOR 防护）：

- 用户只能读取、修改自己的用户资料、通知配置、鸡尾酒笔记、配方互动、功能卡片和邀请码。
- 私聊双方、群聊成员才可读取会话、消息、震动设置和实时事件。
- 好友删除要求当前用户属于该好友关系。
- 国际跳棋房间仅成员可读取及订阅；仅轮到的一方可走棋；仅对局方可发起或回应协商。
- 管理横幅和应用发布记录的写入接口不向移动客户端暴露，需独立管理员鉴权。

### 3.3 频率限制与反滥用

Redis 滑动窗口或令牌桶限流最小要求：

| 场景 | 建议限制 |
|---|---|
| 登录、注册、密码重置 | 每 IP 10 次/15 分钟；每手机号 5 次/15 分钟 |
| 短信发送 | 每手机号 1 次/60 秒、5 次/24 小时；每 IP 20 次/24 小时 |
| 普通 API | 每用户 300 次/分钟 |
| 消息发送 | 每用户 30 条/分钟、每会话 15 条/分钟 |
| 远程震动触发 | 每发送方-接收方-会话 3 次/60 秒 |
| 游戏聊天 | 每用户 20 条/分钟 |

命中限制返回 `429 RATE_LIMITED`，可附带 `Retry-After` 秒数。客户端的本地限流只是体验优化，服务端限流才是最终判定。

### 3.4 CORS、TLS 与安全头

- 生产环境只允许明确的 Web 管理端 Origin，例如 `https://admin.example.com`；移动原生客户端不依赖 CORS，但不能配置 `*` 与凭证并用。
- 允许方法：`GET, POST, PUT, PATCH, DELETE, OPTIONS`。
- 允许头：`Authorization, Content-Type, Accept, X-Request-Id, Idempotency-Key`。
- 预检缓存：`Access-Control-Max-Age: 600`。
- 所有生产 API、Socket、下载 URL 必须 HTTPS/WSS，HTTP 仅限 `localhost`、`127.0.0.1`、Android 模拟器 `10.0.2.2` 调试。
- 配置 HSTS、`X-Content-Type-Options: nosniff`、合理 CSP（管理端）、请求体大小限制，日志脱敏 `Authorization`、密码、验证码。

## 4. REST API 规范

下表的路径均省略 API 前缀；实际使用 `/api/<path>` 或 `/api/v1/<path>`。除标注“公开”外均需要 Bearer JWT。

### 4.1 认证与用户

| 方法和路径 | 鉴权 | 请求体 / 查询 | 成功响应 `data` | 失败状态 |
|---|---|---|---|---|
| `POST /auth/login` | 公开 | `{"phone":"13800138000","password":"8-72位密码"}` | `{"token":"JWT","user":用户对象}` | 400, 401, 429 |
| `POST /auth/register` | 公开 | `{"phone":"...","password":"...","code":"6位验证码","nickname":"1-32字符"}` | `{"token":"JWT","user":用户对象}` | 400, 409, 422, 429 |
| `POST /auth/sms/send` | 公开 | `{"phone":"..."}` | `{"expiresIn":300}` | 400, 429, 503 |
| `POST /auth/sms/send-reset` | 公开 | `{"phone":"..."}` | `{"expiresIn":300}` | 400, 404, 429, 503 |
| `POST /auth/password/reset` | 公开 | `{"phone":"...","code":"...","newPassword":"..."}` | `{"success":true}` | 400, 422, 429 |
| `POST /auth/password/change` | 是 | `{"oldPassword":"...","newPassword":"..."}` | `{"success":true}` | 400, 401, 422 |
| `POST /auth/logout` | 是 | 空对象或无请求体 | `{"success":true}` | 401 |
| `GET /users/me` | 是 | 无 | 用户对象 | 401 |
| `PATCH /users/me` | 是 | 可更新 `nickname`（1-32）、`avatar`（HTTPS URL 或头像 ID）、`avatarId` | 用户对象 | 400, 422 |

用户对象统一为：

```json
{
  "id": "user_01J...",
  "nickname": "小明",
  "avatar": "https://cdn.example.com/avatar/a1.png",
  "avatar_id": "a1",
  "createdAt": "2026-09-16T08:30:00Z"
}
```

为兼容客户端，`id` 必须存在；可额外同时返回等值 `uid`，但新客户端只应依赖 `id`。手机号不可在好友、聊天、游戏对象中暴露。

### 4.2 公开目录、好友与邀请码

| 方法和路径 | 请求 | 成功响应 `data` | 失败状态 |
|---|---|---|---|
| `GET /avatars` | 无 | `[{"id":"a1","url":"https://..."}]` | 500 |
| `GET /friends` | 无 | 好友对象数组 | 401 |
| `DELETE /friends/{friendId}` | 无 | 204 | 401, 403, 404 |
| `GET /friends/codes` | 无 | 当前用户的邀请码数组 | 401 |
| `POST /friends/codes` | `{"expiry":"1d|3d|7d|30d|permanent"}` | 邀请码对象，201 | 400, 429 |
| `PATCH /friends/codes/{id}` | `{"expiry":"1d|3d|7d|30d|permanent"}` | 更新的邀请码对象 | 400, 403, 404 |
| `DELETE /friends/codes/{id}` | 无 | 204 | 403, 404 |
| `DELETE /friends/codes/{id}/permanent` | 无 | 204，仅永久码可用 | 403, 404, 422 |
| `POST /friends/codes/redeem` | `{"code":"ABC123"}` | `{"friend":好友对象,"relationshipId":"..."}` | 400, 404, 409, 410, 422 |

好友对象最少包含 `id`、`nickname`、`avatar`。邀请码对象：

```json
{
  "id": "invite_...",
  "code": "ABC123",
  "expiry": "7d",
  "expiresAt": "2026-09-23T08:30:00Z",
  "isPermanent": false,
  "createdAt": "2026-09-16T08:30:00Z"
}
```

兑换操作必须在单一数据库事务中执行：锁定邀请码，检查未过期、未撤销、未被使用、非本人兑换，创建双向好友关系，标记兑换者和兑换时间。`invite_codes.code`、每对用户的规范化关系键必须唯一，避免重复好友与并发重复兑换。

### 4.3 聊天、会话、同步与设置

| 方法和路径 | 请求 | 成功响应 `data` | 失败状态 |
|---|---|---|---|
| `POST /chats` | `{"targetUserId":"user_..."}` | 私聊会话对象，201；已存在则 200 返回既有会话 | 400, 403, 404, 409 |
| `GET /chats` | 可选 `limit`、`cursor` | 会话对象数组 | 401 |
| `GET /chats/{id}/messages` | 可选 `limit`、`beforeSeq` | 消息数组 | 401, 403, 404 |
| `POST /chats/{id}/messages` | 消息发送体 | 消息对象，201 或幂等重放 200 | 400, 403, 404, 409, 422, 429 |
| `GET /chats/{id}/messages/sync` | `afterSeq`（建议必填）、`limit` | `{"messages":[],"latestSeq":123,"hasMore":false}` | 400, 403, 404 |
| `GET /groups/{id}/messages` | 同私聊查询 | 消息数组 | 401, 403, 404 |
| `POST /groups/{id}/messages` | 同消息发送体 | 消息对象 | 400, 403, 404, 422, 429 |
| `GET /groups/{id}/messages/sync` | 同私聊同步 | 同步对象 | 400, 403, 404 |
| `PUT /chat-settings/{chatId}` | `{"pinned":true}` 或 `{"unread":false}` | 当前用户在该会话的设置对象 | 400, 403, 404 |
| `GET /notification-settings` | 无 | 通知设置对象 | 401 |
| `PUT /notification-settings` | 通知设置对象，可部分更新 | 更新后的通知设置对象 | 400, 422 |

消息发送体：

```json
{
  "content": "你好",
  "type": "text",
  "clientMessageId": "01J...",
  "receiverId": "user_..."
}
```

- `content` 去首尾空白后长度为 1-5000；`type` 当前仅接受 `text`。
- `receiverId` 仅用于客户端兼容，服务端从会话成员推导真实接收方并校验其一致性。
- `clientMessageId` 对同一 `sender_id` 全局唯一，必须持久化。重复提交返回首次创建的消息而不是再次写入。
- 每个会话消息必须由服务端在事务内分配单调递增 `seq`，并更新会话最后消息与更新时间。

消息对象：

```json
{
  "id": "msg_...",
  "chatId": "chat_...",
  "senderId": "user_...",
  "receiverId": "user_...",
  "content": "你好",
  "type": "text",
  "clientMessageId": "01J...",
  "seq": 42,
  "createdAt": "2026-09-16T08:30:00Z"
}
```

会话对象最少包含：`id`、`type`（`direct`/`group`）、`members`、`lastMessage`、`unreadCount`、`settings`、`updatedAt`。`GET /chats` 必须只返回调用者所属会话。

通知设置主字段采用 camelCase：

```json
{"chat":true,"game":true,"friendRequest":true,"system":true}
```

为兼容现有客户端，服务端过渡期可接受 `friend_request`，并将它标准化为 `friendRequest` 后存储与返回。

### 4.4 远程震动

| 方法和路径 | 请求 | 成功响应 `data` | 失败状态 |
|---|---|---|---|
| `GET /remote-controls/chats/{chatId}/vibration` | 无 | 震动权限对象 | 401, 403, 404 |
| `PUT /remote-controls/chats/{chatId}/vibration` | `{"enabled":true}` | 更新后的权限对象 | 400, 403, 404 |

权限对象：

```json
{
  "chatId": "chat_...",
  "localEnabled": true,
  "peerAuthorized": false,
  "updatedAt": "2026-09-16T08:30:00Z"
}
```

响应可额外包含历史兼容别名 `enabled`、`allowRemoteVibration`、`canRemoteVibrate`、`remoteVibrationAvailable`，但新接口以 `localEnabled` 和 `peerAuthorized` 为准。

设置 `enabled=true` 表示“允许对方远程触发本人的设备”。触发只能经 Socket 事件 `remote:vibration:trigger`，服务端必须验证：会话为一对一有效会话、双方仍是可通信关系、接收者已开启 `localEnabled`、触发者不是接收者、未超过 Redis 限流。每一次请求和结果都写入审计表，审计表不得记录 token。

### 4.5 首页内容与应用更新

| 方法和路径 | 鉴权 | 请求 / 查询 | 成功响应 `data` | 失败状态 |
|---|---|---|---|---|
| `GET /banners` | 可选 | `platform=android&enabled=true` | 横幅数组 | 400, 500 |
| `DELETE /features/{featureId}` | 是 | 无 | 204 | 403, 404 |
| `GET /app/version` | 公开 | 可选 `platform=android` | 版本对象 | 400, 500 |
| `GET /app/releases` | 公开 | 可选 `platform=android&limit=20` | 发布记录数组 | 400, 500 |

横幅对象至少有 `id`、`title`、`imageUrl`、`actionUrl`、`platform`、`enabled`、`sortOrder`。只返回已启用且当前时间处于投放窗口内的记录。

版本对象必须保留 Flutter 当前识别的 snake_case 字段：

```json
{
  "has_update": true,
  "update_required": false,
  "latest_version": "1.2.0",
  "version_code": 120,
  "min_version": "1.0.0",
  "min_version_code": 100,
  "release_notes": "修复问题",
  "download_url": "https://cdn.example.com/app-1.2.0.apk",
  "sha256": "64位小写十六进制"
}
```

`download_url` 必须为可信 HTTPS 地址，APK 必须在发布前计算 SHA-256；客户端限制文件大小 150 MB。`GET /app/releases` 每项至少包含版本对象内适用字段、`publishedAt` 和 `platform`。

### 4.6 鸡尾酒

| 方法和路径 | 请求 / 查询 | 成功响应 `data` | 失败状态 |
|---|---|---|---|
| `GET /cocktail/recipes` | `limit`、`offset`、`q` 或 `keyword`、`taste`、`category` | 配方数组与分页 meta | 400 |
| `GET /cocktail/recipes/{recipeId}/interaction` | 无 | 当前用户互动对象 | 401, 404 |
| `PUT /cocktail/recipes/{recipeId}/favorite` | `{"favorite":true}` | 互动对象 | 400, 404 |
| `PUT /cocktail/recipes/{recipeId}/rating` | `{"rating":1}`，范围 1-5 | 互动对象 | 400, 404, 422 |
| `GET /cocktail/notes` | 可选 `limit`、`offset` | 当前用户笔记数组 | 401 |
| `POST /cocktail/notes` | 笔记体 | 笔记对象，201 | 400, 409, 422 |
| `PUT /cocktail/notes/{noteId}` | 笔记体的可更新字段 | 笔记对象 | 400, 403, 404, 422 |
| `DELETE /cocktail/notes/{noteId}` | 无 | 204 | 403, 404 |

配方对象：

```json
{
  "id": "recipe_...",
  "name": "Mojito",
  "ingredients": ["白朗姆", "薄荷", "青柠", "苏打水"],
  "steps": ["..."],
  "taste": "fresh",
  "abv": 12.5,
  "category": "classic"
}
```

互动对象：`{"favorite":true,"rating":5,"updatedAt":"..."}`。数据库对 `(user_id, recipe_id)` 唯一，使用 UPSERT。

笔记体：

```json
{
  "id": "note_客户端可选预生成ID",
  "title": "标题",
  "body": "内容",
  "category": "分类",
  "tags": ["标签"]
}
```

标题最大 100、正文最大 10000、分类最大 50、标签最多 20 个且每项最大 30。服务端始终以 JWT 用户 ID 写入 `user_id`；笔记 ID 仅在同一用户范围去重，严禁依据前端传入的用户身份读取或修改他人笔记。

### 4.7 国际跳棋

房间接口全部需要 JWT；读操作仅房间成员可访问。

| 方法和路径 | 请求 | 成功响应 `data` | 失败状态 |
|---|---|---|---|
| `GET /game/rooms/mine` | 可选 `status`、`limit` | 当前用户房间数组 | 401 |
| `GET /game/rooms/{roomId}` | 无 | 房间状态对象 | 403, 404 |
| `POST /game/rooms` | `{"opponentId":"可选好友ID"}` 或空对象 | 新房间对象，201 | 400, 403, 404, 429 |
| `POST /game/rooms/join-by-code` | `{"code":"..."}` | 加入后的房间对象 | 400, 404, 409, 410 |
| `POST /game/rooms/{roomId}/join` | 空对象 | 加入后的房间对象 | 403, 404, 409 |
| `POST /game/rooms/{roomId}/move` | 走棋体 | 新房间状态对象 | 400, 403, 404, 409, 422 |
| `POST /game/rooms/{roomId}/undo/request` | 空对象 | 协商对象 | 403, 404, 409 |
| `POST /game/rooms/{roomId}/undo/respond` | `{"accepted":true}` | 新房间状态对象 | 400, 403, 404, 409 |
| `POST /game/rooms/{roomId}/resign` | 空对象 | 结束后的房间状态对象 | 403, 404, 409 |
| `POST /game/rooms/{roomId}/draw/request` | 空对象 | 协商对象 | 403, 404, 409 |
| `POST /game/rooms/{roomId}/draw/respond` | `{"accepted":true}` | 新房间状态对象 | 400, 403, 404, 409 |
| `POST /game/rooms/{roomId}/rematch` | 空对象 | 新一局房间状态对象 | 403, 404, 409 |

走棋体：

```json
{"fromRow":2,"fromCol":1,"toRow":3,"toCol":2}
```

行、列范围为 0-7。服务端是棋局规则唯一权威：验证成员身份、轮次、棋子归属、目标格、强制吃子、连跳、升王、胜负和和棋；客户端坐标绝不能直接成为可信状态。每次变更在事务内使用 `state_version` 乐观锁，旧版本写入返回 `409 GAME_VERSION_CONFLICT` 并让客户端重新拉取房间。

房间状态对象至少包含：

```json
{
  "id": "room_...",
  "code": "ABCD12",
  "status": "waiting",
  "players": [{"id":"user_...","nickname":"...","color":"black"}],
  "board": [[null, {"color":"black","king":false}]],
  "turnUserId": "user_...",
  "moveHistory": [],
  "stateVersion": 3,
  "result": null,
  "updatedAt": "2026-09-16T08:30:00Z"
}
```

## 5. Socket.IO 实时协议

### 5.1 连接与鉴权

Socket 根地址为 API 地址移除 `/api` 后的域名，例如 `https://api.xxblqaq.cn`，路径固定：

```text
/socket.io/
```

客户端使用 `websocket` 优先、`polling` 回退，并在握手 auth 中传：

```json
{"token":"JWT"}
```

连接后客户端仍会发送带 Ack 的 `auth`：

```json
{"token":"JWT","userId":"可选兼容字段"}
```

服务端忽略并不信任 `userId`，仅从已验证 JWT 推导用户。推荐 Ack：

```json
{"ok":true,"data":{"userId":"user_..."}}
```

失败 Ack 兼容客户端格式：

```json
{"error":"登录已过期"}
```

鉴权失败应拒绝连接或发送 `connect_error` 后断开；JWT 到期或登出时断开该 `sid` 所有连接。多实例 Socket.IO 必须启用 Redis Adapter。

### 5.2 聊天与远程震动事件

| 方向 | 事件 | Payload | 服务端行为 / Ack |
|---|---|---|---|
| C -> S | `auth` | `{"token":"JWT"}` | 认证并绑定 socket 用户；Ack `{"ok":true}` 或 `{"error":"..."}` |
| C -> S | `chat:join` | 直接传 `chatId` 字符串 | 校验会话成员后 `socket.join("chat:<id>")`；Ack 成功或错误 |
| C -> S | `chat:send` | 消息发送体，含 `chatId` | 复用 HTTP 发送事务与幂等规则，成功后广播 `chat:message`；Ack 返回消息 |
| C -> S | `typing:start` | `{"chatId":"..."}` | 成员校验后仅转发给其他成员，不持久化 |
| C -> S | `typing:stop` | `{"chatId":"..."}` | 同上 |
| S -> C | `chat:message` | 消息对象 | 发送给目标会话房间及用户个人房间 |
| C -> S | `remote:vibration:trigger` | `{"chatId":"..."}` | 权限、关系、限流、审计后向接收方发送；Ack 成功或错误 |
| S -> C | `remote:vibration` | `{"chatId":"...","senderId":"...","createdAt":"..."}` | 仅发送给被授权接收者 |

`chat:send` 成功 Ack 建议为 `{"data": <消息对象>}`；客户端当前只要求错误字段，因此可同时提供 `data`。输入状态负载可额外包含发送方公开用户对象，但不得泄露手机号。

## 6. 数据库设计规范

### 6.1 基础规范

- 使用 UUID/ULID 作为公开主键，`created_at`、`updated_at` 采用 UTC `timestamptz`。
- 业务写入使用事务；涉及余额类数据当前不存在，不应引入无关表。
- 所有外键按业务确定 `RESTRICT`、`CASCADE` 或软删除策略；用户数据优先软删除/匿名化，聊天消息不能因用户删除被级联误删。
- 所有用户归属数据都有 `user_id` 索引；分页采用 `(created_at, id)` 或单调 `seq`，避免大 offset 扫描。
- Schema 通过迁移工具（Prisma Migrate、Flyway、Knex 等）版本化；生产禁止自动 `sync` 改表。

### 6.2 推荐核心表与约束

| 表 | 核心字段 | 关键索引/约束 |
|---|---|---|
| `users` | `id, phone, password_hash, nickname, avatar_url, avatar_id, status` | `phone` 唯一；手机号规范化后存储 |
| `auth_sessions` | `id, user_id, token_jti, expires_at, revoked_at, device_info` | `token_jti` 唯一；`user_id, expires_at` 索引 |
| `sms_codes` | `phone, purpose, code_hash, expires_at, consumed_at` | `phone, purpose, expires_at` 索引；验证码只存 hash |
| `avatars` | `id, url, enabled, sort_order` | `enabled, sort_order` 索引 |
| `friendships` | `id, user_low_id, user_high_id, created_at` | `(user_low_id, user_high_id)` 唯一；以排序后的二人 ID 消除方向重复 |
| `invite_codes` | `id, owner_id, code, expiry, expires_at, revoked_at, redeemed_by, redeemed_at` | `code` 唯一；`owner_id, created_at` 索引 |
| `conversations` | `id, type, direct_key, last_message_id, last_seq, updated_at` | 直接会话 `direct_key` 唯一 |
| `conversation_members` | `conversation_id, user_id, joined_at` | `(conversation_id, user_id)` 唯一；`user_id` 索引 |
| `messages` | `id, conversation_id, sender_id, receiver_id, content, type, client_message_id, seq` | `(conversation_id, seq)` 唯一；`(sender_id, client_message_id)` 唯一 |
| `conversation_user_settings` | `conversation_id, user_id, pinned, unread, last_read_seq` | `(conversation_id, user_id)` 唯一 |
| `notification_settings` | `user_id, chat, game, friend_request, system` | `user_id` 主键 |
| `remote_vibration_permissions` | `conversation_id, user_id, enabled, updated_at` | `(conversation_id, user_id)` 唯一 |
| `remote_vibration_audits` | `id, conversation_id, sender_id, receiver_id, outcome, reason, created_at` | `receiver_id, created_at` 和 `sender_id, created_at` 索引 |
| `banners` | `id, title, image_url, action_url, platform, enabled, starts_at, ends_at, sort_order` | `platform, enabled, starts_at, ends_at, sort_order` 索引 |
| `user_features` | `id, user_id, feature_key, deleted_at` | `user_id, deleted_at` 索引 |
| `app_releases` | `id, platform, version, version_code, min_version_code, download_url, sha256, published_at` | `(platform, version_code)` 唯一 |
| `cocktail_recipes` | `id, name, ingredients JSONB, steps JSONB, taste, abv, category` | `category, taste` 索引；按需全文检索索引 |
| `cocktail_recipe_interactions` | `user_id, recipe_id, favorite, rating, updated_at` | `(user_id, recipe_id)` 唯一 |
| `cocktail_notes` | `id, user_id, title, body, category, tags JSONB` | `user_id, updated_at DESC` 索引 |
| `game_rooms` | `id, code, status, board_state JSONB, turn_user_id, state_version, result` | `code` 唯一；`status, updated_at` 索引 |
| `game_room_players` | `room_id, user_id, color, joined_at` | `(room_id, user_id)` 唯一；一间房颜色唯一 |
| `game_moves` | `id, room_id, move_number, actor_id, from_row, from_col, to_row, to_col, board_after JSONB` | `(room_id, move_number)` 唯一 |
| `game_negotiations` | `id, room_id, type, requester_id, responder_id, status, created_at` | `room_id, status` 索引；每类未完成协商受约束 |
| `game_chat_messages` | `id, room_id, sender_id, content, created_at` | `room_id, created_at` 索引 |
| `idempotency_keys` | `user_id, key, request_hash, response_json, expires_at` | `(user_id, key)` 唯一 |

`board_state` 与 `board_after` 适合 JSONB 保存以便高效恢复，同时 `game_moves` 是不可变历史。对棋局更新应锁定 `game_rooms` 行或通过 `state_version` 条件更新，确保不会发生双人同时成功走棋。

## 7. 关键业务实现要求

### 7.1 消息与离线同步

1. 发送消息时在一个事务中校验成员、写入 `messages`、分配 `seq`、更新会话游标。
2. 提交成功后发布领域事件；Socket 监听者收到 `chat:message`，离线用户由推送服务处理（本期可不实现系统推送）。
3. `GET .../sync?afterSeq=N` 按 `seq ASC` 返回，不可漏消息；`latestSeq` 必须表示服务端已提交的最高序号。
4. 客户端 SQLite outbox 重试会重复发送，服务端必须依赖 `(sender_id, client_message_id)` 返回原消息。

### 7.2 一致性和重试

- 对可重试写操作，先查询 `Idempotency-Key`，请求哈希不同则返回 `409 IDEMPOTENCY_KEY_REUSED`。
- Redis 短锁只用于降低竞争，数据库唯一约束与事务是最终一致性保障。
- 短信供应商、对象存储等临时故障可在服务端有限重试（指数退避，最多 2 次），无法完成返回 `503`。
- 不对密码错误、权限错误、业务校验错误自动重试。

### 7.3 审计、监控与隐私

- 审计：登录、密码修改、邀请码兑换、好友删除、远程震动、棋局结果等记录操作者、对象、结果、时间和 `requestId`。
- 指标：HTTP 延迟和错误率、Socket 在线数/认证失败、Redis 限流命中、消息幂等命中、游戏冲突、短信供应商失败。
- 告警：5xx 比例、登录异常、短信失败、数据库连接池耗尽、远程震动拒绝激增。
- 日志和监控不得保存密码、短信明文、JWT、完整手机号；手机号展示或日志使用掩码。

## 8. 测试标准与 Postman 用例

### 8.1 测试层级和最低覆盖

| 测试层级 | 必测内容 | 最低要求 |
|---|---|---|
| 单元测试 | 验证器、JWT、密码哈希、棋局规则、邀请码状态机、限流键 | 领域服务和关键规则语句/分支覆盖不低于 80% |
| 集成测试 | 路由、数据库事务、唯一约束、对象授权、Redis 限流 | 每个 API 至少成功、未认证、越权、校验失败各一例 |
| Socket 测试 | 握手认证、房间授权、Ack、断线重连、广播范围 | 所有事件至少成功与拒绝各一例 |
| 契约测试 | 响应字段、状态码、snake_case 版本字段、旧路径兼容 | 对照本规范自动校验 |
| 端到端联调 | Flutter 登录、聊天、震动、棋局、更新检查 | 至少 Android 模拟器和真机各一次 |

### 8.2 Postman 环境变量

```json
{
  "baseUrl": "http://localhost:3000/api",
  "phone": "13800138000",
  "password": "TestPass123!",
  "token": "",
  "userId": "",
  "friendId": "",
  "chatId": "",
  "roomId": "",
  "recipeId": "",
  "noteId": ""
}
```

生产环境变量的 `baseUrl` 必须为 HTTPS。Postman 登录请求测试脚本应将 Token 保存至环境：

```javascript
const body = pm.response.json();
pm.test('登录成功', () => pm.response.to.have.status(200));
pm.expect(body.data.token).to.be.a('string').and.not.empty;
pm.environment.set('token', body.data.token);
pm.environment.set('userId', body.data.user.id);
```

认证请求统一添加：

```text
Authorization: Bearer {{token}}
Content-Type: application/json
```

### 8.3 必备 Postman 测试序列

1. `POST /auth/sms/send` -> 获取测试验证码（测试环境可由 Mock Provider 固定返回）。
2. `POST /auth/register` -> 断言 `201/200`、`data.token`、`data.user.id`。
3. `GET /users/me` -> 断言与登录用户一致；删除 Token 后断言 `401`。
4. 邀请码创建、第二账号兑换、重复兑换 -> 分别断言成功与 `409/410`。
5. 创建或获取私聊 -> 发送同一 `clientMessageId` 两次 -> 断言只产生一条消息及相同 `id`、`seq`。
6. 使用无关第三账号读取会话、修改震动、读取笔记、加入游戏房间 -> 均断言 `403` 或隐藏为 `404`。
7. 接收方打开震动授权后，发送方连续触发 4 次 -> 前 3 次成功，第 4 次 `429`；关闭授权后断言 `403 REMOTE_VIBRATION_DENIED`。
9. `GET /app/version` -> 断言全部 snake_case 字段及 `sha256` 匹配 `/^[a-f0-9]{64}$/`。

## 9. 部署配置

### 9.1 必需环境变量

```dotenv
NODE_ENV=production
PORT=3000
DATABASE_URL=postgresql://user:password@db:5432/chat_app
REDIS_URL=redis://redis:6379/0
JWT_ISSUER=chat-app-api
JWT_AUDIENCE=chat-app
JWT_PRIVATE_KEY=<Secret Manager 注入>
JWT_PUBLIC_KEY=<Secret Manager 注入>
SMS_PROVIDER_API_KEY=<Secret Manager 注入>
CORS_ORIGINS=https://admin.example.com
PUBLIC_BASE_URL=https://api.xxblqaq.cn
LOG_LEVEL=info
```

- 禁止将密钥、数据库密码、签名私钥、短信密钥提交到 Git 或打包进 Flutter。
- 生产用 Secret Manager/KMS 注入密钥；部署账户仅授予最小权限。
- 数据库连接启用 TLS，配置连接池上限并设置迁移专用账户。

### 9.2 Docker 与上线顺序

推荐容器：`api`、`worker`（短信/异步任务）、`postgres`（托管优先）、`redis`（托管优先）。构建镜像后：

1. 在预发布环境执行数据库迁移并备份生产数据库。
2. 运行单元、集成、Socket 契约测试。
3. 部署 API，配置健康检查 `GET /health`（只供基础设施调用，不要求 Flutter 使用）。
4. 部署 Socket.IO 实例并连接 Redis Adapter。
5. 配置反向代理 `/api`、`/api/v1`、`/socket.io/` 转发和 HTTPS/WSS。
6. 以金丝雀方式发布，观察 401、429、5xx、Socket 认证失败和数据库性能。

健康检查不得返回密钥、配置或用户数据；就绪检查需验证数据库与 Redis 可用性。

### 9.3 备份与恢复

- PostgreSQL 至少每日全量备份与持续 WAL/PITR，定期执行恢复演练。
- 保留审计日志的期限遵循产品隐私政策；到期安全删除或匿名化。
- Redis 仅存可重建缓存、限流与短期会话撤销数据，不作为唯一业务数据来源。

## 10. Flutter 联调步骤

1. 本地启动 API：例如 `http://localhost:3000/api`。Android 模拟器使用 `http://10.0.2.2:3000/api`；真机使用开发机局域网 HTTPS 地址或受信任测试域名。
2. 使用 Flutter 编译参数覆盖地址：

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api
```

3. 确认 API 返回 `data` 包裹；`GET /users/me` 必须返回 `{"data": 用户对象}`，登录/注册必须返回 `{"data":{"token":"...","user":{...}}}`。
4. 登录后核对 HTTP `Authorization` 与 Socket `auth.token` 都能通过；Socket URL 应为 API 地址去掉 `/api` 的根域名。
5. 两个测试账号验证好友兑换、私聊、消息重试幂等、聊天同步、输入状态和远程震动授权。
6. 两个测试账号验证国际跳棋入房、走棋、悔棋/和棋协商、认输、重赛及重连后的 `GET /game/rooms/{id}` 恢复。
7. 验证版本接口使用 HTTPS 下载 URL 和正确 SHA-256；确认旧 `/api/*` 与新 `/api/v1/*` 响应一致。
8. 将客户端默认地址切至生产地址前，运行 Flutter 静态检查和测试，并在真实 Android 设备验证 TLS 证书链。

## 11. 前端调用覆盖校验

下表按已审查的 Flutter 网络调用逐项比对。`已覆盖` 表示本文定义了后端实现所需的 HTTP 或 Socket 合同。

| 前端来源 | 已发现调用 | 本规范章节 | 状态 |
|---|---|---|---|
| `auth_service.dart` | 登录、注册、短信、密码、登出、`/users/me` | 4.1 | 已覆盖 |
| `avatar_catalog_service.dart` | `GET /avatars` | 4.2 | 已覆盖 |
| `home_page.dart` | 好友、邀请码、横幅、会话设置、功能删除 | 4.2、4.3、4.5 | 已覆盖 |
| `chat_service.dart` | 会话、私聊/群聊消息、同步、会话设置 | 4.3、7.1 | 已覆盖 |
| `chat_socket_service.dart` | 聊天认证、入房、发送、输入状态、远程震动 | 5.1、5.2 | 已覆盖 |
| `remote_vibration_service.dart` | 授权读取/更新 | 4.4、5.2 | 已覆盖 |
| `message_notification_service.dart` | 通知设置读取/更新 | 4.3 | 已覆盖 |
| `app_update_service.dart` | 版本与发布记录 | 4.5 | 已覆盖 |
| `cocktail_recipe_page.dart` | 配方、收藏、评分、互动 | 4.6 | 已覆盖 |
| `cocktail_notes_page.dart` | 笔记 CRUD | 4.6 | 已覆盖 |
| `checkers_socket_service.dart` | 房间、走棋、协商、重赛、Socket | 4.7、5.3 | 已覆盖 |
| `minecraft_query*.dart` | TCP 与第三方 API、内部调试上报 | 1.2 | 明确排除 |
| 本地功能页面 | 出行、调酒台、邮编、动态等 | 1.2 | 明确当前无后端调用 |

校验结论：当前 Flutter 已调用的项目 HTTP API、Socket.IO 事件、认证头、响应包裹、离线消息幂等和远程震动安全规则均已在本文定义。尚未接入业务后端的功能已明确列为不在本期范围，避免后端实现与客户端实际能力不一致。
