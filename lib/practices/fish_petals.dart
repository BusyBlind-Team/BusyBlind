import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../core/audio/input_capture.dart';
import '../core/audio/sound_catalog.dart';
import '../core/practice/practice_manifest.dart';
import '../core/practice/practice_result.dart';
import '../core/practice/practice_session.dart';
import '../core/practice/practice_types.dart';
import '../domain/petals.dart';
import '../widgets/practice_scene.dart';

/// 钓花（耐心 · 收集）——听觉化改造版（设计方案 7.4）+ 浮标视觉（待对齐 #7）。
///
/// 玩法循环：长按甩杆 → 聚瓣期（触竿概率随本次甩杆时长上升：
/// 前 2 秒为 0，10 秒约 20% → 60 秒约 60%）→ 触竿响"叮"（花瓣，65%）
/// 或"咚"（杂物，35%）→ "叮"后 1.5 秒内松手收杆；"咚"后松手为空竿
/// → 松手后 2 秒休竿期。
/// 反挂机：连续 90 秒无有效输入自动进入结算。
/// 花瓣经 extraRewards 返还宿主入库；核心判定全走听觉，
/// 画面只是睁眼奖励层。
///
/// 浮标视觉（待对齐清单 #7）：长按后浮标落在手指处（略微放大、点起涟漪）；
/// 附近花瓣按距离远近不同程度散开，再慢慢随机向浮标靠近；
/// 按住拖动（移动浮标）也会使花瓣散开。花瓣聚散只是氛围层，
/// 不参与叮/咚判定。
/// 钓竿状态机：idle → casting（按住）→ hooked（已触发叮/咚）→ 休竿 → casting…
enum _RodState { idle, casting, hooked, resting }

class FishPetalsSession extends PracticeSession {
  static const int _noBiteBeforeUs = 2000000; // 前 2 秒概率为 0
  static const int _restUs = 2000000; // 休竿期
  static const int _catchWindowUs = 1500000; // "叮"后收杆窗口
  static const int _hookTimeoutUs = 4000000; // 触竿后最长握竿时长，超时自动休整
  static const int _antiIdleUs = 90000000; // 90 秒无输入自动结算
  static const double _petalChance = 0.65;

  /// 钓到各稀有度花瓣的概率（新改进意见）：常见 70% / 稀有 25% / 奇珍 5%。
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
  final Random _rng = Random();

  _RodState _state = _RodState.idle;
  int _castStartUs = 0;
  int _hookAtUs = 0;
  bool _hookIsPetal = false;
  int _restEndUs = 0;
  int? _lastInputUs;
  Timer? _pollTimer;

