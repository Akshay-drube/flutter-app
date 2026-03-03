import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:rcs/core/services/rb_service.dart';
import 'package:wifi_iot/wifi_iot.dart';

// ══════════════════════════════════════════════════════════════════════════════
// ROBOT CONTROL SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class RobotControlScreen extends StatefulWidget {
  final RobotInfo robot;
  const RobotControlScreen({super.key, required this.robot});

  @override
  State<RobotControlScreen> createState() => _RobotControlScreenState();
}

class _RobotControlScreenState extends State<RobotControlScreen>
    with TickerProviderStateMixin {

  // ── Real Pi data ────────────────────────────────────────────────────────────
  bool   _piOnline = false;
  String _piName   = 'Pi_Robot';
  PiData _piData   = PiData.empty();
  Timer? _statusTimer;
  Timer? _dataTimer;
  RobotConfig? get _cfg => widget.robot.config;

  // ── UI state ────────────────────────────────────────────────────────────────
  bool _isStarted = false;

  String get _statusLabel => !_piOnline ? 'OFFLINE' : _isStarted ? 'MOVING' : 'IDLE';
  Color  get _statusColor => !_piOnline
      ? const Color(0xFFFF2D55)
      : _isStarted ? const Color(0xFF00FF88) : const Color(0xFFFFB800);

  double get _rangeMeter {
    final m = _piData.mbits;
    if (m <= 0)   return 0.0;
    if (m >= 65)  return 1.5;
    if (m >= 54)  return 4.0;
    if (m >= 36)  return 7.5;
    if (m >= 18)  return 15.0;
    return 25.0;
  }

  int get _signalBars {
    final m = _piData.mbits;
    if (m >= 65) return 4;
    if (m >= 36) return 3;
    if (m >= 18) return 2;
    if (m > 0)   return 1;
    return 0;
  }

  // ── Animation controllers ───────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late AnimationController _fadeCtrl;
  late AnimationController _markerCtrl;
  late AnimationController _scanCtrl;
  late Animation<double>   _pulseAnim;
  late Animation<double>   _fadeAnim;
  late Animation<double>   _markerAnim;
  late Animation<double>   _scanAnim;

  // ── Telemetry bars ──────────────────────────────────────────────────────────
  final List<double> _teleBars = List.generate(16, (_) => 0.3);
  Timer? _teleTimer;

  @override
  void initState() {
    super.initState();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    Future.delayed(const Duration(milliseconds: 400), () {
      WiFiForIoTPlugin.forceWifiUsage(true);
    });

    if (_cfg != null) {
      _fetchStatus();
      _fetchData();
    }

    _pulseCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);
    _fadeCtrl   = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _markerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _scanCtrl   = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();

    _pulseAnim  = Tween<double>(begin: 0.3, end: 1.0).animate(CurvedAnimation(parent: _pulseCtrl,  curve: Curves.easeInOut));
    _fadeAnim   = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _markerAnim = Tween<double>(begin: 0.0, end: -6.0).animate(CurvedAnimation(parent: _markerCtrl, curve: Curves.easeInOut));
    _scanAnim   = Tween<double>(begin: 0.0, end: 1.0).animate(_scanCtrl);

    _fadeCtrl.forward();

    _teleTimer = Timer.periodic(const Duration(milliseconds: 130), (_) {
      if (!mounted) return;
      setState(() {
        _teleBars.removeAt(0);
        _teleBars.add(_piOnline ? (0.15 + Random().nextDouble() * 0.85) : 0.08);
      });
    });
  }

  Future<void> _fetchStatus() async {
    if (_cfg == null) return;
    final s = await PiService.fetchStatus(_cfg!);
    if (mounted) setState(() { _piOnline = s.online; _piName = s.name; });
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted) return;
      final s = await PiService.fetchStatus(_cfg!);
      if (mounted) setState(() { _piOnline = s.online; _piName = s.name; });
    });
  }

  Future<void> _fetchData() async {
    if (_cfg == null) return;
    final d = await PiService.fetchData(_cfg!);
    if (mounted) setState(() => _piData = d);
    _dataTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted) return;
      final d = await PiService.fetchData(_cfg!);
      if (mounted) setState(() => _piData = d);
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _dataTimer?.cancel();
    _teleTimer?.cancel();
    _pulseCtrl.dispose();
    _fadeCtrl.dispose();
    _markerCtrl.dispose();
    _scanCtrl.dispose();
    WiFiForIoTPlugin.forceWifiUsage(false);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onStart() => setState(() => _isStarted = true);
  void _onStop()  => setState(() => _isStarted = false);

  // ════════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(children: [
          // 1. Camera / background
          Positioned.fill(child: _buildCamera()),
          // 2. Gradient vignette
          Positioned.fill(child: _buildVignette()),
          // 3. Panels
          Positioned(top: 14, left: 14,  child: _buildRobotCard()),
          Positioned(top: 14, right: 14, child: _buildTopRight()),
          Positioned(bottom: 14, left: 14,  child: _buildControls()),
          Positioned(bottom: 14, right: 14, child: _buildMap()),
          // 4. Center crosshair
          Positioned.fill(child: IgnorePointer(child: Center(
            child: CustomPaint(size: const Size(80, 80),
              painter: _CrosshairPainter(opacity: _piOnline ? 0.38 : 0.12)),
          ))),
          // 5. Back
          Positioned(top: 14, left: 0, right: 0,
            child: Center(child: _buildBack())),
        ]),
      ),
    );
  }

  // ── Camera ──────────────────────────────────────────────────────────────────
  Widget _buildCamera() {
    if (_cfg != null && _piOnline) {
      return MjpegStream(streamUrl: _cfg!.streamUrl);
    }
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center, radius: 1.3,
          colors: [Color(0xFF060F20), Color(0xFF020609)],
        ),
      ),
      child: CustomPaint(painter: _GridPainter()),
    );
  }

  Widget _buildVignette() => IgnorePointer(
    child: Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center, radius: 1.0,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.5)],
        ),
      ),
    ),
  );

  // ── Robot Info Card ──────────────────────────────────────────────────────────
  Widget _buildRobotCard() {
    final hasGps = _piData.latitude != 0 || _piData.longitude != 0;
    return _Glass(
      width: 225,
      accent: _piOnline ? const Color(0xFF00FF88) : const Color(0xFFFF2D55),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, __) => Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _statusColor.withValues(alpha: 0.10 * _pulseAnim.value),
                  border: Border.all(
                    color: _statusColor.withValues(alpha: 0.55 * _pulseAnim.value),
                    width: 1.5,
                  ),
                ),
                child: Icon(Icons.smart_toy_outlined, color: _statusColor, size: 20),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_piName, style: const TextStyle(
                  color: Colors.white, fontSize: 14,
                  fontWeight: FontWeight.w700, letterSpacing: 0.4,
                  fontFamily: 'monospace',
                )),
                const SizedBox(height: 3),
                Row(children: [
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, __) => Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle, color: _statusColor,
                        boxShadow: [BoxShadow(
                          color: _statusColor.withValues(alpha: 0.75 * _pulseAnim.value),
                          blurRadius: 7, spreadRadius: 1,
                        )],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(_statusLabel, style: TextStyle(
                    color: _statusColor, fontSize: 9,
                    fontWeight: FontWeight.w800, letterSpacing: 2.5,
                  )),
                ]),
              ],
            )),
          ]),
          const SizedBox(height: 11),
          Container(height: 0.5, color: Colors.white.withValues(alpha: 0.07)),
          const SizedBox(height: 9),
          _Row(label: 'RANGE', value: '${_rangeMeter.toStringAsFixed(1)} m'),
          const SizedBox(height: 4),
          _Row(label: 'LAT', value: hasGps ? _piData.latitude.toStringAsFixed(5) : '—', mono: true),
          const SizedBox(height: 4),
          _Row(label: 'LNG', value: hasGps ? _piData.longitude.toStringAsFixed(5) : '—', mono: true),
          if (_piData.location != '—') ...[
            const SizedBox(height: 4),
            _Row(label: 'LOC', value: _piData.location),
          ],
        ],
      ),
    );
  }

  // ── Top Right ────────────────────────────────────────────────────────────────
  Widget _buildTopRight() => _Glass(
    width: 185,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            _SigBars(bars: _signalBars),
            const SizedBox(width: 7),
            Text(
              _piData.mbits > 0 ? '${_piData.mbits.toStringAsFixed(0)} Mbps' : '—',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.60), fontSize: 10, fontFamily: 'monospace'),
            ),
          ]),
          _Batt(level: 0.78),
        ]),
        const SizedBox(height: 11),
        Container(height: 0.5, color: Colors.white.withValues(alpha: 0.07)),
        const SizedBox(height: 8),
        Text('TELEMETRY', style: TextStyle(
          color: Colors.white.withValues(alpha: 0.24), fontSize: 8, letterSpacing: 2, fontWeight: FontWeight.w700,
        )),
        const SizedBox(height: 6),
        SizedBox(
          height: 30,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: _teleBars.map((h) => Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 0.7),
                height: 30 * h.clamp(0.05, 1.0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter, end: Alignment.topCenter,
                    colors: [
                      Color(0xFF00CFFF).withValues(alpha: 0.9),
                      Color(0xFF00CFFF).withValues(alpha: 0.25),
                    ],
                  ),
                ),
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 9),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _Chip(label: 'HOTSPOT', on: _piOnline),
          _Chip(label: _piOnline ? 'LINKED' : 'UNLINKED', on: _piOnline),
        ]),
      ],
    ),
  );

  // ── Controls ─────────────────────────────────────────────────────────────────
  Widget _buildControls() => _Glass(
    width: 195,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CONTROL', style: TextStyle(
          color: Colors.white.withValues(alpha: 0.24), fontSize: 8, letterSpacing: 2, fontWeight: FontWeight.w700,
        )),
        const SizedBox(height: 11),
        Row(children: [
          Expanded(child: _GlowBtn(
            label: 'START', icon: Icons.play_arrow_rounded,
            color: const Color(0xFF00FF88), active: _isStarted, onTap: _onStart,
          )),
          const SizedBox(width: 9),
          Expanded(child: _GlowBtn(
            label: 'STOP', icon: Icons.stop_rounded,
            color: const Color(0xFFFF2D55), active: !_isStarted, onTap: _onStop,
          )),
        ]),
        const SizedBox(height: 11),
        AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
          height: 3,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: _isStarted
                ? const LinearGradient(colors: [Color(0xFF00FF88), Color(0xFF00CFFF)])
                : null,
            color: _isStarted ? null : Colors.white.withValues(alpha: 0.06),
            boxShadow: _isStarted
                ? [const BoxShadow(color: Color(0x5500FF88), blurRadius: 8)]
                : [],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _isStarted ? '● Robot is running' : '○ Robot is stopped',
          style: TextStyle(
            color: _isStarted ? Color(0xFF00FF88).withValues(alpha: 0.75) : Colors.white.withValues(alpha: 0.18),
            fontSize: 9, letterSpacing: 0.5,
          ),
        ),
      ],
    ),
  );

  // ── Map ───────────────────────────────────────────────────────────────────────
  Widget _buildMap() {
    final lat = _piData.latitude  != 0 ? _piData.latitude  : 10.0261;
    final lng = _piData.longitude != 0 ? _piData.longitude : 76.3083;
    return _Glass(
      width: 205,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('LOCATION', style: TextStyle(
              color: Colors.white.withValues(alpha: 0.24), fontSize: 8, letterSpacing: 2, fontWeight: FontWeight.w700,
            )),
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 5, height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle, color: const Color(0xFF00CFFF),
                    boxShadow: [BoxShadow(
                      color: Color(0xFF00CFFF).withValues(alpha: _pulseAnim.value * 0.8),
                      blurRadius: 6,
                    )],
                  ),
                ),
                const SizedBox(width: 4),
                const Text('LIVE', style: TextStyle(
                  color: Color(0xFF00CFFF), fontSize: 7, letterSpacing: 1.5, fontWeight: FontWeight.w700,
                )),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AnimatedBuilder(
              animation: Listenable.merge([_markerCtrl, _scanCtrl]),
              builder: (_, __) => CustomPaint(
                size: const Size(double.infinity, 88),
                painter: _MapPainter(
                  markerOffset: _markerAnim.value,
                  scanProgress: _scanAnim.value,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('LAT', style: TextStyle(color: Colors.white.withValues(alpha: 0.18), fontSize: 7, letterSpacing: 1.5)),
              Text(lat.toStringAsFixed(5),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.60), fontSize: 10, fontFamily: 'monospace')),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('LNG', style: TextStyle(color: Colors.white.withValues(alpha: 0.18), fontSize: 7, letterSpacing: 1.5)),
              Text(lng.toStringAsFixed(5),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.60), fontSize: 10, fontFamily: 'monospace')),
            ]),
          ]),
        ],
      ),
    );
  }

  // ── Back button ──────────────────────────────────────────────────────────────
  Widget _buildBack() => GestureDetector(
    onTap: () => Navigator.of(context).pop(),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.arrow_back_ios_new, color: Colors.white.withValues(alpha: 0.38), size: 11),
            const SizedBox(width: 5),
            Text('BACK', style: TextStyle(
              color: Colors.white.withValues(alpha: 0.38), fontSize: 11,
              letterSpacing: 2.5, fontWeight: FontWeight.w700,
            )),
          ]),
        ),
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// GLASS PANEL
// ══════════════════════════════════════════════════════════════════════════════

