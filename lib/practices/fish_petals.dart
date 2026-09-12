import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/audio/input_capture.dart';
import '../core/audio/sound_catalog.dart';
import '../core/practice/practice_manifest.dart';
import '../core/practice/practice_result.dart';
import '../core/practice/practice_session.dart';
import '../core/practice/practice_types.dart';
import '../domain/petals.dart';
import '../widgets/practice_scene.dart';

/// 钓花（耐心 · 收集）——听觉化改造版（设计方案 7.4）。
///
/// 玩法循环：长按甩杆（浮漂固定在落点）→ 聚瓣期（触竿概率随本次甩杆
/// 时长上升：前 2 秒为 0，10 秒约 20% → 60 秒约 60%）→ 花瓣/杂物**自然
/// 漂进浮漂判定半径**才触竿（Bug 描述 #5：不能远程钓到），响"叮"（花瓣）
/// 或"咚"（杂物）→ "叮"后 1.5 秒内松手收杆；"咚"后松手为空竿 → 松手后
/// 2 秒休竿期。
/// 反挂机：连续 90 秒无有效输入自动进入结算。
/// 花瓣经 extraRewards 返还宿主入库；核心判定全走听觉，
/// 画面只是睁眼奖励层。
/// 钓竿状态机：idle → casting（按住）→ hooked（已触发叮/咚）→ 休竿 → casting…
enum _RodState { idle, casting, hooked, resting }

class FishPetalsSession extends PracticeSession {
  static const int _noBiteBeforeUs = 2000000; // 前 2 秒概率为 0
  static const int _restUs = 2000000; // 休竿期
  static const int _catchWindowUs = 1500000; // "叮"后收杆窗口
  static const int _hookTimeoutUs = 4000000; // 触竿后最长握竿时长，超时自动休整
  static const int _antiIdleUs = 90000000; // 90 秒无输入自动结算

  /// 钓到各稀有度花瓣的概率（新改进意见）：常见 70% / 稀有 25% / 奇珍 5%。
  ///（叮/咚的比例不再固定 65/35：由漂进判定半径的东西类型决定，
  /// Bug 描述 #5 的距离判定让上钩类型回归物理。）
  static const double _rareChance = 0.25;
  static const double _legendaryChance = 0.05;

  /// 按概率抽稀有度：常见 70% / 稀有 25% / 奇珍 5%。
  PetalRarity rollPetalRarity() {
    final r = _rng.nextDouble();
    if (r < _legendaryChance) return PetalRarity.legendary;
    if (r < _legendaryChance + _rareChance) return PetalRarity.rare;
    return PetalRarity.common;
  }
  static const int _meritPerPetal = 3; // 待对齐清单 #5：钓到花瓣数 × 3

  late PracticeContext _ctx;
  final Random _rng;

  FishPetalsSession({Random? rng}) : _rng = rng ?? Random();

  /// 池塘模拟：会话所有，玩法判定（上钩距离门槛）与视觉渲染共用。
  final PondModel pond = PondModel();

  _RodState _state = _RodState.idle;
  int _castStartUs = 0;
  int _hookAtUs = 0;
  bool _hookIsPetal = false;
  int _restEndUs = 0;
  int? _lastInputUs;
  Timer? _pollTimer;

  // 统计。
  int _petalsCaught = 0;
  int _miscatch = 0; // "咚"后收杆次数（空竿）
  int _missed = 0; // "叮"后超时未收
  int _casts = 0;
  final List<int> _waitTimesUs = [];
  final List<Reward> _caught = [];

  bool _finished = false;

  @override
  PracticeManifest get manifest => const PracticeManifest(
    id: 'fish_petals',
    // §14.2：在所选 BGM 之上叠加溪流水声。
    ambience: AmbiencePolicy.stream,
    name: '钓花',
    subtitle: '叮则收手，咚则空竿',
    tags: [TrainingTag.patience, TrainingTag.collect],
    eyeMode: EyeMode.eyesClosed,
    typicalLength: Duration(minutes: 4),
    meritBase: 12,
    iconKey: 'fish_petals',
    allowManualEnd: true,
    rulesText:
        '长按屏幕把浮漂落在手指处，落定后就固定在那里，闭眼等。\n刚投下会惊散附近的花瓣——前两秒不会有人上钩；\n'
        '花瓣和杂物会慢慢漂回浮漂，漂到跟前才可能上钩。\n'
        '"叮"是花瓣碰漂，1.5 秒内松手收杆；"咚"只是杂物，收了也是空竿。',
    introTags: '趣味·耐心·收集',
    intro: '甩杆，然后静候。频繁地甩杆会惊动花瓣，所以请耐心等待，它们会上钩的。不要心急，否则只会钓起一堆杂物。',
  );

  /// 触竿概率曲线：随本次甩杆时长上升（10s≈20% → 60s≈60%，每秒概率）。
  static double biteRatePerSecond(int heldUs) {
    if (heldUs < _noBiteBeforeUs) return 0;
    final s = heldUs / 1000000;
    const p10 = 0.20;
    const p60 = 0.60;
    if (s <= 10) {
      return p10 * (s - 2) / 8;
    }
    return (p10 + (p60 - p10) * (s - 10) / 50).clamp(p10, p60);
  }

  @override
  Future<void> prepare(PracticeContext ctx) async {
    _ctx = ctx;
    _lastInputUs = 0;
  }

