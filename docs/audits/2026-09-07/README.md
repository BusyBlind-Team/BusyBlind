# Fuckthon 仓库审计报告

审计日期：2026-09-07。结论：**可以继续作为原型开发，但当前不宜按稳定版本对外分发。** 核心问题集中在音频校准、暂停状态、奖励真实性、界面更新和数据可靠性。现有测试全绿，并未覆盖这些故障路径。

## 审计对象与方法

| 项目 | 本次范围 |
| --- | --- |
| 本地仓库 | 仓库根目录（本地工作区检出） |
| 远程地址 | `https://github.com/KymeFran/Fuckthon.git`，与用户给出的 SSH 地址指向同一仓库 |
| 审计提交 | `91698f453605711565c8a4a19f723ace82d24397` |
| 工作区状态 | 审计前后均无未提交修改；154 个受版本控制文件与审计副本逐文件校验一致 |
| 技术栈 | Flutter 3.47.2 / Dart 3.13.2；Riverpod、audioplayers、sensors_plus；本地 JSON 存储 |
| 覆盖 | 43 个 Dart 业务文件，共 5,986 行；现有测试、依赖锁文件、Android/iOS 配置、CI、README 与主要 Markdown 设计规则 |
| 执行方式 | 在独立副本中运行现有测试及审计复现；未修改业务源码、未提交或推送任何变更 |

本报告针对本地当前提交，未拉取远端最新分支，也不将 README 中的历史自检结论视为本次验证结果。PDF/DOCX 原始策划附件未逐页审读；没有进行真机测试、APK/iOS 构建、线上渗透、全 Git 历史密钥扫描或完整依赖漏洞库扫描。

## 结果概览

**共 11 项问题：P1 高优先级 5 项，P2 中优先级 6 项。** 这里的等级表示修复优先级，不是 CVSS 安全漏洞评分。P1 建议在下一轮对外体验前解决；P2 应进入稳定发布前的修复清单。

| 编号 | 等级 | 问题 | 证据 |
| --- | --- | --- | --- |
| F01 | P1 | 校准结束或退出后节拍仍持续播放 | R6 复现 |
| F02 | P1 | 校准偏移没有进入玩法判定时间 | R1 复现及调用链 |
| F03 | P1 | 暂停时会话时间仍前进，独立轮询继续处理玩法 | R2 复现 |
| F04 | P1 | 零操作退出可刷修为、成就 | R3、R9、R11 复现 |
| F05 | P1 | 存储变更不刷新页面，合成可重复扣花瓣 | R4、R5 复现 |
| F06 | P2 | 原地覆盖存档，损坏后静默变成新账户 | R12 验证恢复行为；写入风险静态确认 |
| F07 | P2 | CI 分发 APK 使用临时调试签名，升级链不可靠 | 构建配置静态确认 |
| F08 | P2 | 抽签后快速返回触发已卸载组件的 ref 异常 | R7 实际抛错 |
| F09 | P2 | 打坐系统返回绕过记录及成就结算 | R8 复现 |
| F10 | P2 | 助眠结算期间重新出现可点击的开始按钮 | R10 复现 |
| F11 | P2 | 过河“踩滑不提升难度”的规则没有执行 | R13 复现 |

## 逐项发现

### F01 · 校准节拍订阅未释放