class _Glass extends StatelessWidget {
  final Widget child;
  final double? width;
  final Color? accent;

  const _Glass({required this.child, this.width, this.accent});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(18),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Color(0xFF020C1C).withValues(alpha: 0.74),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: accent != null
                ? accent!.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.07),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: accent != null
                  ? accent!.withValues(alpha: 0.07)
                  : Colors.black.withValues(alpha: 0.4),
              blurRadius: 28,
            ),
            const BoxShadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 6)),
          ],
        ),
        child: child,
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// GLOW BUTTON
// ══════════════════════════════════════════════════════════════════════════════

class _GlowBtn extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  const _GlowBtn({
    required this.label, required this.icon,
    required this.color, required this.active, required this.onTap,
  });

  @override
  State<_GlowBtn> createState() => _GlowBtnState();
}

class _GlowBtnState extends State<_GlowBtn> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _s;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 90));
    _s = Tween<double>(begin: 1.0, end: 0.93).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => _c.forward(),
    onTapUp: (_) { _c.reverse(); widget.onTap(); },
    onTapCancel: () => _c.reverse(),
    child: AnimatedBuilder(
      animation: _s,
      builder: (_, child) => Transform.scale(scale: _s.value, child: child),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          color: widget.active ? widget.color.withValues(alpha: 0.16) : widget.color.withValues(alpha: 0.05),
          border: Border.all(
            color: widget.color.withValues(alpha: widget.active ? 0.60 : 0.18), width: 1.5,
          ),
          boxShadow: widget.active ? [
            BoxShadow(color: widget.color.withValues(alpha: 0.30), blurRadius: 16),
            BoxShadow(color: widget.color.withValues(alpha: 0.12), blurRadius: 32, spreadRadius: 2),
          ] : [],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(widget.icon,
            color: widget.color.withValues(alpha: widget.active ? 1.0 : 0.35), size: 20),
          const SizedBox(width: 5),
          Text(widget.label, style: TextStyle(
            color: widget.color.withValues(alpha: widget.active ? 1.0 : 0.35),
            fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.5,
          )),
        ]),
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// SMALL REUSABLE WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

