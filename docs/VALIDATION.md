# v0.2 验证 · 2026-09-25

- 900 组规则、3,600 次 AI 合法性检查通过。
- 末拍边界：1.40 秒不锁定、1.80 秒锁定、跨轮节拍顺序通过。
- 成就：10/20/30 门槛、重复不重发、跨局不累计、首胜、本地重读通过，测试使用隔离存档。
- 流程：命中前延迟、140ms 定格、后台暂停终结、恢复倒数、重玩和展台通过。
- 实际引擎录制 `showcase-v2.mp4`，人物/终结/成就截图已人工查看。
- Android v0.2 ARM64 debug APK 已导出并通过签名校验；Android 14 模拟器安装、启动、成就页、返回首页、进入对战与触屏选攒均通过。当前进程日志未发现 Godot 脚本错误或崩溃，未测试实体手机。
- iOS 已重新导出项目。系统现已能识别 26.5 模拟器运行时，但 Xcode 构建仍报 `iOS 26.5 Platform Not Installed`，模拟器链接还报 `framework MetalFX not found`；平台工具链仍不完整。不能报告 iOS 构建或运行成功，也没有可安装 IPA。

以下保留 v0.1 的历史验证记录。

# 验证记录 · 2026-09-19

## 已通过
- Godot 4.4.1 编辑器导入、脚本解析和 Apple M2 Compatibility 实际渲染。
- 规则：900 个动作/能量组合，对称性、能量范围、不能双败；普通波/防/攒和强化克制的明确案例。
- AI：3,600 次决策均合法；函数只接受双方公开能量和历史。
- 流程：选择、后台时钟冻结、3 秒恢复倒数、胜利结算、重玩清零、返回首页、单人展台。
- 原生 Android：ARM64 debug APK 导出并通过签名校验，Android 14 模拟器安装、启动、触屏进入对战和选攒，中文字体与真实 3D 渲染正常。
- 14.5 秒动作演示由 Godot Movie Maker 实际渲染，非概念视频。

## 平台产物与限制
- `builds/bobozan-debug.apk`：约 39 MB，测试签名 APK，可供 ARM64 Android 试玩；未测试实体手机、持续发热、音频延迟和不同厂商后台策略，不是商店发行包。
- `builds/ios/Bobozan.xcodeproj`：已用官方匹配 iOS 模板导出，可在 Xcode 中继续配置。
- iOS 编译尝试被本机环境阻塞：`Launch Screen.storyboard: error: iOS 26.5 Platform Not Installed.`；`simctl list runtimes` 也无可用运行时。需在 Xcode 设置 Components 安装匹配 iOS 平台组件后重试。
- iOS Team ID `0000000000` 仅用于无签名导出验证，是占位符，不代表开发团队。真机安装必须替换为用户真实团队及有效签名。未生成可安装 IPA，未进行 iOS 模拟器或真机运行测试。
- 蓝牙未实现，跨平台可行性未验证。

## 可复现命令
在项目目录执行：
```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/test_rules.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/test_flow.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --export-debug Android
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --export-debug iOS
```
导出使用 `builds/templates` 中的官方模板；若缺失可执行 `python3 tools/fetch_templates.py` 重新获取指定版本的 Android/iOS 两个文件，ZIP CRC 会验证完整性。本机原有 Android APK 模板为损坏的 9 字节文件，项目未覆盖该全局文件，已使用工程内官方模板。Gradle 备用路径曾受依赖下载阻塞，最终 APK 使用官方预编译模板完成。

## 试玩后待确认
强化波/防的成本和破防规则、能量上限、每拍 0.7 秒是否顺手、角色风格和动画精细度。当前模型是可运行的程序化几何原型；未来可替换为 Blender 制作的绑定模型，保留动作接口与规则层。

## 0.3 原生蓝牙开发版（2026-09-26）

Android Gradle 构建与 Godot 导出成功；`builds/bobozan-v0.3.apk` 已通过 apksigner 验签与 ZIP 完整性检查，包含 BoboBle 原生类、蓝牙权限和 Godot 许可。尚未在手机安装或完成无线互联，本次环境 adb 无已连接设备。

规则、AI、时间边界、离线流程、成就测试通过。新增 `test_network.gd` 连续 35 回合同步测试通过；`test_network_flow.gd` 双游戏场景的主客视角、决胜动画与退出通过。模拟链路 30 毫秒单程延迟、317 毫秒时钟差；不等于 BLE 实机表现。

iOS Swift 源码类型检查与修改后的 Xcode 工程格式检查通过。完整构建仍在 CompileStoryboard 阶段报 `iOS 26.5 Platform Not Installed`；没有已验证的 IPA。Xcode 账号列表仍为空，现有证书所属邮箱未核对。

提交状态与剩余事项见 `release/APP-STORE-READINESS.md`。`home-v3.png` / `privacy-v3.png` 是桌面引擎实际渲染截图。