  @override
  void start() {
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _poll(),
    );
  }

  /// 本次甩杆已等待的秒数（模型聚拢力度用；非甩杆状态为 0）。
  double _holdSecondsAt(int nowUs) =>
      _state == _RodState.casting ? (nowUs - _castStartUs) / 1e6 : 0.0;

  void _poll() {
    if (_finished || !_ctx.scheduler.isRunning) return;
    final now = _ctx.scheduler.nowUs();

    // 反挂机：连续 90 秒无有效输入。
    final last = _lastInputUs ?? 0;
    if (now - last >= _antiIdleUs) {
      _ctx.requestFinish(FinishReason.antiIdle);
      return;
    }

    // 由会话时间推进池塘（P1）：判定要求"物件漂进浮漂 36px 内"，
    // 若只由绘制帧推进，关闭动画/无障碍导航后物件永不移动、永远
    // 上不了钩，最终只能被反挂机收口。动画正常时帧驱动已消费掉
    // 大部分时间差，这里只补残差，不会双倍推进。
    pond.advance(now, holdSeconds: _holdSecondsAt(now));

    switch (_state) {
      case _RodState.casting:
        // Bug#5（第二轮 §5.6）：不再用"每秒概率 × 0.1"抽是否触竿，改为
        // 纯物理判定——物体漂进内层判定圈即上钩（外层加速圈会先把它导向
        // 浮漂）。等待越久、朝向浮漂的偏向概率越高，触竿自然越容易，
        // 原来的耐心训练意图由物理本身承载。
        final pending = pond.takePendingHook();
        if (pending != null) _hook(now, pending);
      case _RodState.hooked:
        final held = now - _hookAtUs;
        // "叮"后超时未收手：花瓣随波而去。
        if (_hookIsPetal && held > _catchWindowUs) {
          _missed++;
          _sinkAndRest(now);
        } else if (held > _hookTimeoutUs) {
          // "咚"后长时间握着不放：自动空竿休整，不把状态机吊死。
          _sinkAndRest(now);
        }
      case _RodState.idle:
      case _RodState.resting:
        break;
    }
  }

  void _restFrom(int now) {
    _state = _RodState.resting;
    _restEndUs = now + _restUs;
    pond.setBuoyShown(false);
    notifyVisualChanged();
  }

  /// 上钩的东西到点沉底（复审 R3）：沉没声与视觉状态都由会话状态机在
  /// 会话时间轴上发出——不依赖绘制帧率，关闭动画/无障碍模式下时机一致。
  void _sinkAndRest(int now) {
    pond.sinkHooked();
    _ctx.sounds.play(SoundCatalog.fishSinkKey, gain: 0.9);
    _ctx.recorder.log('sink', {'petal': _hookIsPetal});
    _restFrom(now);
  }

  void _hook(int now, PondItem item) {
    // 上钩者由池塘模拟给出（漂进判定圈的那一件），类型由它自己决定。
    _hookAtUs = now;
    _hookIsPetal = item.isPetal;
    pond.hookItem(item);
    _ctx.sounds.play(_hookIsPetal ? SoundCatalog.fishDingKey : SoundCatalog.fishDongKey, gain: 0.9);
    _ctx.recorder.log('hook', {
      'petal': _hookIsPetal,
      'waitMs': (now - _castStartUs) ~/ 1000,
    });
    _state = _RodState.hooked;
    notifyVisualChanged();
  }

  // ---- 测试钩子：绕过随机触发与距离门槛，直接把状态机推到触竿态 ----
  @visibleForTesting
  void debugForceHook({required bool petal}) {
    final now = _ctx.scheduler.nowUs();
    _castStartUs = now;
    _hookAtUs = now;
    _hookIsPetal = petal;
    pond.forceHook(petal: petal);
    _state = _RodState.hooked;
    notifyVisualChanged();
  }

  @visibleForTesting
  bool get debugIsResting => _state == _RodState.resting;
  @visibleForTesting
  int get debugPetals => _petalsCaught;
  @visibleForTesting
  int get debugMissed => _missed;
  @visibleForTesting
  int get debugMiscatch => _miscatch;
  @visibleForTesting
  PondModel get debugPond => pond;

  @override
  void onInput(InputEvent e) {
    if (_finished) return;
    if (e.phase != PointerPhase.move) {
      _lastInputUs = e.sessionUs;
    }
    final now = e.sessionUs;

    switch (e.phase) {
      case PointerPhase.down:
        // 甩杆：浮漂落在手指处并固定（Bug 描述 #5：不能在屏幕上移动）。
        final pos = e.position;
        if (_state == _RodState.idle ||
            (_state == _RodState.resting && now >= _restEndUs)) {
          _state = _RodState.casting;
          _castStartUs = now;
          _casts++;
          if (pos != null) pond.setBuoy(pos, shown: true);
          _ctx.sounds.play(SoundCatalog.swishKey, gain: 0.6);
          _ctx.recorder.log('cast', {'at': now});
          notifyVisualChanged();
        }
      case PointerPhase.move:
        break; // 浮漂固定在抛竿落点，拖动不移动浮漂（Bug 描述 #5）。
      case PointerPhase.up:
      case PointerPhase.cancel:
        if (_state == _RodState.hooked) {
          final heldUs = _hookAtUs - _castStartUs;
          if (_hookIsPetal && now - _hookAtUs <= _catchWindowUs) {
            // 收杆成功：按稀有度概率抽花瓣入库（常见70%/稀有25%/奇珍5%）。
            final rarity = rollPetalRarity();
            _petalsCaught++;
            _waitTimesUs.add(heldUs);
            _caught.add(
              Reward(
                kind: RewardKind.petal,
                id: rarity.id,
                label: '花瓣（${rarity.label}）',
              ),
            );
            pond.catchHooked();
            _ctx.sounds.play(SoundCatalog.windChimeKey, gain: 0.5);
            _ctx.recorder.log('catch', {'petals': _petalsCaught});
            _restFrom(now);
          } else if (_hookIsPetal) {
            // 叮后超窗才松手（沉没轮询还没来得及判，三轮审查 P1）：
            // 复用轮询超时的沉没路径，保证"超时流失"不因计时器先后
            // 有时沉没有声、有时漂回无声。
            _missed++;
            _sinkAndRest(now);
          } else {
            // "咚"后收手 = 空竿：上钩的杂物就地脱钩恢复漂流
            //（二轮审查 P1：不发状态物件会永久卡在 hooked 态）。
            _miscatch++;
            _waitTimesUs.add(heldUs);
            pond.releaseHooked();
            _restFrom(now);
          }
        } else if (_state == _RodState.casting) {
          // 没等到触竿就收手：空竿。
          _restFrom(now);
        }
        // 收杆 = 浮漂离水。
        notifyVisualChanged();
    }
  }

  @override
  void onInterrupt(InterruptReason r) {}

  @override
  void onResume() {}

  @override
  Future<PracticeResult> finish(FinishReason r) async {
    _pollTimer?.cancel();
    if (_finished) return _buildResult(r);
    _finished = true;
    return _buildResult(r);
  }

  PracticeResult _buildResult(FinishReason r) {
    final elapsedUs = _ctx.scheduler.nowUs().clamp(0, 1 << 30);
    final avgWaitUs = _waitTimesUs.isEmpty
        ? 0
        : _waitTimesUs.fold<int>(0, (a, b) => a + b) ~/ _waitTimesUs.length;
    final miscatchRate = (_casts == 0) ? 0.0 : _miscatch / _casts;
    // quality 仅作展示（耐心曲线），修为不再由它驱动。
    final waitScore = (avgWaitUs / 20000000).clamp(0.2, 1.0);
    final quality = (waitScore * 0.7 + (1 - miscatchRate) * 0.3).clamp(
      0.1,
      1.0,
    );
    // 待对齐清单 #5：修为 = 钓到花瓣数 × 3（钓到的花瓣是真实所得，
    // 与结束方式无关）。
    final merit = _petalsCaught * _meritPerPetal;

    return PracticeResult(
      effectiveDuration: Duration(microseconds: elapsedUs),
      quality: quality,
      merit: merit,
      completed: r == FinishReason.completed || r == FinishReason.userEnded,
      metrics: {
        'casts': _casts,
        'petalsCaught': _petalsCaught,
        'miscatch': _miscatch,
        'missed': _missed,
        'avgWaitSec': avgWaitUs / 1000000,
        'antiIdle': r == FinishReason.antiIdle,
      },
      extraRewards: _caught,
    );
  }

  @override
  Widget buildVisual(BuildContext c) {
    final subtitle = switch (_state) {
      _RodState.idle => '长按抛竿 · 闭眼等候',
      _RodState.casting => '水面很静 · 再等一等',
      _RodState.hooked => _hookIsPetal ? '叮 · 松手收花' : '咚 · 此竿为空',
      _RodState.resting => '收心片刻 · 等水面复静',
    };
    return Stack(
      children: [
        Positioned.fill(
          child: PracticeScene(
            kind: PracticeSceneKind.fishPetals,
            title: '钓 花',
            subtitle: subtitle,
            active: _state == _RodState.hooked,
            count: _casts,
            accent: _petalsCaught > 0 || (_state == _RodState.hooked && _hookIsPetal)
                ? 1
                : 0,
            // 删除钓竿模型，只保留俯视浮漂层（新改进意见）。
            foreground: false,
          ),
        ),
        // 俯视池塘层：花瓣/杂物图片漂流、浮漂图片固定在落点、
        // 漂进判定半径才上钩。常驻以保留模拟状态。
        Positioned.fill(
          child: IgnorePointer(
            child: _PondLayer(
              model: pond,
              nowUs: () => _ctx.scheduler.nowUs(),
              holdSeconds: () => _holdSecondsAt(_ctx.scheduler.nowUs()),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget buildSummary(BuildContext c, PracticeResult r) {
    final m = r.metrics;
    final idle = m['antiIdle'] as bool? ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          idle ? '水面静了太久，先回去吧。' : '收竿。花瓣已收进图鉴。',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFE8DFC8), fontSize: 15),
        ),
        const SizedBox(height: 16),
        _Row(label: '投竿', value: '${m['casts']} 次'),
        _Row(label: '钓起花瓣', value: '${m['petalsCaught']} 片'),
        _Row(label: '"咚"空竿', value: '${m['miscatch']} 次'),
        _Row(label: '"叮"未接住', value: '${m['missed']} 次'),
        _Row(
          label: '平均等待',
          value: '${(m['avgWaitSec'] as num? ?? 0).toStringAsFixed(1)} 秒',
        ),
        if (_caught.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            children: [
              for (final reward in _caught)
                PetalBadge(
                  label: reward.label,
                  color: kGenericPetalColor,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0x88E8DFC8), fontSize: 13),
          ),
          Text(
            value,
            style: const TextStyle(color: Color(0xFFE8DFC8), fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class PetalBadge extends StatelessWidget {
  const PetalBadge({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}

/// 池塘里的一件漂浮物（花瓣 / 杂物）。
class PondItem {
  PondItem({required this.isPetal, required this.pos, required Random rng})
    : phase = rng.nextDouble() * 2 * pi,
      // 每个物体**自带一个独立随机源**，游走的方向与速度全部由它自己抽。
      // 绝不用模型级的共享变量，否则多个物体会整齐划一地同步漂移。
      rng = Random(rng.nextInt(1 << 31)),
      // 碰撞半径与质量（§5.4）：杂物更大更"重"。
      radius = isPetal ? 12.0 : 24.0,
      mass = isPetal ? 1.0 : 1.9;

  final bool isPetal;
  Offset pos;
  Offset vel = Offset.zero;
  double phase;

  /// 该物体自己的随机源（游走方向/速度）。
  final Random rng;

  /// 当前速率（标量）与行进方向——速率**连续变化**，方向只在速率为 0
  /// 时更换，避免单帧速度突变造成"一跳一跳"的卡顿。
  double speed = 0;
  Offset dir = const Offset(1, 0);

  /// 游走分段：0 起步加速 / 1 巡航 / 2 刹车 / 3 静止歇一下。
  /// 初值是"静止且计时已到"，第一帧就会开出一段新游走——否则初版
  /// cruiseSpeed=0 会让第一段巡航空转好几秒，物件杵在原地不动。
  int legPhase = 3;
  double legLeft = 0;
  double cruiseSpeed = 0;

  /// 是否还在惯性滑行（吃过击散/碰撞冲量，速率高于游走量级）。
  /// 为真时只吃阻力，等衰减回游走量级再交回分段循环。
  bool inertia = false;

  /// 碰撞半径 / 质量（§5.3 情况六）。
  final double radius;
  final double mass;

  bool hooked = false;
  bool leaving = false; // 被钓起：向浮漂收拢消失
  double leaveT = 0;
  bool sinking = false; // 未钓起：沉下水底
  double sinkT = 0;
}

/// 池塘模拟（会话所有，玩法与视觉共用）。
///
/// 玩法侧（FishPetalsSession）：
/// - 上钩判定：[hookNearestItem] 只返回漂进浮漂判定半径内的东西
///   （Bug 描述 #5：禁止远程钓）；
/// - 触竿/收取/沉没/脱钩由状态机在会话时间轴上直接改状态。
/// 视觉侧（_PondLayer）：逐帧 [step] 推进位移，只渲染不判定。
///
/// 行为：
/// - 未甩杆：花瓣与杂物缓慢漂流（同屏上限 2 瓣 + 2 杂）。
/// - 抛竿：浮漂落在手指处并固定；落水把附近漂浮物小范围惊散
///   （Bug 描述 #5：力度减小，不再打到屏幕边缘）。
/// - 之后漂浮物以更快的速度向浮漂靠拢（Bug 描述 #5：缩短等待）。
/// - 上钩者停在浮漂边打转；收取向浮漂收拢消失、沉没下沉消失、
///   脱钩就地恢复漂流；消失后 3–8 秒在边缘补齐名额。
class PondModel {
  PondModel({Random? rng}) : _rng = rng ?? Random(23);

  final Random _rng;
  final List<PondItem> items = [];
  final List<({Offset pos, double age})> ripples = [];
  final List<double> _spawnTimers = [];
  Size _size = Size.zero;
  Offset? _buoy;
  bool _buoyShown = false;
  bool _buoyWasShown = false;
  PondItem? _hooked;

  static const int _maxPetals = 2;
  static const int _maxClutter = 2;

  /// 浮漂判定半径：漂浮物自然漂进该范围才可能上钩（Bug 描述 #5）。
  static const double hookRadius = 36;

  /// Bug#5（第二轮 §5.3 情况四）：双层判定圈。
  /// 外圈"加速圈"——进入即把方向修正为面向浮漂；内圈"判定圈"——进入即上钩。
  static const double accelerateR = 118;
  static const double catchR = 30;

  /// §5.3 情况一：抛竿击散的作用半径（力度按距离衰减，沿用原参数）。
  static const double _scatterRadius = 170;

  /// §5.3 情况二：惯性滑行的阻力系数。
  static const double _drag = 1.8;

  /// §5.3 情况三：游走速率区间与各段时长。
  /// 起步/刹车都用线性斜坡，单帧速度变化 = 速率/斜坡时长/60 ≈ 1 px/s，
  /// 远低于肉眼可辨的阈值。
  static const double _wanderMin = 18;
  static const double _wanderMax = 40;
  static const double _legAccelSec = 0.8;
  static const double _legBrakeSec = 1.0;

  /// 加速圈内的最大转向角速度（弧度/秒）。6 rad/s 约 0.5 秒转 180°，
  /// 单帧速度变化 = 速率 × 6 × dt ≈ 4px/s，看不出折角。
  static const double _turnRate = 6.0;

  /// §5.3 情况三：朝浮漂的初始概率，以及涨到上限所需时间。
  static const double _biasMin = 0.18;
  static const double _biasMax = 0.85;
  static const int _biasRampUs = 45000000;

  /// §5.3 情况六：碰撞恢复系数（<1 表示非弹性，动能逐次损耗）。
  static const double _restitution = 0.72;

  /// 浮漂本次在水中的滞留时长（收杆/抛竿时重置）。
  double _castElapsedUs = 0;

  /// 本帧是否有物体刚进入判定圈（由会话轮询取走，走正常收杆流程）。
  PondItem? _pendingHook;

  Size get size => _size;

  Offset? get buoy => _buoy;
  bool get buoyShown => _buoyShown && _buoy != null;
  int get hookedCount => items.where((i) => i.hooked).length;
  int get terminalCount => items.where((i) => i.sinking || i.leaving).length;

  /// 视图层数据（测试断言用）。
  List<({Offset pos, Offset vel})> debugItems() =>
      items.map((i) => (pos: i.pos, vel: i.vel)).toList(growable: false);

  /// 视图给出可用尺寸；首帧播种漂浮物。
  void resize(Size s) {
    if (s == Size.zero || (s == _size && items.isNotEmpty)) return;
    _size = s;
    _refill();
  }

  Offset _randomPoint() => Offset(
    _rng.nextDouble() * (_size.width - 80) + 40,
    _rng.nextDouble() * (_size.height - 160) + 80,
  );

  int get _petalCount =>
      items.where((i) => i.isPetal && !i.leaving && !i.sinking).length;
  int get _clutterCount =>
      items.where((i) => !i.isPetal && !i.leaving && !i.sinking).length;

  void _refill() {
    if (_size == Size.zero) return;
    while (_petalCount < _maxPetals) {
      items.add(PondItem(isPetal: true, pos: _randomPoint(), rng: _rng));
    }
    while (_clutterCount < _maxClutter) {
      items.add(PondItem(isPetal: false, pos: _randomPoint(), rng: _rng));
    }
  }

  /// 会话通告浮漂位置与可见性。可见沿上升沿：涟漪 + 小范围惊散 +
  /// 上次空竿者的兜底脱钩（引用清空前先复位 hooked 标记）。
  void setBuoy(Offset pos, {required bool shown}) {
    _buoy = pos;
    _buoyShown = shown;
    final shownNow = buoyShown;
    if (shownNow && !_buoyWasShown) {
      // 每次抛竿重新计时：偏向浮漂的概率从初始值重新爬升。
      _castElapsedUs = 0;
      _pendingHook = null;
      for (var i = 0; i < 3; i++) {
        ripples.add((pos: pos, age: -i * 0.18));
      }
      scatter(pos);
      _hooked?.hooked = false;
      _hooked = null;
    }
    _buoyWasShown = shownNow;
  }

  /// 只更新可见性（浮漂位置固定，Bug 描述 #5）。
  ///
  /// 隐藏时必须同步复位落水上升沿标记：否则第一竿把它置为 true 之后，
  /// 第二次抛竿不再满足上升沿条件，击散与涟漪只在第一竿出现（P2）。
  void setBuoyShown(bool shown) {
    _buoyShown = shown;
    // §5.3 情况三：收杆时把"朝浮漂"的概率重置回均匀。
    if (!shown) {
      _buoyWasShown = false;
      _castElapsedUs = 0;
    }
  }

  /// 距浮漂最近的同类型漂浮物（可限判定半径）；没有则 null。
  PondItem? nearestOf(bool isPetal, {double? within}) {
    final c = _buoy;
    if (c == null) return null;
    PondItem? nearest;
    var best = double.infinity;
    for (final item in items) {
      if (item.isPetal != isPetal || item.sinking || item.leaving) continue;
      final d = (item.pos - c).distance;
      if (within != null && d > within) continue;
      if (d < best) {
        best = d;
        nearest = item;
      }
    }
    return nearest;
  }

  /// 上钩判定（玩法）：漂进浮漂判定半径内的漂浮物才可上钩。
  PondItem? hookNearestItem({required double within}) {
    final c = _buoy;
    if (c == null || !buoyShown) return null;
    PondItem? nearest;
    var best = double.infinity;
    for (final item in items) {
      if (item.sinking || item.leaving || item.hooked) continue;
      final d = (item.pos - c).distance;
      if (d <= within && d < best) {
        best = d;
        nearest = item;
      }
    }
    return nearest;
  }

  /// 绑定上钩者（视觉：停在浮漂边打转）。
  ///
  /// §5.3 情况五：他者上钩的瞬间，其余物体立刻获得"远离浮漂"的速度；
  /// 已经在加速圈内的，远离速度要大于靠近速度，才会真的被挤开而不是
  /// 继续朝浮漂挪。
  void hookItem(PondItem item) {
    _hooked = item..hooked = true;
    item.vel = Offset.zero;
    item.speed = 0;
    final c = _buoy;
    if (c == null) return;
    for (final other in items) {
      if (identical(other, item) || other.sinking || other.leaving) continue;
      final d = other.pos - c;
      final dist = d.distance;
      final dir = dist > 0.01 ? d / dist : const Offset(-1, 0);
      final near = dist <= accelerateR;
      final away = near ? _wanderMax * 2.4 : _wanderMax * 0.9;
      other.vel = dir * away;
      _applyImpulse(other);
    }
  }

  /// 测试钩子：无视距离门槛绑定指定类型的最近者。
  void forceHook({required bool petal}) {
    final item = nearestOf(petal);
    if (item != null) _hooked = item..hooked = true;
  }

  /// 收取：上钩者向浮漂收拢消失。
  void catchHooked() {
    if (_hooked != null && !_hooked!.sinking) {
      _hooked!
        ..hooked = false
        ..leaving = true;
      _scheduleRespawn();
    }
    _hooked = null;
  }

  /// 沉没：上钩者沉下水底消失。
  void sinkHooked() {
    if (_hooked != null && !_hooked!.sinking) {
      _hooked!
        ..hooked = false
        ..sinking = true;
      _scheduleRespawn();
    }
    _hooked = null;
  }

  /// 脱钩：空竿收杆，上钩者就地恢复漂流。
  void releaseHooked() {
    if (_hooked != null && !_hooked!.sinking && !_hooked!.leaving) {
      _hooked!.hooked = false;
    }
    _hooked = null;
  }

  void _scheduleRespawn() => _spawnTimers.add(3 + _rng.nextDouble() * 5);

  /// 抛竿惊散：只作用在浮漂周围 [_scatterRadius] 内、力度随距离衰减
  ///（Bug 描述 #5：力度减小，不再击飞到屏幕边缘）。
  void scatter(Offset center) {
    for (final item in items) {
      if (item.hooked || item.sinking || item.leaving) continue;
      final d = item.pos - center;
      final dist = d.distance;
      if (dist < 0.01 || dist > _scatterRadius) continue;
      final falloff = 1 - dist / _scatterRadius;
      item.vel += d / dist * 120 * falloff;
      _applyImpulse(item); // 击散是瞬时冲量，之后进入惯性滑行
    }
  }

  int? _lastAdvanceUs;

  /// 由**会话时间**推进模拟（P1：判定不得依赖界面动画）。
  ///
  /// 谁调用不重要——动画帧与会话轮询都调它，各自只消费"距上次推进的
  /// 会话时间差"，所以重复调用不会双倍推进。关闭动画/无障碍导航时绘制
  /// 帧停住，会话轮询仍照常把池塘推进下去，物件照常漂进判定半径。
  void advance(int nowUs, {required double holdSeconds}) {
    if (_size == Size.zero) return;
    final last = _lastAdvanceUs;
    _lastAdvanceUs = nowUs;
    if (last == null) return;
    // 单次最多推进 250ms：足够覆盖 100ms 的会话轮询，又能在回到前台后
    // 避免物件瞬移（下层以 1/120 子步积分保持稳定）。
    var remaining = ((nowUs - last) / 1e6).clamp(0.0, 0.25);
    while (remaining > 1e-9) {
      final dt = min(remaining, 1 / 120);
      step(dt, holdSeconds: holdSeconds);
      remaining -= dt;
    }
  }

  /// 逐帧推进（由 [advance] 调用；玩法判定不依赖谁在驱动它）。
  void step(double dt, {required double holdSeconds}) {
    if (_size == Size.zero) return;
    final center = _buoy;
    final buoyShown = this.buoyShown;

    // 刷新计时。
    for (var i = 0; i < _spawnTimers.length; i++) {
      _spawnTimers[i] -= dt;
    }
    for (final due in _spawnTimers.where((t) => t <= 0).toList()) {
      _spawnTimers.remove(due);
      _spawnAtEdge();
    }

    // 涟漪老化。
    for (var i = 0; i < ripples.length; i++) {
      ripples[i] = (pos: ripples[i].pos, age: ripples[i].age + dt);
    }
    ripples.removeWhere((r) => r.age > 1.3);

    // 东西运动（Bug#5 第二轮：改成速度/加速度模型，六种情况见 §5.3）。
    // 浮漂在水中的滞留时间：朝向浮漂的概率随它单调上升（情况三）。
    if (buoyShown) _castElapsedUs += dt * 1000000;
    final bias =
        (_biasMin + (_biasMax - _biasMin) * (_castElapsedUs / _biasRampUs))
            .clamp(_biasMin, _biasMax);

    for (final item in items) {
      if (item.sinking) {
        item.sinkT += dt / 1.1;
        item.pos += Offset(0, 14 * dt);
        continue;
      }
      if (item.leaving) {
        item.leaveT += dt / 0.5;
        if (center != null) {
          item.pos += (center - item.pos) * (dt * 6).clamp(0.0, 1.0);
        }
        continue;
      }
      if (item.hooked) {
        // 上钩者停在浮漂边轻微打转。
        item.phase += dt * 3;
        final d = item.pos - center!;
        final dist = d.distance;
        if (dist > 26) {
          item.pos += -d / dist * 30 * dt;
        } else {
          item.pos += Offset(cos(item.phase) * 3 * dt, sin(item.phase) * 3 * dt);
        }
        item.vel *= pow(0.9, dt * 60).toDouble();
        continue;
      }

      // 情况二/三：惯性滑行与游走分段（速率全程连续，见 _updateWander）。
      _updateWander(item, dt, center, buoyShown, bias);

      if (buoyShown && center != null) {
        final toBuoy = center - item.pos;
        final dist = toBuoy.distance;
        if (dist > 0.01) {
          // 情况四：进入外层加速圈 → 立即把方向修正为面向浮漂。
          // 情况四：进入加速圈后把方向转向浮漂。
          // 用**有上限的转向速率**而不是瞬间对齐——瞬间改向在 40px/s 下
          // 会造成约 20px/s 的单帧速度突变，看起来是一次折角。
          if (dist <= accelerateR && item.speed > 0) {
            item.dir = _turnToward(item.dir, toBuoy / dist, _turnRate * dt);
            item.vel = item.dir * item.speed;
          }
          // 情况四：进入内层判定圈 → 判定上钩、速度清零，交回会话收杆。
          if (dist <= catchR) {
            item.speed = 0;
            item.vel = Offset.zero;
            _pendingHook ??= item;
          }
        }
      }

      item.pos += item.vel * dt;
      // 情况六：碰屏幕边缘镜面反射。
      _bounceOffWalls(item);
    }
    // 情况六：物体之间的圆-圆碰撞（按质量交换动量）。
    _resolveItemCollisions();
    items.removeWhere((item) {
      final gone =
          (item.sinking && item.sinkT >= 1) ||
          (item.leaving && item.leaveT >= 1);
      return gone;
    });
  }

  /// 取走"刚进入判定圈"的物体（会话轮询用；取走即清空）。
  PondItem? takePendingHook() {
    final item = _pendingHook;
    _pendingHook = null;
    return item;
  }

  /// §5.3 情况二/三：惯性滑行 + "起步 → 巡航 → 刹车 → 静止 → 换向"。
  ///
  /// **关键约束：除真正的冲量（击散/碰撞/被挤开）外，速率必须连续变化。**
  /// 早期实现是在速率跌破阈值时直接把速度赋成新的随机值，实测单帧
  /// |Δv| 高达 60px/s——看起来就是"一跳一跳"的卡顿。方向也只在速率为 0
  /// 的静止段更换，换向因此不可见。
  void _updateWander(
    PondItem item,
    double dt,
    Offset? center,
    bool buoyShown,
    double bias,
  ) {
    if (item.inertia) {
      item.vel *= exp(-_drag * dt);
      item.speed = item.vel.distance;
      if (item.speed > 0.01) item.dir = item.vel / item.speed;
      if (item.speed <= _wanderMin) {
        // 不要在这里硬清零：接着走"刹车"斜坡，从**当前速率**平滑减到 0，
        // 再进静止段换向。否则击散/碰撞之后仍是"滑着滑着突然停一下"。
        item.inertia = false;
        item.cruiseSpeed = item.speed;
        item.legPhase = 2;
        item.legLeft = _legBrakeSec;
      }
      item.vel = item.dir * item.speed;
      return;
    }

    item.legLeft -= dt;
    switch (item.legPhase) {
      case 0: // 起步：速率 0 → 巡航值（线性斜坡）
        item.speed =
            item.cruiseSpeed * (1 - item.legLeft / _legAccelSec).clamp(0.0, 1.0);
        if (item.legLeft <= 0) {
          item.speed = item.cruiseSpeed;
          item.legPhase = 1;
          item.legLeft = 1.2 + item.rng.nextDouble() * 2.2;
        }
      case 1: // 巡航
        item.speed = item.cruiseSpeed;
        if (item.legLeft <= 0) {
          item.legPhase = 2;
          item.legLeft = _legBrakeSec;
        }
      case 2: // 刹车：巡航值 → 0
        item.speed =
            item.cruiseSpeed * (item.legLeft / _legBrakeSec).clamp(0.0, 1.0);
        if (item.legLeft <= 0) {
          item.speed = 0;
          item.legPhase = 3;
          item.legLeft = 0.35 + item.rng.nextDouble() * 0.8;
        }
      default: // 静止：速率为 0，此时换向不可见
        item.speed = 0;
        if (item.legLeft <= 0) _startLeg(item, center, buoyShown, bias);
    }
    item.vel = item.dir * item.speed;
  }

  /// 开一段新游走。方向与速率都用**该物件自己的随机源**抽：以 [bias] 的
  /// 概率朝浮漂（带角度抖动，不会直勾勾排队），否则纯随机方向。
  void _startLeg(PondItem item, Offset? center, bool buoyShown, double bias) {
    if (!buoyShown || center == null) {
      item.speed = 0;
      item.vel = Offset.zero;
      item.legPhase = 3;
      item.legLeft = 0.2;
      return;
    }
    final double angle;
    if (item.rng.nextDouble() < bias) {
      final base = atan2(center.dy - item.pos.dy, center.dx - item.pos.dx);
      angle = base + (item.rng.nextDouble() - 0.5) * 1.1;
    } else {
      angle = item.rng.nextDouble() * 2 * pi;
    }
    item.dir = Offset(cos(angle), sin(angle));
    item.cruiseSpeed =
        _wanderMin + item.rng.nextDouble() * (_wanderMax - _wanderMin);
    item.legPhase = 0;
    item.legLeft = _legAccelSec;
    item.speed = 0;
    item.vel = Offset.zero;
  }

  /// 把 [from] 这个单位方向朝 [to] 最多旋转 [maxRad] 弧度（有符号取近路）。
  Offset _turnToward(Offset from, Offset to, double maxRad) {
    final dot = (from.dx * to.dx + from.dy * to.dy).clamp(-1.0, 1.0);
    final cross = from.dx * to.dy - from.dy * to.dx;
    final angle = atan2(cross, dot);
    final step = angle.clamp(-maxRad, maxRad);
    final c = cos(step), sn = sin(step);
    return Offset(from.dx * c - from.dy * sn, from.dx * sn + from.dy * c);
  }

  /// 把外部冲量记到物件上：进入"惯性滑行"，只吃阻力衰减。
  void _applyImpulse(PondItem item) {
    item.speed = item.vel.distance;
    if (item.speed > 0.01) item.dir = item.vel / item.speed;
    item.inertia = true;
  }

  /// §5.3 情况六：碰屏幕边缘镜面反射（带恢复系数）。
  ///
  /// **必须同时改 [PondItem.dir]**：速度每步都由 `dir × speed` 重算，
  /// 只改 `vel` 的话下一步就被覆盖，物体会一直顶着墙（贴边抖动/停住）。
  void _bounceOffWalls(PondItem item) {
    const left = 16.0, right = 16.0, top = 50.0, bottom = 40.0;
    final w = _size.width, h = _size.height;
    var bounced = false;
    if (item.pos.dx < left) {
      item.pos = Offset(left, item.pos.dy);
      item.dir = Offset(item.dir.dx.abs(), item.dir.dy);
      bounced = true;
    } else if (item.pos.dx > w - right) {
      item.pos = Offset(w - right, item.pos.dy);
      item.dir = Offset(-item.dir.dx.abs(), item.dir.dy);
      bounced = true;
    }
    if (item.pos.dy < top) {
      item.pos = Offset(item.pos.dx, top);
      item.dir = Offset(item.dir.dx, item.dir.dy.abs());
      bounced = true;
    } else if (item.pos.dy > h - bottom) {
      item.pos = Offset(item.pos.dx, h - bottom);
      item.dir = Offset(item.dir.dx, -item.dir.dy.abs());
      bounced = true;
    }
    if (!bounced) return;
    // 速率按恢复系数损耗，并把 vel 同步成 dir × speed（统一状态）。
    item.speed *= _restitution;
    item.vel = item.dir * item.speed;
  }

  /// §5.3 情况六：物体之间的圆-圆碰撞。
  ///
  /// 先按质量反比分开重叠，再沿法线做一维碰撞：冲量由相对速度与质量决定，
  /// 恢复系数 <1，动量守恒、动能逐次损耗。
  void _resolveItemCollisions() {
    for (var i = 0; i < items.length; i++) {
      for (var j = i + 1; j < items.length; j++) {
        final a = items[i], b = items[j];
        if (a.sinking || b.sinking || a.leaving || b.leaving) continue;
        final d = b.pos - a.pos;
        final dist = d.distance;
        final minDist = a.radius + b.radius;
        if (dist >= minDist || dist < 0.001) continue;
        final dir = d / dist;
        final total = a.mass + b.mass;
        final overlap = minDist - dist;
        a.pos = a.pos - dir * (overlap * b.mass / total);
        b.pos = b.pos + dir * (overlap * a.mass / total);

        final rel = (b.vel - a.vel).dx * dir.dx + (b.vel - a.vel).dy * dir.dy;
        if (rel > 0) continue; // 已经在分离
        final impulse = -(1 + _restitution) * rel / (1 / a.mass + 1 / b.mass);
        a.vel = a.vel - dir * (impulse / a.mass);
        b.vel = b.vel + dir * (impulse / b.mass);
        _applyImpulse(a);
        _applyImpulse(b);
      }
    }
  }

  void _spawnAtEdge() {
    final isPetal = _petalCount <= _clutterCount;
    if (isPetal && _petalCount >= _maxPetals) return;
    if (!isPetal && _clutterCount >= _maxClutter) return;
    final s = _size;
    final side = _rng.nextInt(4);
    final t = _rng.nextDouble();
    final pos = switch (side) {
      0 => Offset(t * s.width, 70),
      1 => Offset(t * s.width, s.height - 60),
      2 => Offset(36, t * s.height),
      _ => Offset(s.width - 36, t * s.height),
    };
    items.add(PondItem(isPetal: isPetal, pos: pos, rng: _rng));
  }

  /// 补齐漂浮物名额（静帧模式移除终端物件后立即调用）。
  void refill() => _refill();

  void clearSpawnTimers() => _spawnTimers.clear();

  /// 测试钩子：固定位置播种漂浮物（绕过随机布点）。
  void debugAddItem({required bool petal, required Offset pos}) {
    items.add(PondItem(isPetal: petal, pos: pos, rng: _rng));
  }

  /// 测试钩子：清空全部漂浮物。
  void debugClear() => items.clear();
}

/// 俯视池塘层：渲染 [PondModel]（花瓣/杂物/浮漂用正式图片素材，
/// Bug 描述 #5），逐帧推进模拟；自身不做任何玩法判定。
class _PondLayer extends StatefulWidget {
  const _PondLayer({
    required this.model,
    required this.nowUs,
    required this.holdSeconds,
  });

  final PondModel model;

  /// 会话时间源（与判定同一条时钟，避免画面与判定用两个时基）。
  final int Function() nowUs;
  final double Function() holdSeconds;

  @override
  State<_PondLayer> createState() => _PondLayerState();
}

class _PondLayerState extends State<_PondLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _frame;
  bool _reduceMotion = false;

  PondModel get _model => widget.model;

  @override
  void initState() {
    super.initState();
    _frame = AnimationController(
      vsync: this,
      duration: const Duration(days: 365),
    )..addListener(_onFrame);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.maybeOf(context);
    final reduceMotion = (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);
    _model.resize(media?.size ?? Size.zero);
    if (reduceMotion != _reduceMotion || !_frame.isAnimating) {
      _reduceMotion = reduceMotion;
      if (_reduceMotion) {
        _frame.stop();
        _model.ripples.clear();
        // 静帧模式下模型仍由会话轮询推进（判定不能停），但画面若不重绘
        // 就会"过期"：会话只在**状态变化**时递增 visualRevision，所以两次
        // 判定之间没有任何重建——屏幕停在最后一帧、模型继续在走，下一次
        // 判定（叮/咚、回到待机）重建时画面直接跳到新位置。录屏里 2.5s 的
        // 空竿判定、4.25s 的回待机两次跳变正好落在这类事件上，中间 5~9s
        // 的"冻住"就是事件之间的空档。这里按低频自行刷新让画面始终跟得上，
        // 刷新率仍从 60fps 降到 ~8fps，符合"减少动态"。
        _staticRefresh ??= Timer.periodic(_staticRefreshPeriod, (_) {
          if (!mounted) return;
          _staticRefreshes++;
          setState(() {});
        });
      } else {
        _staticRefresh?.cancel();
        _staticRefresh = null;
        _frame.repeat();
      }
    }
  }

  /// 静帧刷新周期：约 8fps。
  ///
  /// 目的不是"让画面动起来"，而是让画面**不过期**：模型由会话轮询持续推进，
  /// 只要刷新率跟得上，画面上物件的位置就与模型一致（巡航速率 ~40px/s 时
  /// 每帧位移约 5px，看不出跳变；击散后的惯性冲刺会短暂更大，但仍是连续
  /// 轨迹，而不是"冻住几秒再瞬移"）。同时它远低于逐帧渲染的开销，
  /// 符合"减少动态"的本意。
  static const Duration _staticRefreshPeriod = Duration(milliseconds: 120);

  Timer? _staticRefresh;

  /// 静帧模式下的自刷新次数（回归观察点：画面不能"过期"）。
  @visibleForTesting
  int get debugStaticRefreshes => _staticRefreshes;
  int _staticRefreshes = 0;

  void _onFrame() {
    if (_reduceMotion) return;
    // 逐帧推进只负责画面流畅；推进量的所有权在 PondModel.advance，
    // 关闭动画时由会话轮询继续推进，判定不依赖绘制帧。
    setState(() {
      _model.advance(widget.nowUs(), holdSeconds: widget.holdSeconds());
    });
  }

  @override
  Widget build(BuildContext context) {
    _model.resize(MediaQuery.maybeOf(context)?.size ?? Size.zero);
    if (_reduceMotion) {
      // 无动画/无障碍导航：跳过逐帧运动；状态（上钩/收取/沉没/脱钩）
      // 已由会话直接改在模型上。静帧没有"下沉/收拢"过程：直接移除
      // 终端物件并即时补齐名额，避免残影永留。
      _model.items.removeWhere((i) => i.sinking || i.leaving);
      _model.clearSpawnTimers();
      _model.refill();
      return _buildPond();
    }
    return _buildPond();
  }

  Widget _buildPond() {
    final model = _model;
    return Stack(
      children: [
        // 涟漪层（抛竿落水的几圈虚化水纹）。
        Positioned.fill(
          child: CustomPaint(
            painter: _RippleFieldPainter(ripples: List.of(model.ripples)),
          ),
        ),
        // 花瓣 / 杂物图片层。
        for (final item in model.items)
          Positioned(
            left: item.pos.dx - 13,
            top: item.pos.dy - 13,
            child: Opacity(
              opacity: itemFade(item),
              child: Image.asset(
                item.isPetal
                    ? 'assets/art/fish_petals/petal.png'
                    : 'assets/art/fish_petals/clutter.png',
                // §5.5：杂物显示尺寸放大到两倍，花瓣不变。
                width: item.isPetal ? 26 : 52,
                height: item.isPetal ? 26 : 52,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => SizedBox(
                  width: item.isPetal ? 26 : 52,
                  height: item.isPetal ? 26 : 52,
                ),
              ),
            ),
          ),
        // 浮漂图片：固定在抛竿落点（Bug 描述 #5）。
        if (model.buoyShown)
          Positioned(
            left: model.buoy!.dx - 19,
            top: model.buoy!.dy - 19,
            child: Image.asset(
              'assets/art/fish_petals/bobber.png',
              width: 38,
              height: 38,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const SizedBox(width: 38, height: 38),
            ),
          ),
      ],
    );
  }

  static double itemFade(PondItem item) {
    final fade = item.sinking ? (1 - item.sinkT).clamp(0.0, 1.0) : 1.0;
    final leaveFade = item.leaving
        ? (1 - item.leaveT).clamp(0.0, 1.0)
        : 1.0;
    return (fade * leaveFade).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _staticRefresh?.cancel();
    _frame.dispose();
    super.dispose();
  }

  @visibleForTesting
  bool get debugIsAnimating => _frame.isAnimating;

  /// 透出会话所有的池塘模型（宿主级测试断言用）。
  @visibleForTesting
  PondModel get debugPond => _model;
}

/// 涟漪：抛竿落水时几圈逐渐虚化的水纹。
class _RippleFieldPainter extends CustomPainter {
  _RippleFieldPainter({required this.ripples});

  final List<({Offset pos, double age})> ripples;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    for (final r in ripples) {
      if (r.age < 0) continue;
      final t = (r.age / 1.2).clamp(0.0, 1.0);
      final paint = ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1.6 * (1 - t)
        ..color = ui.Color.lerp(
          const ui.Color(0x77E8DFC8),
          const ui.Color(0x00E8DFC8),
          t,
        )!;
      canvas.drawCircle(r.pos, 8 + 46 * t, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RippleFieldPainter old) => true;
}