class _Row extends StatelessWidget {
  final String label, value;
  final bool mono;
  const _Row({required this.label, required this.value, this.mono = false});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: TextStyle(
        color: Colors.white.withValues(alpha: 0.24), fontSize: 9, letterSpacing: 1.5, fontWeight: FontWeight.w600,
      )),
      Text(value, style: TextStyle(
        color: Colors.white.withValues(alpha: 0.70), fontSize: 11,
        fontFamily: mono ? 'monospace' : null, fontWeight: FontWeight.w600,
      )),
    ],
  );
}

class _SigBars extends StatelessWidget {
  final int bars;
  const _SigBars({required this.bars});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    mainAxisSize: MainAxisSize.min,
    children: List.generate(4, (i) => Container(
      width: 4, height: 6.0 + i * 4.0,
      margin: const EdgeInsets.only(left: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(1.5),
        color: i < bars ? const Color(0xFF00CFFF) : Colors.white.withValues(alpha: 0.10),
        boxShadow: i < bars
            ? [const BoxShadow(color: Color(0x8800CFFF), blurRadius: 4)]
            : [],
      ),
    )),
  );
}

class _Batt extends StatelessWidget {
  final double level;
  const _Batt({required this.level});

  @override
  Widget build(BuildContext context) {
    final c = level > 0.5 ? const Color(0xFF00FF88)
        : level > 0.2 ? const Color(0xFFFFB800)
        : const Color(0xFFFF2D55);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 24, height: 11,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2.5),
          border: Border.all(color: c.withValues(alpha: 0.5), width: 1.2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(1.5),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: level,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1),
                color: c,
                boxShadow: [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 4)],
              ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 4),
      Text('${(level * 100).round()}%',
        style: TextStyle(color: c, fontSize: 9, fontFamily: 'monospace')),
    ]);
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool on;
  const _Chip({required this.label, required this.on});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(5),
      color: on ? Color(0xFF00CFFF).withValues(alpha: 0.09) : Colors.white.withValues(alpha: 0.03),
      border: Border.all(
        color: on ? Color(0xFF00CFFF).withValues(alpha: 0.28) : Colors.white.withValues(alpha: 0.07),
      ),
    ),
    child: Text(label, style: TextStyle(
      color: on ? const Color(0xFF00CFFF) : Colors.white.withValues(alpha: 0.18),
      fontSize: 8, letterSpacing: 1.5, fontWeight: FontWeight.w700,
    )),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// PAINTERS
