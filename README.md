# 忙僧 · busy·blind

给忙碌的生活，留一点安静。

忙僧是一款以声音互动为主的专注与呼吸练习 App。听雨、敲木鱼、跟随潮声呼吸，或在池塘边等一片花瓣上钩。练习之外，也可以收集花瓣、合成花朵，记录自己的修行进度。

[下载与发布](https://github.com/BusyBlind-Team/BusyBlind/releases) · [反馈问题](https://github.com/BusyBlind-Team/BusyBlind/issues) · [参与贡献](CONTRIBUTING.md)

## 支持平台

**当前面向 Android 发布。** iOS 工程仍不完整，暂不开发、不提供安装包，也不承诺可正常运行。其他平台暂未作为发布目标验证。

## 可以做什么

| 练习 | 体验 |
| --- | --- |
| 木鱼 | 按自己的节奏敲击，练习维持稳定的一秒间隔。 |
| 数雨 | 静静听雨、默数雨滴，结束后填写听到的数量。 |
| 听潮 | 跟随音乐练习呼吸，可选择 4–6、盒式或 4–7–8 节奏。 |
| 钓花 | 按住屏幕抛竿，听到花瓣上钩的提示后松手收取。 |
| 过河 | 听一段音符间隔，再用按住和松开屏幕复现节奏。 |

还包括打坐、每日一签、修为与成就、花瓣收集和花朵图鉴。好友功能尚未接入服务，暂不可用。

## 安装与使用

1. 打开 [Releases](https://github.com/BusyBlind-Team/BusyBlind/releases)，选择一个已发布版本。
2. 下载该版本附件中的 `.apk` 文件。`Source code` 是源码压缩包，不是安装包。
3. 在 Android 手机上打开 APK，按系统提示允许该来源安装应用。
4. 首次进入后跟随教程体验；建议佩戴耳机，并先调到舒适音量。

如果 Releases 中还没有 APK，说明公开安装包尚未发布。Actions 中的构建产物用于开发验证，不等同于正式发布版本。

更新时优先直接覆盖安装；若提示签名不一致，不要为安装新版本贸然卸载旧版，卸载可能清除本地记录。先查看对应版本的升级说明。

## 数据与联网

- 修行记录、收藏和设置保存在本机，核心练习不需要账户或 API Key。
- 修炼报告支持本地模板，也可由你自行配置兼容的 AI 服务生成。
- 使用 AI 报告时，应用会将修行聚合统计发送到你配置的服务；该服务可能收费。不使用 AI 报告不影响核心练习。
- 当前 API Key 以明文保存在本地 JSON 中。请勿把个人数据文件、备份或密钥提交到仓库或附在问题反馈里。
- 暂无云同步；卸载或清除应用数据可能丢失本地记录。

## 从源码运行（Android）

使用与 [CI](.github/workflows/ci.yml) 一致的 Flutter **3.47.2 stable**、JDK **17**，并安装 Android SDK。连接 Android 真机，或启动 Android 模拟器。

```bash
git clone https://github.com/BusyBlind-Team/BusyBlind.git
cd BusyBlind
flutter pub get
flutter devices
flutter run -d <设备ID>
```

检查与构建：

```bash
flutter analyze
flutter test
flutter build apk --release
```

APK 默认输出到 `build/app/outputs/flutter-apk/app-release.apk`。公开分发前还需要配置发布签名，详见[发布说明](docs/RELEASING.md)。模拟器适合检查界面与基本流程，声音时序和流畅度以真机体验为准。

## 参与开发

欢迎提交问题与 Pull Request。请先阅读[贡献指南](CONTRIBUTING.md)。

项目使用 Flutter、Riverpod 和 audioplayers；练习逻辑位于 `lib/practices/`，音频与练习公共能力位于 `lib/core/`，本地数据位于 `lib/data/`。

早期设计与审计资料保留在 `docs/`；[历史 README](docs/README-history.md) 中的旧规则和测试数量不代表当前版本。

## 许可证

项目代码采用 [MIT License](LICENSE)。第三方依赖和音频、美术素材的授权须分别遵守其适用条款，代码许可证不替代第三方素材授权。素材来源说明与问题反馈见[素材说明](ASSET_NOTICE.md)。
