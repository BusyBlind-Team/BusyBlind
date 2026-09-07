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

  // 浮标位置（宿主坐标系的逻辑坐标；null = 未投）。
  Offset? _buoyPos;
  int _catchPulse = 0; // 成功收瓣的视觉脉冲计数

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
    eyeMode: EyeMode.openThenClosed,
    typicalLength: Duration(minutes: 4),
    meritBase: 12,
    iconKey: 'fish_petals',
    allowManualEnd: true,
    rulesText:
        '长按屏幕，把浮标落在手指处，闭眼等。\n刚投下会惊散花瓣——前两秒不会有人上钩；\n甩得越久，花瓣越愿意靠近。\n'
        '"叮"是花瓣碰竿，1.5 秒内松手收杆；"咚"只是杂物，收了也是空竿。',
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
          _restFrom(now);
        } else if (held > _hookTimeoutUs) {
          // "咚"后长时间握着不放：自动空竿休整，不把状态机吊死。
          _restFrom(now);
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

  void _hook(int now) {
    _hookAtUs = now;
    _hookIsPetal = _rng.nextDouble() < _petalChance;
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
          // 甩杆：浮标落在手指处（待对齐清单 #7）。
          _state = _RodState.casting;
          _castStartUs = now;
          _casts++;
          _buoyPos = e.position;
          _ctx.sounds.play(SoundCatalog.swishKey, gain: 0.6);
          _ctx.recorder.log('cast', {'at': now});
          notifyVisualChanged();
        }
      case PointerPhase.move:
        // 按住拖动 = 移动浮标；花瓣散开交给视觉层响应位置变化。
        if (_state == _RodState.casting || _state == _RodState.hooked) {
          if (e.position != null && e.position != _buoyPos) {
            _buoyPos = e.position;
            notifyVisualChanged();
          }
        }
      case PointerPhase.up:
      case PointerPhase.cancel:
        if (_state == _RodState.hooked) {
          final heldUs = _hookAtUs - _castStartUs;
          if (_hookIsPetal && now - _hookAtUs <= _catchWindowUs) {
            // 收杆成功：花瓣入库。
            _petalsCaught++;
            _waitTimesUs.add(heldUs);
            _caught.add(const Reward(kind: RewardKind.petal, id: 'petal', label: '花瓣'));
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
        // 收杆 = 浮标离水。
        _buoyPos = null;
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
      _RodState.idle => '长按投下浮标 · 闭眼等候',
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
          ),
        ),
        // 花瓣聚散氛围层（待对齐清单 #7）：常驻以保留粒子状态。
        Positioned.fill(
          child: IgnorePointer(
            child: _BuoyPetalLayer(
              buoy: _buoyPos,
              showBuoy: _state == _RodState.casting || _state == _RodState.hooked,
              catchPulse: _catchPulse,
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

/// 浮标 + 花瓣聚散氛围层（纯视觉，不参与判定）。
///
/// 行为（待对齐清单 #7）：
/// - 浮标落下：在落点播放"略微放大 + 涟漪"动画；附近花瓣按距离远近
///   不同程度散开。
/// - 之后花瓣慢慢、带随机扰动地向浮标靠近，近到一定程度便停在浮标边。
/// - 浮标移动（按住拖动）：对附近花瓣再施加一次散射。
class _BuoyPetalLayer extends StatefulWidget {
  const _BuoyPetalLayer({
    required this.buoy,
    required this.showBuoy,
    required this.catchPulse,
  });

  final Offset? buoy;
  final bool showBuoy;
  final int catchPulse;

  @override
  State<_BuoyPetalLayer> createState() => _BuoyPetalLayerState();
}

class _BuoyPetalLayerState extends State<_BuoyPetalLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  final List<_FloatingPetal> _petals = [];
  final List<_Ripple> _ripples = [];
  Offset? _lastBuoy;
  double _dropAge = 999; // 距浮标落水的秒数（入场放大用）
  bool _reduceMotion = false;
  int _seenCatchPulse = 0;
  final Random _rng = Random(11);

  static const double _scatterRadius = 130; // 惊散范围（逻辑像素）
  static const double _settleRadius = 22; // 靠近到该距离即停在浮标边

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(days: 365),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.maybeOf(context);
    _reduceMotion =
        (media?.disableAnimations ?? false) || (media?.accessibleNavigation ?? false);
    if (_petals.isEmpty && size().width > 0) _seedPetals();
  }

  Size size() => MediaQuery.maybeOf(context)?.size ?? Size.zero;

  void _seedPetals() {
    final s = size();
    for (var i = 0; i < 12; i++) {
      _petals.add(
        _FloatingPetal(
          pos: Offset(
            _rng.nextDouble() * s.width,
            _rng.nextDouble() * s.height * 0.7 + s.height * 0.15,
          ),
          phase: _rng.nextDouble() * 2 * pi,
          tint: kPetalTints[_rng.nextInt(kPetalTints.length)],
        ),
      );
    }
  }

  void _scatterFrom(Offset center, double strength) {
    for (final p in _petals) {
      final d = p.pos - center;
      final dist = d.distance;
      if (dist < _scatterRadius && dist > 0.01) {
        final falloff = 1 - dist / _scatterRadius;
        p.vel += d / dist * falloff * 260 * strength;
        p.settled = false;
      }
    }
  }

  @override
  void didUpdateWidget(covariant _BuoyPetalLayer old) {
    super.didUpdateWidget(old);
    final buoy = widget.buoy;
    if (buoy != null) {
      final prev = _lastBuoy;
      if (prev == null) {
        // 浮标落水：涟漪 + 惊散。
        _ripples.add(_Ripple(pos: buoy, age: 0, big: true));
        _scatterFrom(buoy, 1.0);
        _dropAge = 0;
      } else if ((buoy - prev).distance > 6) {
        // 移动浮标：花瓣散开（幅度随移动幅度）。
        _scatterFrom(buoy, ((buoy - prev).distance / 60).clamp(0.4, 1.0));
      }
      _lastBuoy = buoy;
    } else {
      _lastBuoy = null;
    }
    if (widget.catchPulse > _seenCatchPulse && _lastBuoy != null) {
      _seenCatchPulse = widget.catchPulse;
      _ripples.add(_Ripple(pos: _lastBuoy!, age: 0, big: false, gold: true));
    }
  }

  void _step(double dt) {
    final s = size();
    if (s == Size.zero) return;
    _dropAge += dt;
    final buoy = widget.showBuoy ? widget.buoy : null;
    for (final p in _petals) {
      if (buoy != null) {
        final toBuoy = buoy - p.pos;
        final dist = toBuoy.distance;
        if (p.settled && dist < _settleRadius * 1.6) {
          // 已停在浮标边，轻轻打转。
          p.phase += dt * 2;
          p.pos = buoy - toBuoy / max(dist, 0.01) * _settleRadius;
          p.vel *= 0.9;
          continue;
        }
        if (dist > _settleRadius) {
          // 慢慢随机靠近：朝向浮标 + 垂直方向的游移。
          final dir = toBuoy / max(dist, 0.01);
          final perp = Offset(-dir.dy, dir.dx);
          final wander = sin(p.phase + dist * 0.05) * 0.35;
          final pull = (dist > 260 ? 26.0 : 14.0);
          p.vel += dir * pull * dt + perp * wander * pull * dt;
        } else {
          p.settled = true;
        }
      } else {
        // 没有浮标：随波逐流。
        p.phase += dt * 0.6;
        p.vel += Offset(sin(p.phase) * 4 * dt, cos(p.phase * 0.8) * 3 * dt);
      }
      p.vel *= pow(0.55, dt).toDouble(); // 阻尼
      p.pos += p.vel * dt;
      // 留在水面内。
      p.pos = Offset(
        p.pos.dx.clamp(8, s.width - 8),
        p.pos.dy.clamp(s.height * 0.1, s.height - 8),
      );
    }
    for (final r in _ripples) {
      r.age += dt;
    }
    _ripples.removeWhere((r) => r.age > (r.big ? 1.1 : 0.8));
  }

  @override
  Widget build(BuildContext context) {
    if (_petals.isEmpty) _seedPetals();
    if (_reduceMotion) {
      return CustomPaint(
        painter: _BuoyPetalPainter(
          petals: _petals,
          ripples: const [],
          buoy: widget.showBuoy ? widget.buoy : null,
          buoyScale: 1,
        ),
      );
    }
    return AnimatedBuilder(
      animation: _ticker,
      builder: (context, _) {
        _step(1 / 60);
        final buoy = widget.showBuoy ? widget.buoy : null;
        // 落水后 0.45 秒内做"略微放大"的入场。
        final scale = _dropAge < 0.45
            ? 0.6 + 0.4 * Curves.easeOutBack.transform(_dropAge / 0.45)
            : 1.0;
        return CustomPaint(
          painter: _BuoyPetalPainter(
            petals: _petals,
            ripples: _ripples,
            buoy: buoy,
            buoyScale: scale,
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

class _FloatingPetal {
  _FloatingPetal({required this.pos, required this.phase, required this.tint});

  Offset pos;
  Offset vel = Offset.zero;
  double phase;
  Color tint;
  bool settled = false;
}

class _Ripple {
  _Ripple({required this.pos, required this.age, required this.big, this.gold = false});

  Offset pos;
  double age;
  bool big;
  bool gold;
}

const List<Color> kPetalTints = [
  Color(0xCCF2C9CE),
  Color(0xCCF5D9A8),
  Color(0xCCD9E4C9),
  Color(0xCCE8D0E8),
];

class _BuoyPetalPainter extends CustomPainter {
  _BuoyPetalPainter({
    required this.petals,
    required this.ripples,
    required this.buoy,
    required this.buoyScale,
  });

  final List<_FloatingPetal> petals;
  final List<_Ripple> ripples;
  final Offset? buoy;
  final double buoyScale;

  @override
  void paint(Canvas canvas, Size size) {
    // 花瓣。
    for (final p in petals) {
      canvas.drawCircle(p.pos, 4.5, Paint()..color = p.tint);
    }
    // 涟漪。
    for (final r in ripples) {
      final maxR = r.big ? 54.0 : 34.0;
      final t = (r.age / (r.big ? 1.1 : 0.8)).clamp(0.0, 1.0);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * (1 - t)
        ..color = (r.gold ? const Color(0x88D8B36A) : const Color(0x55E8DFC8))
            .withValues(alpha: (1 - t) * 0.8);
      canvas.drawCircle(r.pos, 6 + maxR * t, paint);
    }
    // 浮标。
    final b = buoy;
    if (b != null) {
      canvas.drawCircle(b, 9 * buoyScale, Paint()..color = const Color(0xFFB0473E));
      canvas.drawCircle(
        b,
        9 * buoyScale * 0.55,
        Paint()..color = const Color(0xFFEFE3C2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BuoyPetalPainter old) => true;
}