// ══════════════════════════════════════════════════════════════════════════════

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Color(0xFF00CFFF).withValues(alpha: 0.04)..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += 38) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 38) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }
  @override bool shouldRepaint(_) => false;
}

class _CrosshairPainter extends CustomPainter {
  final double opacity;
  _CrosshairPainter({required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final p = Paint()
      ..color = Color(0xFF00CFFF).withValues(alpha: opacity)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(Offset(cx, cy), 26, p);
    canvas.drawCircle(Offset(cx, cy), 3,
      Paint()..color = Color(0xFF00CFFF).withValues(alpha: opacity * 0.7));

    const gap = 7.0;
    canvas.drawLine(Offset(cx, cy - 26), Offset(cx, cy - gap), p);
    canvas.drawLine(Offset(cx, cy + gap), Offset(cx, cy + 26), p);
    canvas.drawLine(Offset(cx - 26, cy), Offset(cx - gap, cy), p);
    canvas.drawLine(Offset(cx + gap, cy), Offset(cx + 26, cy), p);

    const r = 20.0;
    for (int i = 0; i < 4; i++) {
      final a = i * pi / 2 + pi / 4;
      canvas.drawLine(
        Offset(cx + r * cos(a), cy + r * sin(a)),
        Offset(cx + (r + 8) * cos(a), cy + (r + 8) * sin(a)),
        p,
      );
    }
  }

  @override bool shouldRepaint(_CrosshairPainter o) => o.opacity != opacity;
}

class _MapPainter extends CustomPainter {
  final double markerOffset;
  final double scanProgress;
  _MapPainter({required this.markerOffset, required this.scanProgress});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width; final h = size.height;