  // 视觉层事件脉冲：上钩一次 +1 / 收瓣成功一次 +1 / 沉底一次 +1
  // （俯视池塘层据此绑定状态；复审 R3：沉没事件由状态机发出，
  // 声效不再依赖视觉动画是否在绘制）。
  int _hookPulse = 0;
  int _catchPulse = 0;
  int _sinkPulse = 0;

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
        '长按屏幕，把浮标落在手指处，闭眼等。\n刚投下会惊散花瓣——前两秒不会有人上钩；\n甩得越久，花瓣越愿意靠近。\n'
        '"叮"是花瓣碰竿，1.5 秒内松手收杆；"咚"只是杂物，收了也是空竿。',
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
        // 100ms 轮询，事件概率 = 每秒概率 × 0.1。
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
    notifyVisualChanged();
  }

  /// 上钩的东西到点沉底（复审 R3）：沉没声与视觉脉冲都由会话状态机在
  /// 会话时间轴上发出——不依赖绘制帧率，关闭动画/无障碍模式下时机一致。
  void _sinkAndRest(int now) {
    _sinkPulse++;
    _ctx.sounds.play(SoundCatalog.fishSinkKey, gain: 0.9);
    _ctx.recorder.log('sink', {'petal': _hookIsPetal});
    _restFrom(now);
  }

  void _hook(int now) {
    _hookAtUs = now;
    _hookIsPetal = _rng.nextDouble() < _petalChance;
    _hookPulse++;
    _ctx.sounds.play(_hookIsPetal ? SoundCatalog.fishDingKey : SoundCatalog.fishDongKey, gain: 0.9);
    _ctx.recorder.log('hook', {
      'petal': _hookIsPetal,
      'waitMs': (now - _castStartUs) ~/ 1000,
    });
    _state = _RodState.hooked;
    notifyVisualChanged();
  }

  // ---- 测试钩子：绕过随机触发，直接把状态机推到触竿态 ----
  @visibleForTesting
  void debugForceHook({required bool petal}) {
    final now = _ctx.scheduler.nowUs();
    _castStartUs = now;
    _hookAtUs = now;
    _hookIsPetal = petal;
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

  @override
  void onInput(InputEvent e) {
    if (_finished) return;
    if (e.phase != PointerPhase.move) {
      _lastInputUs = e.sessionUs;
    }
    final now = e.sessionUs;

    switch (e.phase) {
      case PointerPhase.down:
        if (_state == _RodState.idle ||
            (_state == _RodState.resting && now >= _restEndUs)) {
          // 甩杆：浮漂落在屏幕正中（改进列表 #17，俯视视觉）。
          _state = _RodState.casting;
          _castStartUs = now;
          _casts++;
          _ctx.sounds.play(SoundCatalog.swishKey, gain: 0.6);
          _ctx.recorder.log('cast', {'at': now});
          notifyVisualChanged();
        }
      case PointerPhase.move:
        break; // 浮漂固定在屏幕正中，拖动不移动浮漂。
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
            _catchPulse++;
            _ctx.sounds.play(SoundCatalog.windChimeKey, gain: 0.5);
            _ctx.recorder.log('catch', {'petals': _petalsCaught});
          } else if (!_hookIsPetal) {
            _miscatch++;
            _waitTimesUs.add(heldUs);
          }
          _restFrom(now);
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
        // 俯视池塘层（改进列表 #17）：花瓣/杂物漂流、浮漂落正中惊散、
        // 随甩杆时长缓慢聚拢、上钩绑定与沉底刷新。常驻以保留状态。
        Positioned.fill(
          child: IgnorePointer(
            child: _PondLayer(
              showBuoy: _state == _RodState.casting || _state == _RodState.hooked,
              hookPulse: _hookPulse,
              hookIsPetal: _hookIsPetal,
              catchPulse: _catchPulse,
              sinkPulse: _sinkPulse,
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


/// 俯视池塘层（纯视觉，不参与叮/咚判定）——改进列表 #17。
///
/// - 未甩杆：只有缓慢漂流的花瓣与杂物（同屏上限 2 瓣 + 2 杂）。
/// - 长按甩杆：浮漂在屏幕正中落下（仅仅是浮漂），点起几圈逐渐虚化的
///   涟漪；浮漂落下时击散附近所有东西。
/// - 之后随甩杆时间延长，东西在一定距离随机游走，并逐渐有靠近浮漂的
///   趋势；每样东西速度不同，避免一起抵达。
/// - 一个东西上钩（叮/咚脉冲）：其他东西缓慢远离浮漂、在附近游走；
///   到点未钓起时状态机发沉没脉冲，上钩者沉下水底消失。
/// - 有东西消失后，等 3–8 秒在屏幕边缘刷新一个（不超过上限）。
class _PondItem {
  _PondItem({required this.isPetal, required this.pos})
    : phase = _pondRng.nextDouble() * 2 * pi,
      speed = 0.55 + _pondRng.nextDouble() * 0.8;

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

final Random _pondRng = Random(23);

class _PondLayer extends StatefulWidget {
  const _PondLayer({
    required this.showBuoy,
    required this.hookPulse,
    required this.hookIsPetal,
    required this.catchPulse,
    required this.sinkPulse,
    required this.holdSeconds,
  });

  final bool showBuoy;
  final int hookPulse;
  final bool hookIsPetal;
  final int catchPulse;
  final int sinkPulse;
  final double Function() holdSeconds;

  @override
  State<_PondLayer> createState() => _PondLayerState();
}

class _PondLayerState extends State<_PondLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _frame;
  final List<_PondItem> _items = [];
  final List<({Offset pos, double age})> _ripples = [];
  final List<double> _spawnTimers = [];
  Offset? _center;
  Size _size = Size.zero;

  bool _buoyWasShown = false;
  int _hookSeen = 0;
  int _catchSeen = 0;
  int _sinkSeen = 0;
  _PondItem? _hooked;
  bool _reduceMotion = false;

  static const int _maxPetals = 2;
  static const int _maxClutter = 2;
  static const double _scatterRadius = 180;

  @override
  void initState() {
    super.initState();
    _frame = AnimationController(
      vsync: this,
      duration: const Duration(days: 365),
    )..repeat();
  }

  void _ensureSeeded() {
    final media = MediaQuery.maybeOf(context);
    _reduceMotion =
        (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);
    final s = media?.size ?? Size.zero;
    if (s == Size.zero || s == _size && _items.isNotEmpty) return;
    _size = s;
    _center ??= Offset(s.width / 2, s.height / 2);
    if (_items.isNotEmpty) return;
    for (var i = 0; i < _maxPetals; i++) {
      _items.add(_PondItem(isPetal: true, pos: _randomPoint(s)));
    }
    for (var i = 0; i < _maxClutter; i++) {
      _items.add(_PondItem(isPetal: false, pos: _randomPoint(s)));
    }
  }

  Offset _randomPoint(Size s) => Offset(
    _pondRng.nextDouble() * (s.width - 80) + 40,
    _pondRng.nextDouble() * (s.height - 160) + 80,
  );

  int get _petalCount =>
      _items.where((i) => i.isPetal && !i.leaving && !i.sinking).length;
  int get _clutterCount =>
      _items.where((i) => !i.isPetal && !i.leaving && !i.sinking).length;

  void _scheduleRespawn() => _spawnTimers.add(3 + _pondRng.nextDouble() * 5);

  void _spawnAtEdge() {
    final isPetal = _petalCount <= _clutterCount;
    if (isPetal && _petalCount >= _maxPetals) return;
    if (!isPetal && _clutterCount >= _maxClutter) return;
    final s = _size;
    final side = _pondRng.nextInt(4);
    final t = _pondRng.nextDouble();
    final pos = switch (side) {
      0 => Offset(t * s.width, 70),
      1 => Offset(t * s.width, s.height - 60),
      2 => Offset(36, t * s.height),
      _ => Offset(s.width - 36, t * s.height),
    };
    _items.add(_PondItem(isPetal: isPetal, pos: pos));
  }

  void _scatterFrom(Offset center, double strength) {
    for (final item in _items) {
      if (item.hooked || item.sinking || item.leaving) continue;
      final d = item.pos - center;
      final dist = d.distance;
      if (dist < _scatterRadius && dist > 0.01) {
        final falloff = 1 - dist / _scatterRadius;
        item.vel += d / dist * falloff * 300 * strength;
      }
    }
  }

  void _step(double dt) {
    if (_size == Size.zero) return;
    final center = _center!;
    final buoyShown = widget.showBuoy;

    // 浮漂落水：涟漪 + 击散附近所有东西。
    if (buoyShown && !_buoyWasShown) {
      for (var i = 0; i < 3; i++) {
        _ripples.add((pos: center, age: -i * 0.18));
      }
      _scatterFrom(center, 1.0);
      _hooked = null;
    }
    _buoyWasShown = buoyShown;

    // 上钩脉冲：把最靠近浮漂的同类型东西绑为上钩者；其余缓慢远离。
    if (widget.hookPulse != _hookSeen) {
      _hookSeen = widget.hookPulse;
      _PondItem? nearest;
      var best = double.infinity;
      for (final item in _items) {
        if (item.isPetal != widget.hookIsPetal ||
            item.sinking ||
            item.leaving) {
          continue;
        }
        final d = (item.pos - center).distance;
        if (d < best) {
          best = d;
          nearest = item;
        }
      }
      if (nearest != null) {
        _hooked = nearest..hooked = true;
        for (final item in _items) {
          if (item == nearest || item.sinking || item.leaving) continue;
          final d = item.pos - center;
          final dist = d.distance;
          if (dist > 0.01) item.vel += d / dist * 22;
        }
      }
    }

    // 收瓣脉冲：上钩者被钓起，向浮漂收拢消失。
    if (widget.catchPulse != _catchSeen) {
      _catchSeen = widget.catchPulse;
      if (_hooked != null && !_hooked!.sinking) {
        _hooked!
          ..hooked = false
          ..leaving = true;
        _scheduleRespawn();
      }
      _hooked = null;
    }

    // 沉没脉冲（复审 R3）：状态机到点发来，上钩者沉底消失。
    // 视觉层只消费状态，沉没时机不随帧率/动画开关漂移。
    if (widget.sinkPulse != _sinkSeen) {
      _sinkSeen = widget.sinkPulse;
      if (_hooked != null && !_hooked!.sinking) {
        _hooked!
          ..hooked = false
          ..sinking = true;
        _scheduleRespawn();
      }
      _hooked = null;
    }

    // 刷新计时。
    for (var i = 0; i < _spawnTimers.length; i++) {
      _spawnTimers[i] -= dt;
    }
    for (final due in _spawnTimers.where((t) => t <= 0).toList()) {
      _spawnTimers.remove(due);
      _spawnAtEdge();
    }

    // 涟漪老化。
    for (var i = 0; i < _ripples.length; i++) {
      _ripples[i] = (pos: _ripples[i].pos, age: _ripples[i].age + dt);
    }
    _ripples.removeWhere((r) => r.age > 1.3);

    // 东西运动。
    final hold = widget.holdSeconds().clamp(0.0, 90.0);
    final pull = 16.0 * (hold / 45).clamp(0.05, 1.0); // 聚拢趋势随甩杆时长上升
    for (final item in _items) {
      if (item.sinking) {
        item.sinkT += dt / 1.1;
        item.pos += Offset(0, 14 * dt);
        continue;
      }
      if (item.leaving) {
        item.leaveT += dt / 0.5;
        item.pos += (center - item.pos) * (dt * 6).clamp(0.0, 1.0);
        continue;
      }
      if (item.hooked) {
        // 上钩者停在浮漂边轻微打转。
        item.phase += dt * 3;
        final d = item.pos - center;
        final dist = d.distance;
        if (dist > 26) {
          item.pos += -d / dist * 30 * dt;
        } else {
          item.pos += Offset(cos(item.phase) * 3 * dt, sin(item.phase) * 3 * dt);
        }
        item.vel *= 0.9;
        continue;
      }

      item.phase += dt * 0.5;
      // 随机游走。
      item.vel += Offset(
        cos(item.phase * 1.7) * 9 * dt,
        sin(item.phase * 1.3) * 9 * dt,
      );
      if (buoyShown) {
        final toBuoy = center - item.pos;
        final dist = toBuoy.distance;
        final dir = dist > 0.01 ? toBuoy / dist : Offset.zero;
        if (_hooked != null && item != _hooked) {
          // 有东西上钩：其他东西很缓慢地远离浮漂、在附近游走。
          item.vel += -dir * 6 * dt;
        } else if (dist > 60 && dist < 320) {
          // 逐渐靠近浮漂的趋势（各自速度不同，避免一起抵达）。
          item.vel += dir * pull * item.speed * dt;
        }
      }
      item.vel *= pow(0.5, dt).toDouble();
      item.pos += item.vel * dt;
      item.pos = Offset(
        item.pos.dx.clamp(16, _size.width - 16),
        item.pos.dy.clamp(50, _size.height - 40),
      );
    }
    _items.removeWhere((item) {
      final gone =
          (item.sinking && item.sinkT >= 1) ||
          (item.leaving && item.leaveT >= 1);
      return gone;
    });
  }

  @override
  Widget build(BuildContext context) {
    _ensureSeeded();
    if (_items.isEmpty && _size != Size.zero) {
      _ensureSeeded();
    }
    if (_reduceMotion) {
      return CustomPaint(
        painter: _PondPainter(
          items: _items,
          ripples: const [],
          showBuoy: widget.showBuoy,
          center: _center ?? Offset.zero,
        ),
      );
    }
    return AnimatedBuilder(
      animation: _frame,
      builder: (context, _) {
        _step(1 / 60);
        return CustomPaint(
          painter: _PondPainter(
            items: _items,
            ripples: _ripples,
            showBuoy: widget.showBuoy,
            center: _center ?? Offset.zero,
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _frame.dispose();
    super.dispose();
  }
}

class _PondPainter extends CustomPainter {
  _PondPainter({
    required this.items,
    required this.ripples,
    required this.showBuoy,
    required this.center,
  });

  final List<_PondItem> items;
  final List<({Offset pos, double age})> ripples;
  final bool showBuoy;
  final Offset center;

  @override
  void paint(Canvas canvas, Size size) {
    // 花瓣 / 杂物（俯视）。
    for (final item in items) {
      final fade = item.sinking ? (1 - item.sinkT).clamp(0.0, 1.0) : 1.0;
      final leaveFade = item.leaving
          ? (1 - item.leaveT).clamp(0.0, 1.0)
          : 1.0;
      final alpha = (fade * leaveFade).clamp(0.0, 1.0);
      if (item.isPetal) {
        final paint = Paint()
          ..color = const Color(0xCCF2C9CE).withValues(alpha: 0.8 * alpha);
        canvas.drawCircle(item.pos, 6, paint);
        canvas.drawCircle(
          item.pos,
          2.4,
          Paint()..color = const Color(0x55B08A8E).withValues(alpha: alpha),
        );
      } else {
        // 杂物：小枯枝。
        final twig = Paint()
          ..color = const Color(0x99635540).withValues(alpha: alpha)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          item.pos - const Offset(6, -4),
          item.pos + const Offset(7, 5),
          twig,
        );
      }
    }

    // 涟漪：几圈逐渐虚化。
    for (final r in ripples) {
      if (r.age < 0) continue;
      final t = (r.age / 1.2).clamp(0.0, 1.0);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * (1 - t)
        ..color = Color.lerp(
          const Color(0x77E8DFC8),
          const Color(0x00E8DFC8),
          t,
        )!;
      canvas.drawCircle(r.pos, 8 + 46 * t, paint);
    }

    // 浮漂（屏幕正中）。
    if (showBuoy) {
      canvas.drawCircle(center, 10, Paint()..color = const Color(0xFFB0473E));
      canvas.drawCircle(
        center,
        5.5,
        Paint()..color = const Color(0xFFEFE3C2),
      );
      canvas.drawCircle(
        center,
        13,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x33E8DFC8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PondPainter old) => true;
}
