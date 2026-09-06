# 盲僧 busy·blind · App 骨架（v0.1）

[![CI](https://github.com/KymeFran/Fuckthon/actions/workflows/ci.yml/badge.svg)](https://github.com/KymeFran/Fuckthon/actions/workflows/ci.yml)

> 给忙碌的人的闭眼修行。本目录是按《盲僧·设计方案.md》（产品规则）与《忙僧·构建方案.md》（技术方案）落地的**初步实现**：两大基座 + 三页签壳层 + 六个修行插件全部可跑。
>
> **设计文档都在 [`docs/`](docs/)**：产品规则、技术方案、概念介绍，以及 `docs/文件资料/` 里的原始策划案与框架提示词。

## 启动方法

### 环境要求

- **Flutter SDK** ≥ 3.47（stable 渠道；开发机装在 `~/development/flutter`，建议把 `~/development/flutter/bin` 加进 `PATH`）
- **iOS**：Xcode（App Store 装完整版，首次打开同意协议）+ CocoaPods（`brew install cocoapods`）
- **Android**：Android Studio（自带模拟器与 SDK）
- 无需后端、无需任何 API key：数据全部本地优先，断网时除"加好友"外功能完整

### 首次启动（三步）

```bash
git clone git@github.com:KymeFran/Fuckthon.git   # 拉取仓库（或 HTTPS 地址）
cd Fuckthon/busy_blind
flutter pub get                                   # 拉依赖
```

然后直接运行（首次会编译原生工程，iOS 首次构建约 3–5 分钟）：

```bash
flutter run
```

### 选择设备

```bash
flutter devices                     # 看当前可用的设备
open -a Simulator                   # 打开 iOS 模拟器后，再 flutter run
flutter emulators                   # 列出安卓模拟器；flutter emulators --launch <id> 启动
flutter run -d <deviceId>           # 指定设备（多台同时在线时用）
flutter run --release               # 性能验证用 release 模式（音视频时序更真实）
```

建议优先用**真机 + 耳机**验证：这套玩法的命门是声音时序，模拟器的音频延迟偏大，只能验证功能、不能验证手感。

### 不装任何环境，直接装到手机（Android）

每次推送后 CI 会自动构建 release APK：打开仓库的 **Actions → 最新一次运行 → Artifacts → `busy_blind-apk`** 下载，传到手机直接安装（需允许"安装未知来源应用"）。iOS 因签名限制仍需 TestFlight 路线。

### 测试与工具

```bash
flutter test                        # 29 个测试（时钟调度 / 六个修行 / 本地存储 / widget 冒烟）
flutter analyze                     # 静态检查（当前无错误警告）
dart run tool/gen_sounds.dart       # assets/sfx/ 里的占位音效由脚本合成，可随时重新生成
```

### 常见问题

- `flutter: command not found`：Flutter 不在 PATH 里，`export PATH="$HOME/development/flutter/bin:$PATH"`（或用全路径调用）。
- iOS 构建报 Pod 相关错误：`cd ios && pod install --repo-update` 后重试；换过 Flutter 版本后先 `flutter clean`。
- 第一次启动没有声音：确认 `flutter pub get` 成功（音效在 `assets/sfx/`，随包加载）；仍无声时跑一次上面的音效生成脚本再 `flutter clean && flutter run`。
- 想清空本地数据重新体验：「我」页签 → 清空本地数据（调试）。

技术栈按构建方案：Flutter + audioplayers（短音效预载内存池）+ flutter_riverpod + 本地 JSON 存储（预留 Drift 迁移位）。

## 已实现

**基座一：AudioClock（`lib/core/audio/`）**
- `AudioClock` 接口 + `SystemAudioClock`：单一微秒时间源、输出延迟 L_out / 用户校准偏移 L_user 的补偿位、`touchToAudioUs` 判定补偿、节拍流。
- `EventScheduler`：按音频时间预排事件（200ms 提前预约），会话时间轴可暂停/恢复（中断恢复后节奏不乱）；声音事件自动进 SessionRecorder。
- `SoundBank`：audioplayers AudioPool 实现（预加载、多路复用）+ Silent 实现（测试用）；`SoundCatalog` 是全 app 统一的声音语义表（磬一声=开始/闭眼、磬两声=结束/睁眼、过河与钓花的叮/咚音色已分开）。
- `InputCapture` / `SessionRecorder`：全部输入与声音事件打音频时间戳，事后对账。

**基座二：修行插件契约（`lib/core/practice/`）**
- `PracticeManifest / PracticeSession / PracticeResult / PracticeContext / PracticeRegistry`，`PracticeHostPage` 统一收口：结算 → 修为 clamp → 成就判定 → 花瓣入库 → 写库 → 结算页。
- **模块化验收通过**：`静坐一分钟`（教程试玩）只依赖注入的四件套，未改宿主任何一行。

**Shell 与页面**
- 三页签「修 / 僧 / 我」横滑 + 底部图标栏（当前图标放大）。
- 僧页：修为条（当前/距下一级）+ 八级称号（浪子→菩萨）+ 立绘占位 + Low-Poly 四按钮。
  - **签**：每日一次，树叶签文 + 随机花瓣收藏（见"实现口径"#4）。
  - **成**：成就列表（未解锁灰色）+ 修为等级表常驻 + 花瓣图鉴（3 朵合成 1 朵）。
  - **禅**：打坐全屏（非修行插件）：+1 修为/60s、单日上限 60、退后台暂停、每 5 分钟极轻磬 + 30 秒在场确认、长按 2 秒退出。陀螺仪判定 TODO。
  - **友**：占位页（全 app 唯一强依赖网络的功能，未接后端）。
- 修页：点方块居中展开详情 + 确定/取消，参数面板（听潮三档节奏、助眠开关）。
- 校准页（我 → 时机校准）：跟拍 16 次取中位数写入 L_user。

**六个修行（`lib/practices/`）**

| 修行 | 状态 | 要点 |
|---|---|---|
| 静坐 | ✅ 完整 | 框架验收用例 |
| 木鱼 | ✅ 完整 | 108 声/目标 1s，无节拍音；每 36 声轻磬；偏差累积→音色变闷；quality 由间隔标准差决定，修为 12×quality；结算有心急/走神曲线 |
| 数雨 | ✅ 完整 | 5 分钟，雨滴 13s±4 / 钟声 30s±8；轻点记雨、长按(≥0.3s)记钟；反作弊（间隔≥800ms、10s 窗口≤3 事件，见口径#2）；修为 15×(1−误差) 下限 5 |
| 听潮 | ✅ 完整 | 4-6/4-7/4-8 三档；按住吸气、松开呼气；相位吻合叠风铃；助眠模式不弹结算、修为次日补发 |
| 钓花 | ✅ 完整 | 长按甩竿，前 2 秒不咬钩，概率 20%@10s→60%@60s；叮(65%)/咚(35%)；叮后 1.5s 内收杆；90s 无输入自动结算；花瓣入 extraRewards |
| 过河 | ✅ 完整 | 叮—咚间隔 T∈[0.6,2.0]s 复现；窗口 max(15%T,180ms)，1.5 倍内踩滑；每 5 跳扩范围、第 10 跳起 叮-咚-咚 变奏；修为 min(跳数×0.6, 20) |

音效全部为脚本合成占位（参数对齐声音语义表），正式音效直接替换 `assets/sfx/` 同名文件即可。

## 自检记录（持续更新）

每次自检发现的问题与优化都记在这里；CI（上方徽章）在每次 push 时自动跑 analyze + test 守门。

**第 1 轮（2026-09-07）**

- 修复：修行页运行中按系统返回会直接丢弃整局结果 → 拦截返回并按"用户结束"走正常结算收口（PopScope）。
- 修复：结算页没有返回入口 → 增加"回去"按钮。
- 修复：打坐页未实现反挂机第一重（退后台立即暂停计时）→ 补上生命周期观察。
- 修复：AppStore 连续快速变更时写盘可能交错 → 写入串行化排队。
- 清理：听潮残留的无用调度字段；相位推进逻辑简化。
- 机制：新增 GitHub Actions CI（push/PR 自动 analyze + test），首轮已绿。
- 补测：新增回归测试——修行运行中触发系统返回必须出结算页而不是直接退出（防改坏）。

**第 2 轮（2026-09-07）**

- 修复（重要）：调度器已触发的事件在 pause/resume 后被重放（退后台回来磬声重响）——`_fire` 未清 `armed`，`_cancelWallTimers` 会把已触发项重置。补回归测试锁死。

**第 3 轮（2026-09-07）**

- 修复：静坐未坐满即取消也发 1 修为，违反"修为只来自真实专注"→ 未完成不发修为。
- 修复：成就解锁对用户不可见 → 结算页展示本次新解锁的成就条目。
- 补测：完成修行显示成就的 widget 测试 + 静坐取消零修为单测（共 27 测）。

**第 4 轮（2026-09-07）**

- 修复：钓花"咚"后久握不放会把状态机吊死到 90s 反挂机 → 触竿 4s 超时自动空竿休整。
- 补测：钓花测试钩子（debugForceHook）+ 确定性测试覆盖"收手入库/叮超时流失/咚久握休整"三路径（共 28 测）。

**第 5 轮（2026-09-07）**

- 机制：CI 增加 APK 构建产物 job——每次 push 自动产出 release APK，无开发环境的手机可直接下载安装（check/apk 双 job 全绿）。
- 文档：README 增加"不装任何环境直接装手机"指引。

**第 6 轮（2026-09-07）**

- 修复：原始输入（down/up/cancel）此前不进 SessionRecorder，事后对账缺原始时间线 → 宿主统一记录后再分发给玩法（构建方案第四节原则落地）。

**第 7 轮（2026-09-07）**

- 优化：音效资产 4.3MB → 2.3MB（-47%）——环境循环与低频音轨降到 22.05kHz、裁掉不可闻衰减尾；瞬态音效保留 44.1kHz。gen_sounds 支持分音轨采样率。

**第 8 轮（2026-09-07）**

- 审查结论：推演"陈旧守门误杀后续跳跃"假设后证伪——合法握竿最长咚+2.3s，够不到咚+6s 的守门时刻，不构成 bug；把判定语义（松手−咚≈T，晚起手=偏差）固化进测试防回归。
- 加固：过河守门回调按跳跃 id 失效（防御性，意图显式化）。
- 补测：连踩 10 阶集成测试——覆盖难度递进与 叮-咚-咚 变奏第二段复现（此前无覆盖）。

**第 9 轮（2026-09-07）**

- 核对：README 测试数、待办中资产体积（第 7 轮后已变）、pubspec 版本号（对齐 v0.1.0 标签）三处文档漂移已修；修行表/修为公式/manifest 基准值逐项比对一致。

**已知待办（按优先级）**

1. AudioClock 换原生音频渲染时钟（接口已留好，短音效调度从毫秒级提升到采样级）。
2. 音效资产从 WAV 换压缩格式（OGG/MP3），可再省约一半（第 7 轮后 assets 约 2.3MB）。
3. 打坐的陀螺仪反挂机（第三重判定）。
4. 好友功能接入 Supabase（全 app 唯一联网功能）。
5. 手动结束交互（听潮/钓花右上角"结束"入口）待设计确认。

## 与设计方案/构建方案的实现口径（需团队拍板的都有注释标记）

1. **AudioClock v0.1 用单调时钟**而非原生音频渲染时钟。接口与构建方案完全一致，接 AVAudioEngine/Oboe/soLoud 时只换实现；短音效目前走 AudioPool（预载、无播放时解码），低延迟够用但非采样级调度。
2. **数雨"同一分钟 ≤3 个事件"与"雨滴 13s/滴（约 4.6 滴/分）"在设计方案内部矛盾**，按意图（防扎堆）实现为"任意 10 秒窗口 ≤3 个事件"。
3. **修为换算放在会话内、clamp 放在宿主**：公式属于玩法规则由会话给出（新修行不改宿主），宿主按 manifest.meritBase×3 统一封顶并单点入账。
4. **抽签奖励按设计方案建议 b**：发签文收藏 + 随机花瓣，不发修为；要改回 +10 修为只动 `SignPage`。
5. **听潮修为公式为拟定值**（分钟×2×quality，原方案"待定"）；钓花 quality 由平均等待与误收率构成（拟）。
6. **存储用 JSON 文档**（字段即未来 Drift 表草图），迁移 SQLite 只动 `AppStore`。
7. 手动结束的修行（听潮/钓花）在右上角有小"结束"入口——正式交互待定。
8. 好友、陀螺仪反挂机、双修、Supabase 同步：未实现，占位已留。

## 目录

```
lib/
  core/audio/        基座一：clock / scheduler / soundbank / recorder / input
  core/practice/     基座二：契约 / 宿主 / 注册表
  domain/            修为等级 / 成就 / 花瓣 / 签文
  data/              AppStore（本地优先 JSON 存储）
  shell/             三页签
  features/          僧页四按钮页面 / 我 / 校准 / 修行列表
  practices/         六个修行插件（新增修行 = 加一个文件 + 注册表一行）
  widgets/           Low-Poly 按钮 / 立绘占位 / 曲线 / 花瓣
tool/gen_sounds.dart 音效合成脚本
test/                时钟调度 / 六个修行 / 商店 / widget 冒烟
```