    // BG
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h),
      Paint()..shader = const LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFF040E22), Color(0xFF061A2E)],
      ).createShader(Rect.fromLTWH(0, 0, w, h)));

    // Grid
    final gp = Paint()..color = Color(0xFF00CFFF).withValues(alpha: 0.06)..strokeWidth = 0.5;
    for (double x = 0; x < w; x += 18) canvas.drawLine(Offset(x, 0), Offset(x, h), gp);
    for (double y = 0; y < h; y += 18) canvas.drawLine(Offset(0, y), Offset(w, y), gp);

    // Roads
    final rp = Paint()..style = PaintingStyle.stroke..strokeWidth = 2.0
      ..color = Color(0xFF00CFFF).withValues(alpha: 0.13);
    canvas.drawPath(Path()
      ..moveTo(0, h * 0.52)
      ..quadraticBezierTo(w * 0.35, h * 0.32, w, h * 0.56), rp);
    canvas.drawPath(Path()
      ..moveTo(w * 0.48, 0)
      ..quadraticBezierTo(w * 0.50, h * 0.5, w * 0.44, h),
      rp..color = Color(0xFF00CFFF).withValues(alpha: 0.08));

    // Scan pulse
    final sr = 12.0 + scanProgress * 28.0;
    canvas.drawCircle(Offset(w / 2, h / 2), sr,
      Paint()
        ..color = Color(0xFF00CFFF).withValues(alpha: (1 - scanProgress) * 0.18)
        ..style = PaintingStyle.stroke..strokeWidth = 1);

    // Marker
    final mx = w / 2; final my = h / 2 + markerOffset;

    canvas.drawCircle(Offset(mx, my), 14,
      Paint()..color = Color(0xFF00CFFF).withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));

    final pin = Path()
      ..moveTo(mx, my - 11)
      ..cubicTo(mx - 7, my - 11, mx - 7, my - 1, mx, my + 7)
      ..cubicTo(mx + 7, my - 1, mx + 7, my - 11, mx, my - 11);
    canvas.drawPath(pin, Paint()..color = const Color(0xFF00CFFF));
    canvas.drawCircle(Offset(mx, my - 5.5), 2.5,
      Paint()..color = const Color(0xFF040E22));
  }

  @override
  bool shouldRepaint(_MapPainter o) =>
      o.markerOffset != markerOffset || o.scanProgress != scanProgress;
}

