# 小酒馆 Flutter 前端

小酒馆是一个 Flutter 社交娱乐客户端，提供账号登录、好友、私聊、鸡尾酒内容、Minecraft 服务器记录、出行规划、邮编查询和本地工具等功能。

本仓库当前只维护客户端代码。后端服务、数据库、管理员后台和部署文件不属于本项目，客户端通过配置的远程 HTTP API 与 Socket.IO 服务工作。

## 1. 项目范围

### 已实现或已接入

- 手机号登录、注册、验证码、密码修改和重置
- 登录状态恢复、游客进入和安全 Token 存储
- 好友列表、好友代码、添加和删除好友
- 私聊、群聊消息基础展示、消息缓存和发送失败重试
- 聊天 Socket.IO 实时收发、输入状态和本地通知
- 首页功能卡片、网站入口、横幅和应用更新检查
- 鸡尾酒配方、收藏、评分、调酒笔记和本地调酒台
- Minecraft Java/基岩版服务器记录与在线状态查询
- 出行计划、邮政编码查询和本地静态数据

### 当前占位或限制

- 动态页面存在，但发布、评论、点赞和列表接口尚未接入
- 出行计划、Minecraft 服务器配置和调酒台库存目前主要保存在本地
- 聊天服务端是否支持群聊、已读同步和完整离线同步取决于远端 API 实现

## 2. 技术栈

- Flutter / Dart
- Provider：应用状态管理
- Dio：HTTP 请求
- Socket.IO Client：聊天实时通信
- sqflite：聊天消息、本地同步状态和发送箱
- SharedPreferences：轻量配置和功能数据
- Flutter Secure Storage：登录 Token
- WebView：网站卡片页面
- flutter_local_notifications：本地消息通知
- image_picker：选择服务器封面

## 3. 目录结构

```text
flutter_app/
├── lib/
│   ├── core/                 应用入口、路由、主题、API 客户端
│   ├── features/             按业务划分的页面
│   ├── models/               用户、消息、房间等数据模型
│   ├── services/             网络、本地数据库、缓存和平台服务
│   └── widgets/              可复用组件和平台适配组件
├── assets/
│   ├── avatars/              内置头像
│   └── data/                 邮编和鸡尾酒配方 JSON
├── android/                  Android 平台工程
├── web/                      Flutter Web 平台文件
└── test/                     Flutter 测试
```

## 4. 启动与运行

环境要求：Flutter SDK，Dart SDK 3.x，Android 开发需要 Android SDK。

```powershell
cd flutter_app
flutter pub get
flutter run --dart-define=API_BASE_URL=https://api.xxblqaq.cn/api
```

检查代码和测试：

```powershell
flutter analyze
flutter test
```

构建 Android：

```powershell
flutter build apk --release --dart-define=API_BASE_URL=https://api.xxblqaq.cn/api
```

Release 构建必须使用正式签名。可在 `android/key.properties` 中配置 `storeFile`、`storePassword`、`keyAlias`、`keyPassword`，或通过 `RELEASE_STORE_FILE`、`RELEASE_STORE_PASSWORD`、`RELEASE_KEY_ALIAS`、`RELEASE_KEY_PASSWORD` 环境变量提供。缺少签名时 Release 任务会直接失败，避免误产出 debug 签名包。

Android 模拟器访问本机测试服务时，可使用 `http://10.0.2.2:3000/api`。生产环境必须使用 HTTPS。

## 5. 网络配置

实现位于 `lib/core/api_client.dart`。

| 配置 | 说明 |
|---|---|
| `API_BASE_URL` | HTTP API 根地址，默认 `https://api.xxblqaq.cn/api` |
| Socket 地址 | 自动去掉 API 根地址末尾的 `/api` |
| Socket.IO 路径 | `/socket.io/` |
| 请求超时 | 连接和响应均为 10 秒 |
| Token | 从安全存储恢复后自动加入 `Authorization: Bearer <token>` |

`API_BASE_URL` 只用于编译期配置，不应把密码、验证码或 Token 写入源码。

## 6. 前端接口契约

以下路径均相对于 `API_BASE_URL`。除公开接口外，均需要：

```http
Authorization: Bearer <JWT_TOKEN>
Accept: application/json
Content-Type: application/json
```

### 6.1 响应格式

推荐服务端返回：

```json
{"data": {}, "message": "操作成功", "meta": {}}
```

列表：

```json
{"data": [], "meta": {"count": 0, "limit": 20, "offset": 0}}
```

错误：

```json
{"code": "ERROR_CODE", "message": "用户可读错误", "data": null}
```

客户端目前兼容部分历史裸对象、裸数组和 `{items: []}` 响应。新接口应统一使用上述格式。

### 6.2 认证与用户

