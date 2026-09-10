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

  void _poll() {
    if (_finished || !_ctx.scheduler.isRunning) return;
    final now = _ctx.scheduler.nowUs();

    // 反挂机：连续 90 秒无有效输入。
    final last = _lastInputUs ?? 0;
    if (now - last >= _antiIdleUs) {
      _ctx.requestFinish(FinishReason.antiIdle);
      return;
    }

    switch (_state) {
      case _RodState.casting:
        final heldUs = now - _castStartUs;
        final rate = biteRatePerSecond(heldUs);
        // 100ms 轮询，事件概率 = 每秒概率 × 0.1。概率命中后还要求
        // 有花瓣/杂物自然漂进浮漂判定半径（Bug 描述 #5：禁止远程钓）。
        if (_rng.nextDouble() < rate * 0.1) {
          _hook(now);
        }
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

  void _hook(int now) {
    // 上钩判定：漂进浮漂判定半径的那个东西才上钩，类型由它自己决定。
    final item = pond.hookNearestItem(within: PondModel.hookRadius);
    if (item == null) return;
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
              holdSeconds: () {
                if (_state != _RodState.casting) return 0.0;
                return (_ctx.scheduler.nowUs() - _castStartUs) / 1e6;
              },
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
      speed = 0.55 + rng.nextDouble() * 0.8;

  final bool isPetal;
  Offset pos;
  Offset vel = Offset.zero;
  double phase;
  double speed;
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

  /// 抛竿击散的作用半径（Bug 描述 #5：只小范围散开）。
  static const double _scatterRadius = 170;

  Size get size => _size;

  /// 屏幕对角线：屏内两点距离的上界（吸引衰减归一基准）。
  double get _diagonal => Offset(_size.width, _size.height).distance;
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
  void setBuoyShown(bool shown) => _buoyShown = shown;

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
  void hookItem(PondItem item) {
    _hooked = item..hooked = true;
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
    }
  }

  /// 逐帧推进（视觉层调用；玩法判定不依赖它）。
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

    // 东西运动。
    // 靠拢速度整体加快（Bug 描述 #5：缩短击散后的回漂等待）。
    final pull = 44.0 + 26.0 * (holdSeconds / 45).clamp(0.0, 1.0);
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

      item.phase += dt * 0.5;
      // 随机游走。
      item.vel += Offset(
        cos(item.phase * 1.7) * 9 * dt,
        sin(item.phase * 1.3) * 9 * dt,
      );
      if (buoyShown) {
        // buoyShown 蕴含 center != null。
        final toBuoy = center! - item.pos;
        final dist = toBuoy.distance;
        // 有东西上钩时其余东西暂停靠拢倾向（二轮审查 P1：不主动推远）。
        if (_hooked == null && dist > 24) {
          final dir = dist > 0.01 ? toBuoy / dist : Offset.zero;
          final falloff = (1 - dist / _diagonal).clamp(0.35, 1.0);
          item.vel += dir * pull * item.speed * falloff * dt;
        }
      }
      item.vel *= pow(0.5, dt).toDouble();
      item.pos += item.vel * dt;
      item.pos = Offset(
        item.pos.dx.clamp(16, _size.width - 16),
        item.pos.dy.clamp(50, _size.height - 40),
      );
    }
    items.removeWhere((item) {
      final gone =
          (item.sinking && item.sinkT >= 1) ||
          (item.leaving && item.leaveT >= 1);
      return gone;
    });
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
  const _PondLayer({required this.model, required this.holdSeconds});

  final PondModel model;
  final double Function() holdSeconds;

  @override
  State<_PondLayer> createState() => _PondLayerState();
}

class _PondLayerState extends State<_PondLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _frame;
  Duration? _lastFrameTime;
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
      _lastFrameTime = null;
      if (_reduceMotion) {
        _frame.stop();
        _model.ripples.clear();
        for (final item in _model.items) {
          item.vel = Offset.zero;
        }
      } else {
        _frame.repeat();
      }
    }
  }

  void _onFrame() {
    final now = _frame.lastElapsedDuration;
    if (_reduceMotion || now == null) return;
    final previous = _lastFrameTime;
    _lastFrameTime = now;
    if (previous == null) return;
    // 长帧最多推进 50ms，避免恢复前台时物件瞬移；小步积分保持惯性稳定。
    var remaining = ((now - previous).inMicroseconds / 1e6).clamp(0.0, 0.05);
    if (remaining == 0) return;
    setState(() {
      while (remaining > 1e-9) {
        final dt = min(remaining, 1 / 120);
        _model.step(dt, holdSeconds: widget.holdSeconds());
        remaining -= dt;
      }
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
                width: 26,
                height: 26,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    const SizedBox(width: 26, height: 26),
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