// ══════════════════════════════════════════════════════════════════════════════
// MJPEG STREAM
// ══════════════════════════════════════════════════════════════════════════════

class MjpegStream extends StatefulWidget {
  final String streamUrl;
  final BoxFit fit;
  const MjpegStream({super.key, required this.streamUrl, this.fit = BoxFit.cover});

  @override
  State<MjpegStream> createState() => _MjpegStreamState();
}

class _MjpegStreamState extends State<MjpegStream> {
  Uint8List? _frame;
  bool _error = false;
  StreamSubscription? _sub;
  http.Client? _client;

  @override void initState() { super.initState(); _start(); }

  Future<void> _start() async {
    try {
      _client = http.Client();
      final res = await _client!.send(http.Request('GET', Uri.parse(widget.streamUrl)));
      final List<int> buf = [];
      _sub = res.stream.listen(
        (chunk) {
          buf.addAll(chunk);
          int s = -1;
          for (int i = 0; i < buf.length - 1; i++) {
            if (buf[i] == 0xFF && buf[i+1] == 0xD8) { s = i; break; }
          }
          if (s == -1) return;
          for (int i = s; i < buf.length - 1; i++) {
            if (buf[i] == 0xFF && buf[i+1] == 0xD9) {
              final jpeg = Uint8List.fromList(buf.sublist(s, i + 2));
              buf.clear();
              if (mounted) setState(() => _frame = jpeg);
              break;
            }
          }
        },
        onError: (_) { if (mounted) setState(() => _error = true); },
        onDone: () => Future.delayed(const Duration(seconds: 2),
          () { if (mounted) _start(); }),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = true);
        Future.delayed(const Duration(seconds: 3),
          () { if (mounted) { setState(() => _error = false); _start(); } });
      }
    }
  }

  @override void dispose() { _sub?.cancel(); _client?.close(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (_frame != null) {
      return SizedBox.expand(
        child: Image.memory(_frame!, fit: widget.fit, gaplessPlayback: true),
      );
    }
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center, radius: 1.3,
          colors: [Color(0xFF060F20), Color(0xFF020609)],
        ),
      ),
      child: CustomPaint(painter: _GridPainter()),
    );
  }
}