| 方法 | 路径 | 认证 | 用途 |
|---|---|---:|---|
| POST | `/auth/login` | 否 | 手机号密码登录 |
| POST | `/auth/register` | 否 | 手机号、密码、验证码注册 |
| POST | `/auth/sms/send` | 否 | 发送注册验证码 |
| POST | `/auth/sms/send-reset` | 否 | 发送重置密码验证码 |
| POST | `/auth/password/reset` | 否 | 重置密码 |
| POST | `/auth/password/change` | 是 | 修改密码 |
| POST | `/auth/logout` | 是 | 退出登录 |
| GET | `/users/me` | 是 | 获取当前用户 |
| PATCH | `/users/me` | 是 | 修改昵称、头像或头像 ID |
| GET | `/avatars` | 否 | 获取远端头像目录 |

注册和登录响应至少应提供 `token` 与 `user`。用户资料不得向搜索或好友列表暴露手机号。

### 6.3 好友

| 方法 | 路径 | 认证 | 用途 |
|---|---|---:|---|
| GET | `/friends` | 是 | 获取好友列表 |
| DELETE | `/friends/{friendId}` | 是 | 删除好友 |
| GET | `/friends/codes` | 是 | 获取自己的好友代码 |
| POST | `/friends/codes` | 是 | 创建好友代码，参数 `expiry` |
| PATCH | `/friends/codes/{id}` | 是 | 修改好友代码有效期 |
| DELETE | `/friends/codes/{id}` | 是 | 禁用好友代码 |
| DELETE | `/friends/codes/{id}/permanent` | 是 | 永久删除好友代码 |
| POST | `/friends/codes/redeem` | 是 | 兑换好友代码，参数 `code` |

前端当前使用的有效期值为 `1d`、`3d`、`7d`、`30d`、`permanent`。

### 6.4 聊天与通知

| 方法 | 路径 | 认证 | 用途 |
|---|---|---:|---|
| POST | `/chats` | 是 | 创建或获取私聊，参数 `targetUserId` |
| GET | `/chats` | 是 | 获取会话列表 |
| GET | `/chats/{chatId}/messages` | 是 | 获取历史消息 |
| POST | `/chats/{chatId}/messages` | 是 | 发送消息 |
| GET | `/chats/{chatId}/messages/sync` | 是 | 按 `after_seq` 增量同步 |
| GET | `/groups/{groupId}/messages` | 是 | 获取群聊消息 |
| POST | `/groups/{groupId}/messages` | 是 | 发送群聊消息 |
| PUT | `/chats/{chatId}/read` | 是 | 提交已读游标 `lastReadSeq` |
| GET | `/groups/{groupId}/messages/sync` | 是 | 增量同步群聊消息 |
| PUT | `/chat-settings/{chatId}` | 是 | 更新 `pinned`、`unread` |
| GET | `/notification-settings` | 是 | 获取通知设置 |
| PUT | `/notification-settings` | 是 | 保存通知设置 |

消息请求示例：

```json
{
  "content": "你好",
  "type": "text",
  "clientMessageId": "client-generated-id",
  "receiverId": "user-id"
}
```

`content` 去除首尾空白后应为 1～5000 个字符。`clientMessageId` 用于网络重试去重。聊天相关接口必须由服务端验证会话成员身份。
已读接口请求体为 `{"lastReadSeq": 123}`，服务端建议返回统一响应格式并包含服务端确认的 `lastReadSeq`，例如 `{"data":{"chatId":"chat-id","lastReadSeq":123},"message":"操作成功"}`。服务端必须保证未读计数、会话 `lastReadSeq` 与消息 `is_read`/`read_at` 的更新一致，并按会话成员校验权限。Socket.IO 可额外支持 `chat:read` 事件并通过 ack 返回结果，但 REST 已读接口是客户端主路径。Android 进程被系统或用户杀死后 Socket.IO 无法接收消息，服务端应提供 FCM、APNs 或等价推送；Socket.IO 只保证客户端进程存活且连接可用时的实时通知。


通知设置字段当前兼容 `chat`、`game`、`friend_request`、`system`；新服务建议统一使用 `friendRequest`。

### 6.5 远程震动

远程震动仅限一对一好友会话，单次目标时长为 500 毫秒。接收者必须同时满足以下条件：

1. 设备支持震动或系统触觉反馈；Android 使用应用声明的 `VIBRATE` 权限，iOS 不存在独立的震动授权弹窗。
2. 在该好友会话的聊天设置中主动开启“允许好友远程触发手机震动”。

| 方法 | 路径 | 认证 | 用途 |
|---|---|---:|---|
| GET | `/remote-controls/chats/{chatId}/vibration` | 是 | 获取本方授权状态及对方是否允许触发 |
| PUT | `/remote-controls/chats/{chatId}/vibration` | 是 | 保存本方授权，数据为 `{ "enabled": true }` |

读取状态至少返回：

```json
{
  "data": {
    "localEnabled": true,
    "peerAuthorized": true
  }
}
```