位置：[lib/features/tutorial/calibration_page.dart:36–40,59–77](https://github.com/KymeFran/Fuckthon/blob/91698f453605711565c8a4a19f723ace82d24397/lib/features/tutorial/calibration_page.dart#L36)。

`listen()` 返回的订阅没有保存；16 次校准完成只设置 `_running=false`，退出页面的 `dispose()` 也没有取消订阅。`mounted` 判断只保护 UI 更新，声音播放在判断之前已经执行。

**实际结果：**进入校准并开始，退出页面后再产生一个节拍，SoundBank 的播放次数仍从 1 增至 2，订阅仍存在。生产实现使用持续的 periodic stream，因此会继续每 800ms 播放 tick；再次校准会新增另一条订阅，干扰后续闭眼修行，并持续累积节拍记录。

修复：保存 `StreamSubscription<int>`，在完成、重新开始和 `dispose` 时取消；处理中断与恢复。验收应覆盖校准完成、主动返回、重复进入后声音均正确停止。

### F02 · 校准结果未用于实际判定

位置：[lib/core/audio/input_capture.dart:33–45](https://github.com/KymeFran/Fuckthon/blob/91698f453605711565c8a4a19f723ace82d24397/lib/core/audio/input_capture.dart#L33)、[lib/core/practice/practice_host.dart:125](https://github.com/KymeFran/Fuckthon/blob/91698f453605711565c8a4a19f723ace82d24397/lib/core/practice/practice_host.dart#L125)；对照 [lib/core/audio/event_scheduler.dart:62](https://github.com/KymeFran/Fuckthon/blob/91698f453605711565c8a4a19f723ace82d24397/lib/core/audio/event_scheduler.dart#L62)。

输入捕获计算了补偿后的 `absUs`，但 `sessionUs` 仍取事件处理时的 `sessionNowUs()`。木鱼、数雨、钓花和过河均使用 `e.sessionUs` 判定；已有的 `toSessionUs(absAudioUs)` 没有接入此路径。

**实际结果：**模拟输入时间 1,000,000µs、用户偏移 200,000µs，得到 `absAudioUs=800,000`，玩法收到的 `sessionUs` 却仍为 1,000,000。用户完成校准后，对这些判定没有预期补偿；UI 调度延迟也进入判定误差。听潮的同步统计另外依赖轮询，本身也没有使用补偿后的输入时间积分。

修复：从原始事件统一映射至补偿后的会话时间，再交给玩法。验收应使用非零输出延迟、非零用户偏移以及模拟输入投递延迟，检查边界判定是否相应移动。

### F03 · 暂停并未冻结会话时间及玩法轮询

位置：[lib/core/audio/event_scheduler.dart:44,59,74–83](https://github.com/KymeFran/Fuckthon/blob/91698f453605711565c8a4a19f723ace82d24397/lib/core/audio/event_scheduler.dart#L44)、[lib/practices/fish_petals.dart:111](https://github.com/KymeFran/Fuckthon/blob/91698f453605711565c8a4a19f723ace82d24397/lib/practices/fish_petals.dart#L111)、[lib/practices/tide_breath.dart:88,145](https://github.com/KymeFran/Fuckthon/blob/91698f453605711565c8a4a19f723ace82d24397/lib/practices/tide_breath.dart#L88)。

`pause()` 只记录暂停时刻并取消已预约的定时器；`isRunning` 仍返回 true，`nowUs()` 直到恢复后才扣除暂停时间。钓花的 100ms 定时器和听潮的 120/200ms 定时器只检查 `isRunning`，其中断回调为空。

**实际结果：**暂停钓花后推进时钟 91 秒，只执行一次轮询就触发 `FinishReason.antiIdle`。在系统仍允许后台 Dart 回调执行的时段，咬钩、错过收杆、反挂机结束和呼吸统计仍可能被处理。恢复时会话时间又向回扣除暂停量，导致轮询保存的时间与会话时间不一致。设备完全挂起期间不会运行回调，因此具体出现时机依平台生命周期而异。

修复：明确区分活动、暂停和结束；暂停期间 `nowUs()` 固定为暂停时刻，独立轮询停止工作，恢复时重置积分基点。现有暂停测试只检查恢复后的时间，没有检查暂停过程中的值。

### F04 · 零操作退出可获得修为与成就

位置：[lib/practices/wooden_fish.dart:106–116](https://github.com/KymeFran/Fuckthon/blob/91698f453605711565c8a4a19f723ace82d24397/lib/practices/wooden_fish.dart#L106)、[lib/practices/count_rain.dart:216–218](https://github.com/KymeFran/Fuckthon/blob/91698f453605711565c8a4a19f723ace82d24397/lib/practices/count_rain.dart#L216)、[lib/domain/achievements.dart:44–50,91–95](https://github.com/KymeFran/Fuckthon/blob/91698f453605711565c8a4a19f723ace82d24397/lib/domain/achievements.dart#L44)。

木鱼空输入的标准差为 0，得到满质量；取消分支仍发 `6×quality`。数雨取消分支固定发 5 点。宿主会正常将这两种中断结果入账，单局 clamp 不限制重复开局。

**实际结果：**真实宿主中“开始木鱼 → 不敲击 → 系统返回”直接得到 **6 修为**，并解锁“心如止水”；数雨无输入取消得到 **5 修为**。另一个复现证明，7 条 `completed=false` 的记录也能满足“累计完成 7 次修行”的“日课”成就。

这与设计文档“修为只来自真实专注、可挂机口子视为 bug”的规则冲突，任何普通用户都可以重复操作，无需修改本地文件。

修复：零有效操作和零有效时长不得发奖；中断奖励以有效进度为依据；稳定性成就设置有效样本下限，完成次数只计真正完成的会话。至少加入空局、短局、连续取消的宿主级验收。

### F05 · Provider 未转发存储通知，造成显示陈旧和重复扣款

位置：[lib/di.dart:11](https://github.com/KymeFran/Fuckthon/blob/91698f453605711565c8a4a19f723ace82d24397/lib/di.dart#L11)、[lib/features/me/me_page.dart:16](https://github.com/KymeFran/Fuckthon/blob/91698f453605711565c8a4a19f723ace82d24397/lib/features/me/me_page.dart#L16)、[lib/features/monk/achievements_page.dart:17,77–84](https://github.com/KymeFran/Fuckthon/blob/91698f453605711565c8a4a19f723ace82d24397/lib/features/monk/achievements_page.dart#L17)、[lib/data/app_store.dart:180–186](https://github.com/KymeFran/Fuckthon/blob/91698f453605711565c8a4a19f723ace82d24397/lib/data/app_store.dart#L180)。

AppStore 是 `ChangeNotifier`，但注入采用普通 `Provider<AppStore>`。页面 `ref.watch(storeProvider)` 监听的是这个 provider，内部 `notifyListeners()` 不会触发相应重建。与此同时，`fuseFlower()` 在扣花瓣之前没有检查该花是否已拥有，防重复仅依赖 UI 隐藏按钮。

**实际结果：**“我”页渲染后把修为从 0 改为 100，画面仍显示 0。图鉴持有 6 片樱花瓣时，第一次合成后界面仍显示 6 片、按钮仍可点；再点一次，实际花瓣从 3 降至 0，图鉴始终只有一朵花。

修复：接入可通知的状态管理机制或显式监听；同时在数据层拒绝已拥有花朵的重复合成。验收需要从按钮操作观察 UI 和库存，不能只测 AppStore 的单个方法。

### F06 · 存档写入与恢复可能放大为全量进度丢失

位置：[lib/data/app_store.dart:18–29,259–270](https://github.com/KymeFran/Fuckthon/blob/91698f453605711565c8a4a19f723ace82d24397/lib/data/app_store.dart#L18)。

串行队列解决了并发写交错，但保存仍直接 `writeAsString()` 覆盖唯一 JSON 文件，没有临时文件替换或备份。加载时任何读取/解析异常都被视为 `{}`；写入错误只打印日志，调用者也无法等待一次明确的持久化成功。

**已验证部分：**给加载器提供包含原有 1,000 修为的截断 JSON，返回的是修为 0、记录 0、教程未完成的新状态，没有向调用者报告存档损坏。随后正常保存会覆盖该文件。**风险推断部分：**写入过程中进程终止或 I/O 故障可能留下这种截断内容；本次未进行断电/杀进程故障注入，不把它描述为已发生的数据丢失事故。

修复：同目录临时文件写入并刷新后原子替换，保留上一份有效备份；损坏文件隔离保留并支持恢复；提供可等待的保存结果和可见错误，避免静默进入空账户后覆盖原存档。

### F07 · APK 分发缺乏稳定签名和检查依赖

位置：[android/app/build.gradle.kts:32–36](https://github.com/KymeFran/Fuckthon/blob/91698f453605711565c8a4a19f723ace82d24397/android/app/build.gradle.kts#L32)、[.github/workflows/ci.yml:33–60](https://github.com/KymeFran/Fuckthon/blob/91698f453605711565c8a4a19f723ace82d24397/.github/workflows/ci.yml#L33)。

名为 release 的构建仍指定 debug signing。CI 使用新的托管 runner，没有恢复一份固定签名密钥的步骤，因此不同运行生成的 APK 不能依赖一致的签名身份完成覆盖升级。对外分发时，用户可能被迫卸载再安装，而项目数据全部在本地。APK job 还没有 `needs: check`，静态分析或测试失败时也可能上传产物。

这是配置层确认的发布风险，本次没有生成两份 APK 对比证书。Android 的升级要求与签名管理见[官方应用签名文档](https://developer.android.com/studio/publish/app-signing)。

修复：配置受控、稳定的发布/内测签名；合理管理版本号；让 APK job 依赖 check。验收应对连续两个版本做保留本地数据的覆盖安装，而不仅是安装成功。

### F08 · 抽签动画期间离开页面产生未处理异常

位置：[lib/features/monk/sign_page.dart:27–43](https://github.com/KymeFran/Fuckthon/blob/91698f453605711565c8a4a19f723ace82d24397/lib/features/monk/sign_page.dart#L27)。

700ms 延迟回调先执行 `ref.read(storeProvider)`，到写完数据后才检查 `mounted`。用户点击“抽签”后立刻返回，页面已经卸载，Riverpod 拒绝读取 ref。

**实际结果：**测试捕获到未处理 `StateError`，堆栈准确指向第 31 行，错误说明在组件卸载后使用 ref 不安全。该次抽签没有完成入账。这里确认的是 Dart 未处理异常，不据此断言所有 release 设备都会直接退出进程。

修复：取消可取消的计时器，或在异步回调起点检查 mounted；若产品决定离开后仍应完成抽签，则提前获取安全的数据层引用，把事务移出组件生命周期。明确“取消”与“继续完成”语义后验收。

### F09 · 打坐的系统返回跳过结算

位置：[lib/features/monk/meditation_page.dart:160–175,220](https://github.com/KymeFran/Fuckthon/blob/91698f453605711565c8a4a19f723ace82d24397/lib/features/monk/meditation_page.dart#L160)。

打坐记录和成就判断仅在长按触发的 `_exit()` 中运行，页面没有像 PracticeHost 一样拦截系统返回。系统返回直接销毁页面并取消定时器。

**实际结果：**进入打坐推进 60 秒，修为已到账 1 点；执行系统返回后页面关闭，但 `store.sessions` 仍为空。更长的打坐也会绕过“枯坐有味”等退出时才执行的成就判断。

修复：将所有退出方式汇总到幂等结算路径，结算完成后再允许路由返回，并测试长按、系统返回和重复退出。

### F10 · 助眠结算时错误返回开始状态

位置：[lib/core/practice/practice_host.dart:107–115,130–138,219–223](https://github.com/KymeFran/Fuckthon/blob/91698f453605711565c8a4a19f723ace82d24397/lib/core/practice/practice_host.dart#L107)、[lib/practices/tide_breath.dart:173–179](https://github.com/KymeFran/Fuckthon/blob/91698f453605711565c8a4a19f723ace82d24397/lib/practices/tide_breath.dart#L173)。

`_finish()` 先令 `_running=false`，再等待玩法结束；构建逻辑没有“正在结算”分支，于是显示开始界面。助眠淡出包含 11 次 400ms 等待，使这个窗口持续约 4.4 秒。`_begin()` 又没有检查 `_finishing`，开始按钮并非只做了错误展示。

**实际结果：**助眠模式点击“结束”后，立即出现有非空点击回调的“开始（磬响后请闭眼）”按钮。由调用链可知此时可再次调用同一个已结束 session 的 `start()`，重新开启计时器/音轨，破坏单次会话生命周期。复现测试验证的是按钮暴露；未在真机测量重新播放的听觉结果。

修复：用明确的 preparing/ready/running/finishing/finished 状态机；finishing 期间禁用启动及重复输入，助眠过程显示符合产品约定的黑屏。固定结算时刻，避免淡出等待计入有效训练时长。

### F11 · 过河踩滑仍推动难度上升

位置：[lib/practices/cross_river.dart:88–98,145–163](https://github.com/KymeFran/Fuckthon/blob/91698f453605711565c8a4a19f723ace82d24397/lib/practices/cross_river.dart#L88)。

成功和踩滑分别传入 `slip:false/true`，但 `_onStepped` 没有使用这个参数，两条路径最终都调用 `_nextJump()`。后者根据总跳数每五跳扩大间隔范围，因此“踩滑不死、难度不递进”的规则失效。

**实际结果：**使用确定性随机源，连续五次以 1.25 倍判定窗口的偏差踩滑，第六跳的 T 已超过初始 2,000,000µs 上限。该变化不是随机波动，是难度范围确实扩大。

修复：分离已通过石阶数与推动难度的有效通过计数；变奏的两段中任一踩滑是否阻止递进也需要统一处理，并加入边界测试。

## 测试证据与覆盖缺口

| 检查 | 实测结果 |
| --- | --- |
| 原仓库现有 Flutter 测试 | **45/45 通过** |
| 原业务源码与测试的 `dart analyze lib test` | **No issues found** |
| 独立审计复现集 | 13 个用例；12 个断言确认缺陷行为，1 个因真实未处理异常失败（R7） |
| 原仓库源码完整性 | 与审计副本受控文件一致；审计后 git status 为空 |

复现集刻意断言当前错误行为，以便记录证据，**“通过”表示问题被复现，不代表行为正确**。修复后应将这些断言改为期望行为。R7 保留非零退出结果及异常栈，不应计为环境故障。

现有测试还出现 [test/tutorial_test.dart:39](https://github.com/KymeFran/Fuckthon/blob/91698f453605711565c8a4a19f723ace82d24397/test/tutorial_test.dart#L39) 的 tap 未命中警告，但测试继续通过，不能据此确认试听按钮实际被点击。大量测试使用 SilentSoundBank、FakeClock 和内存存储，无法覆盖真实音频插件、校准节拍流、磁盘故障或原生传感器行为。视觉快照的去文字策略也不验证真实文本布局。

建议修复时优先保留本报告中已复现的用户操作链，增加跨页面状态变化、暂停中的时间、异步结束期间的按钮状态以及存档恢复测试。无需仅为了扩大数量而重复已有正常路径测试。

## 其他风险与未确认事项

- **iOS 传感器权限声明缺失：**`ios/Runner/Info.plist` 和 Xcode 配置中未看到 `NSMotionUsageDescription`。当前锁定 sensors_plus 7.1.0 的说明要求添加该键，且特别提及其气压计对 motion data 的访问。现有业务只订阅 accelerometer；本次没有在真机触发系统权限流程，因此不把“进入打坐必然崩溃”列为已确认问题。应补齐真实用途说明，并验证目标 iOS 版本。[插件官方说明](https://pub.dev/packages/sensors_plus/versions/7.1.0)
- **音频精度承诺过强：**EventScheduler 使用同一 Dart isolate 的 Timer，无法保证 UI 线程阻塞时声音仍精准；AudioPool 本地锁定版本默认仅预建一个播放器，业务只设置 maxPlayers，重叠播放可能动态创建播放器。README 已将原生时钟列为待办，但“禁止播放时解码/卡顿仍精准”的表述尚无真机证据。需测首音延迟、密集木鱼、蓝牙耳机、循环接缝及中断恢复。
- **安全检查边界：**在当前业务代码和配置的模式检索中未发现明显硬编码凭据、业务远程调用或命令执行入口；这是本地离线应用，好友页仍为占位。此结论不等于不存在历史泄漏、依赖漏洞或原生插件风险。未给出未经漏洞库验证的“依赖安全”结论。
- **文档漂移：**README 首次启动写成 `cd Fuckthon/busy_blind`，而当前 Git 仓库根目录本身已含 pubspec.yaml；按给定地址克隆后应进入 `Fuckthon`。测试数仍出现 35，与实际 45 不符；“陀螺仪未实现”的文字与已有加速度反挂机实现并存。建议统一功能完成状态与平台验收状态。
- **累计数据口径：**`sessionCount` 直接等于最多保留 300 条的历史记录长度；“累计修行次数”最终会停在 300。建议独立保存累计完成次数，历史明细截断仅影响浏览。

## 修复顺序与发布验收

1. **先修 F01–F05：**恢复音频校准与暂停语义，堵住零操作奖励，修正状态通知和重复合成；这些直接影响核心体验及用户资产。
2. **再修 F06、F08–F11：**完善存档恢复、异步任务和退出结算；让后台、返回、重复点击成为常规测试场景。
3. **发布前完成 F07 与真机验收：**连续版本覆盖安装且保留数据；iOS 传感器权限、锁屏/后台/来电、耳机延迟和真实音轨播放分别验证。

项目已有统一会话宿主、可注入时钟、确定性玩法测试、资产检查和 CI，这些结构有利于修复。当前主要缺口是跨层连接和异常路径的验证：内部单元逻辑可通过，并不保证真实导航、音频和持久化链路正确。

证据文件随报告一并提供：现有测试日志、静态分析日志、审计复现源码及完整复现日志。所有结论均基于上述提交，未自动实施修复。


## 随附证据

- [复现说明](evidence/README.md)
- [审计复现用例](evidence/audit_reproduction_test.dart.txt)
- [原有测试日志](evidence/baseline-test.log)
- [静态分析日志](evidence/baseline-analyze.log)
- [审计复现日志](evidence/reproduction-test.log)

上传版本将日志中的本机工作目录替换为 `<audit-worktree>` 并清理行末空白，保留异常、断言和测试结果。复现代码以 `.dart.txt` 附件保存在文档证据目录，不参与常规源码分析或测试发现。
