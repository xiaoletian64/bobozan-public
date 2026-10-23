# 直播答题 → 小爱音箱提醒

> 重新解包审计修正（2026-10-17）：App 登录与默认商家网页登录不同。乐播购短信发送在 App 中有前置滑块，验证码登录后还可能需要选账号或微信授权；现有 CLI 尚未完整实现这些流程。千果 App 登录入口为 GET app/live/appLogin，平台账号 token 与直播间 memberToken 分层。真实登录和续期均未完成验证。以 ../../out/apk-interface-analysis/reanalysis/重新解析结论.txt 为最新认证结论。

实现与 APK 证据分开保存，游戏工程没有接入此工具。它只提醒，不提交答案、不领取奖励、不伪造观看时长或签到数据。

## 当前验证范围

- 已还原千果取题接口、逐题提交、整组提交、跳转判断和 IM 群消息调用链。
- `getLiveAnswerList` 的 `isCanAnswer`、`jumpPage` 的 `ANSWER_PAGE/ANSWER_POPUP` 和 IM 文本 `hcj_im_token_ANSWER` 是候选信号。代码证据已确认，真实账号下的时序尚未验证。
- GET 状态轮询、被动响应观察、持久化去重、失败重试、小爱单设备 TTS 适配已实现。默认只在控制台输出。
- 第一包已确认为“乐播购”。已在干净模拟器运行原生 `libpush.so` 成功生成签名，实际请求 `GetDomain` 成功，取得动态 H5 入口 `https://wx.7948.cn/`。沿远端页面路由定位到答题接口、IM 511 活动消息、790/791 题目显示/结束消息。
- 乐播购取题接口为 `POST https://live-gw.njyqkj0ksyz.com/generic/v1/h5/answer/get_question_list`，参数 `topicId`，form 编码。成功响应中 `dataObj.answerReward.state=1` 表示活动中；已答题、未开始和已结束不提醒。个人观看/签到资格还有额外条件，因此播报“有答题活动，请查看条件”，不声称已满足个人条件。
- 尚无真实账号会话、实际直播间 ID 和小爱音箱授权，所以未完成两款 App 与真实音箱的端到端联调。工具不会后台自动发验证码。

## 离线验证

在本目录运行：

```sh
python3 -m unittest -v
python3 reminder.py replay --config config.demo.json --input demo.jsonl
python3 reminder.py check --config config.example.json
```

也可以双击 `演示.command`。模拟输入包括未开始、开始、重复、弹窗和未确认的第一包信号；千果和乐播购各输出一次模拟提醒。这不能证明真实音箱已经播报。

## 两款 App 状态轮询

复制 `config.example.json` 为 `private/config.json`，使用绝对路径设置 `state_file`、`qianguo.headers_file`，填入当前观看直播间的 `live_id`。请求头文件只保存在本机 `private/` 内，权限设为 `600`，格式为登录产生的请求头对象，例如 `{"memberToken":"实际登录态","packageName":"cn.qianguo.podcast"}`。如实际请求还有 `token`，一并填入。不要把登录态提交到版本库。

```sh
python3 reminder.py poll --config private/config.json --once
python3 reminder.py poll --config private/config.json
```

默认同时检查两款 App；`--provider qianguo` 或 `--provider lebogou` 可单独检查。千果调用 `GET https://api.qianguolive.cn/qg/app/live/getLiveAnswerList/{liveId}`。乐播购调用上文的 `get_question_list`，配置 `lebogou.topic_id` 和私有请求头文件；请求头须包含实际登录产生的 `buid`，并保留原请求中的用户标识、Cookie/Authorization 等必要字段，不能拿手机号代替这些登录态。默认 15 秒一次，最短 10 秒；失败后退避至最多 5 分钟。登录失效会显示检查失败，不会误报为“答题未开始”。没有伪造用户时长；若服务端要求持续在 App 内观看，该程序不能替代实际观看。

## 小爱音箱

使用 MiService 3.0.1 的 `MiNAService.text_to_speech(deviceID, text)`，调用小米云端的单设备 TTS。依赖已安装在本目录隔离的 `.venv` 中；其他机器可用 `pip install -r requirements.txt` 安装。

```sh
.venv/bin/python speaker.py login private/mi-token.json
```

交互登录直接把账号提交给小米，密码不会显示；需要验证码时在终端输入。返回设备清单中 `device_id` 才是这里要填的值，不能用其他设备的 miotDID 代替。

配置 `speaker`：

```json
{
  "type": "miservice",
  "device_id": "登录清单中的 device_id",
  "python_executable": "/绝对路径/.venv/bin/python",
  "token_file": "/绝对路径/private/mi-token.json"
}
```