客户端默认将远程震动接收视为开启，用户可以在单个会话中明确关闭；本地默认开启不代表服务端已授权。服务端必须按会话和发起用户做好友关系、接收者授权和频率校验：同一发起方对同一接收方在任意滚动 60 秒内最多 3 次。无论客户端是否显示按钮，服务端都必须拒绝未授权和超限请求，并返回可展示错误，例如 `对方未授权震动控制功能`、`操作过于频繁，请稍后再试`。每次请求都必须写入不可篡改的审计日志，至少包含请求 ID、会话 ID、发起方、接收方、服务器时间、结果、拒绝原因及限流计数；日志不得记录 Token 或聊天内容。

### 6.6 Socket.IO

聊天与远程震动事件：

| 方向 | 事件 | 数据 |
|---|---|---|
| 客户端 | `auth` | `{token}` |
| 客户端 | `chat:join` | 会话 ID |
| 客户端 | `chat:send` | `chatId`、`content`、`type`、`clientMessageId` |
| 客户端 | `typing:start` / `typing:stop` | `chatId`、可选 `receiverId` |
| 客户端 | `remote:vibration:trigger` | `chatId`、可选 `receiverId` |
| 服务端 | `chat:message` | 消息对象 |
| 服务端 | `remote:vibration` | 已验证的 `{chatId, requestId, senderId}` 指令 |

客户端会在断线后重连，并通过 REST 同步聊天状态。

### 6.7 横幅、版本和功能卡片

| 方法 | 路径 | 认证 | 用途 |
|---|---|---:|---|
| GET | `/banners` | 否 | 首页远端横幅，参数 `platform`、`enabled` |
| GET | `/app/version` | 否 | 检查版本，参数 `platform`、`version`、`version_code` |
| GET | `/app/releases` | 否 | 获取发布记录 |
| DELETE | `/features/{featureId}` | 是 | 删除远端功能卡片 |

版本响应使用既有 snake_case 字段：`has_update`、`update_required`、`latest_version`、`version_code`、`min_version`、`min_version_code`、`release_notes`、`download_url`、`sha256`。

下载地址必须是受信任 HTTPS 地址；客户端安装前会校验下载文件哈希。

### 6.8 鸡尾酒

| 方法 | 路径 | 认证 | 用途 |
|---|---|---:|---|
| GET | `/cocktail/recipes` | 否 | 配方列表和搜索 |
| GET | `/cocktail/recipes/{recipeId}/interaction` | 是 | 当前用户收藏和评分 |
| PUT | `/cocktail/recipes/{recipeId}/favorite` | 是 | 收藏或取消收藏 |
| PUT | `/cocktail/recipes/{recipeId}/rating` | 是 | 提交 1～5 分 |
| GET | `/cocktail/notes` | 是 | 获取笔记 |
| POST | `/cocktail/notes` | 是 | 创建笔记 |
| PUT | `/cocktail/notes/{noteId}` | 是 | 修改笔记 |
| DELETE | `/cocktail/notes/{noteId}` | 是 | 删除笔记 |

配方查询支持 `q`、`keyword`、`taste`、`category`、`limit`、`offset`。远端笔记不可用时客户端回退到本地存储。

## 7. 本地数据与降级

- Token：`FlutterSecureStorage`；兼容迁移旧版 `SharedPreferences` Token
- 远程震动授权：`SharedPreferences`，按当前账号和会话隔离保存
- 聊天：SQLite `chat_game.db`，保存消息、同步序号和 outbox 待发送队列
- 首页布局：`home_features` 及 `website_card_*`
- 调酒台：`cocktail_bar_inventory_v1`
- 调酒笔记：`cocktail_notes`
- 出行计划：`travel_planner_state`
- Minecraft 配置：`minecraft_server_*`
- 静态资源：`assets/data/postal_codes.json`、`assets/data/cocktail_recipes.json`、`assets/avatars/`

网络失败时，前端保留本地聊天、调酒笔记、调酒台、出行计划和 Minecraft 配置。远端接口恢复后，能同步的模块由对应 Service 负责处理。

## 8. 安全和边界

- 不在日志中输出密码、验证码、JWT 或完整消息内容
- 仅允许 HTTPS 头像、网站和更新地址；外部地址还需经过 URL 校验
- APK 下载限制大小并校验 SHA-256
- Minecraft 查询连接由用户输入的服务器地址发起，客户端不把地址上传到业务 API
- 本地数据库和缓存只保存客户端必要数据
- API 权限、好友关系、会话成员和游戏规则必须由远端服务端最终校验

## 9. 测试

当前测试位于 `test/`，包括基础 Widget 测试和鸡尾酒模型测试。提交前执行：

```powershell
flutter analyze
flutter test
```

重点补测方向：登录状态恢复、消息去重与重试、Socket 断线恢复、好友操作越权防护、更新文件校验和各页面在无网络时的降级行为。

## 10. 客户端待办

1. 为聊天 Socket 增加更完整的协议状态模型和同步测试。
2. 将群聊、好友申请、已读回执等能力与远端接口完成联调。
3. 评估出行计划、Minecraft 服务器和调酒台是否需要云同步。
4. 完成动态功能后，再把对应接口加入本契约。

本文档只描述 Flutter 客户端和客户端依赖的接口，不描述后端实现、数据库迁移、管理员后台或部署方式。