本工具不使用 `miservice mina 文本` 命令，因为该版本 CLI 会向所有音箱广播。这里直接调用单个 deviceID，并检查返回是否成功；失败不写入已通知记录。

上游实现与说明：[MiService](https://github.com/Yonsm/MiService)。小米服务可用性、账号风控和具体音箱兼容性仍需真实设备验证。

## 被动观察两个 App 的响应

`proxy_addon.py` 是可选的 mitmproxy 适配器。它不修改系统代理、不安装证书、不改变 APK，也不主动重放任何业务请求。仅当测试设备已有可用且已授权的调试代理配置时使用：

```sh
ANSWER_REMINDER_CONFIG=/绝对路径/private/config.json mitmdump -s /绝对路径/proxy_addon.py
```

这需要另行安装 mitmproxy。Android App 若不信任调试证书或启用了证书固定，无法通过这个适配器观察 HTTPS；本次没有修改信任设置或绕过固定。

千果响应根据已确认路径识别。乐播购根据已确认的 `get_question_list` 响应和已解码 IM 的 511/790/791 判断。其他允许域名响应只保存字段名与类型到 `private/lebogou-schemas.jsonl`，不保存响应值、登录响应、Cookie 或请求头；自定义新规则可以放在 `lebogou_rules`。

WebSocket 适配器仅接受已解码的 TIM JSON 消息；原始二进制/Protobuf IM 数据没有在此工具中实现解码。已经登录的 TIM SDK 可把 `MESSAGE_RECEIVED` 消息规范化后交给 `classify`，但本次尚未建立真实 TIM 会话。

## 证据

`../../out/apk-interface-analysis/分析结果.txt` 和同目录 JS/Java 片段记录了本次还原依据。远端 H5 脚本为 2026-10-17 抓取，可能随服务端发布变化；第一包 JADX 有 234 处反编译错误，不能宣称所有路径均已还原。


## 乐播购原生签名与登录客户端

`native_signer/` 是与原 APK JNI 名称一致的最小 Java 调用器，`lebogou_client.py` 从用户给定 APK 提取原生库，在指定的干净 arm64 安卓模拟器里调用它，不依赖安装到手机，也没有修改原 APK 或绕过账户认证。本次验证的 SDK/版本为 Android SDK 36 工具、API 34 arm64 模拟器、乐播购 260703。

```sh
python3 lebogou_client.py prepare --apk /实际路径/base.apk.1 --serial emulator-5580
python3 lebogou_client.py domain --serial emulator-5580
```

`domain` 已实际验证返回 `isok=true`、`https://wx.7948.cn/`。模拟器须先启动。`prepare` 仅把签名调用器和原生库推入该模拟器 `/data/local/tmp/`；副本在本工具 `private/native` 中，未放到公共源码中。

客户端也实现了 `send-code` 和 `login` 两个交互命令，对应 `SendNormalUserLoginVerifiyCode`、`NormalUserLoginByPhoneV2`。仅在主动运行这些命令时从终端读取手机号/验证码；登录成功响应只保存到 `private/lebogou-login.json`（600 权限）。这两个账户操作本次没有执行，也未验证实际短信投递、风控和登录后 H5 会话衔接。

## 本次实际执行结果

- 干净模拟器安装乐播购原包成功；没有使用用户现有手机或账号。
- 原生签名 → 正常 GetDomain 请求 → 服务端成功响应已实测；证据见 `lebogou-domain-verified.json`。
- 两包模拟响应回放与自动化测试可在本目录复现。
- 两款 App 的真实直播提醒、小米登录和真实音箱发声尚未验证，没有配置后台常驻服务。


## 登录态保存与正常续期

`session_store.py` 使用原子替换写入本机私有文件（600 权限），不会把 token 写入聊天或普通日志。只有配置了 `session_file` 的已登录账号才执行续期，每小时最多一次；轮询程序运行时自动维护，尚未安装后台常驻服务。

- 乐播购：按照 APK 的 WXTokenHelper，使用已登录取得的 `encryptUserId` 调用 `POST https://liveauth.njyqkj0ksyz.com/api/v1/login/get_wx_token`，保存返回 token 与服务端到期信息。
- 千果：按照 H5 的缓存恢复流程，使用现有 memberToken、实际 merchantId/liveId/openIdType 调用 `POST app/live/silenceLogin`，原子更新返回 memberToken。
- 这两条是代码中观察到的正常会话恢复流程；不是承诺永久免扫码。服务端吊销、风控或会话恢复被拒绝时保留原凭据并报告需要重新登录。尚未使用真实账号验证续期。

私有 session 文件只保存该账号所需的字段，例如乐播购的 `encryptUserId`，或千果登录时实际使用的 `openIdType`；不要猜测它们。`qianguo.merchant_id` 来自真实直播链接。
