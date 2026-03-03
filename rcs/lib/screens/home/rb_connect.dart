import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:rcs/core/services/rb_service.dart';
import 'package:wifi_iot/wifi_iot.dart';

class RobotConnectScreen extends StatefulWidget {
  const RobotConnectScreen({super.key});

  @override
  State<RobotConnectScreen> createState() => _RobotConnectScreenState();
}

class _RobotConnectScreenState extends State<RobotConnectScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  _ScanState _state = _ScanState.scanning;
  String _errorMessage = '';
  bool _torchOn = false;
  bool _isProcessing = false;
  String _connectingStep = '';

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _onQrDetected(BarcodeCapture capture) async {
    if (_isProcessing || _state != _ScanState.scanning) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.trim().isEmpty) return;

    _isProcessing = true;
    _scannerController.stop();

    final qrCode = raw.trim();

    setState(() {
      _state = _ScanState.connecting;
      _connectingStep = 'Fetching robot info for "$qrCode"...';
    });

    // ── Step 1: Fetch robot info from MongoDB via backend ──────────────────
    final result = await RobotService.connectByQRCode(qrCode);

    if (!result.success || result.robot == null) {
      if (!mounted) return;
      setState(() {
        _state = _ScanState.error;
        _errorMessage = result.message;
      });
      return;
    }

    final robot = result.robot!;
    final config = robot.config;

    if (config == null) {
      if (!mounted) return;
      setState(() {
        _state = _ScanState.error;
        _errorMessage = 'Robot found but has no hotspot config in database.';
      });
      return;
    }

    // ── Step 2: Join robot hotspot ─────────────────────────────────────────
    setState(() => _connectingStep = 'Connecting to ${config.ssid}...');
    await _joinHotspot(config);

    // ── Step 3: Ping Pi ────────────────────────────────────────────────────
    if (!mounted) return;
    setState(() => _connectingStep = 'Reaching robot at ${config.ip}...');

    print("Trying to reach: http://${config.ip}:${config.port}/status");
    final status = await PiService.fetchStatus(config);

    if (!mounted) return;

    if (status.online) {
      final updatedRobot = RobotInfo.fromQR(config, status);

      // Release forced WiFi routing after we're done
      await WiFiForIoTPlugin.forceWifiUsage(false);

      Navigator.of(context).pop(updatedRobot);
    } else {
      // Release forced WiFi routing on failure too
      await WiFiForIoTPlugin.forceWifiUsage(false);

      setState(() {
        _state = _ScanState.error;
        _errorMessage =
            'Connected to ${config.ssid} but could not reach robot at '
            '${config.ip}:${config.port}.\n\nMake sure the Pi server is running.';
      });
    }
  }

  Future<void> _joinHotspot(RobotConfig config) async {
    try {
      print("Connecting to ${config.ssid}...");

      await WiFiForIoTPlugin.connect(
        config.ssid,
        password: config.password,
        security: NetworkSecurity.WPA,
        joinOnce: true,
        withInternet: false, // ← tells Android: use this even without internet
      );

      // Wait for Android to fully switch to the hotspot network
      await Future.delayed(const Duration(seconds: 5));

      // Force ALL app traffic through WiFi (hotspot), not mobile data
      await WiFiForIoTPlugin.forceWifiUsage(true);

      // Extra wait for routing to stabilize

      final ssid = await WiFiForIoTPlugin.getSSID();
      print("Connected SSID: $ssid");
    } catch (e) {
      print("WiFi error: $e");
      // Continue anyway — user may have connected manually
    }
  }

  void _resetScan() {
    _isProcessing = false;
    setState(() {
      _state = _ScanState.scanning;
      _errorMessage = '';
    });
    _scannerController.start();
  }

  void _toggleTorch() {
    _scannerController.toggleTorch();
    setState(() => _torchOn = !_torchOn);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Container(height: 0.5, color: const Color(0xFF141414)),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF1E1E1E)),
              ),
              child: const Icon(Icons.arrow_back_ios_new,
                  color: Color(0xFF8A8A8A), size: 15),
            ),
          ),
          const Spacer(),
          const Text('CONNECT ROBOT',
              style: TextStyle(
                  color: Color(0xFF3A3A3A),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3)),
          const Spacer(),
          if (_state == _ScanState.scanning)
            GestureDetector(
              onTap: _toggleTorch,
              child: Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: _torchOn ? Colors.white : const Color(0xFF111111),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF1E1E1E)),
                ),
                child: Icon(
                  _torchOn ? Icons.flashlight_on : Icons.flashlight_off,
                  color: _torchOn ? Colors.black : const Color(0xFF8A8A8A),
                  size: 17,
                ),
              ),
            )
          else
            const SizedBox(width: 38),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _ScanState.scanning:   return _buildScannerView();
      case _ScanState.connecting: return _buildConnectingView();
      case _ScanState.error:      return _buildErrorView();
    }
  }

  Widget _buildScannerView() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Column(
        children: [
          const SizedBox(height: 28),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Scan Robot QR',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3)),
                SizedBox(height: 6),
                Text(
                  'Point your camera at the QR code\non your robot to auto-connect.',
                  style: TextStyle(
                      color: Color(0xFF555555), fontSize: 14, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  children: [
                    MobileScanner(
                        controller: _scannerController,
                        onDetect: _onQrDetected),
                    Positioned.fill(
                        child: CustomPaint(painter: _ScanOverlayPainter())),
                    Center(
                      child: SizedBox(
                        width: 200, height: 200,
                        child: CustomPaint(painter: _CornerFramePainter()),
                      ),
                    ),
                    Positioned(
                      bottom: 20, left: 0, right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF2A2A2A)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _PulsingDot(),
                              SizedBox(width: 8),
                              Text('Scanning for QR code',
                                  style: TextStyle(
                                      color: Color(0xFF8A8A8A), fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Row(
              children: const [
                _ChipHint(icon: Icons.wifi, label: 'Auto WiFi'),
                SizedBox(width: 10),
                _ChipHint(icon: Icons.center_focus_strong_outlined, label: 'Hold steady'),
                SizedBox(width: 10),
                _ChipHint(icon: Icons.light_mode_outlined, label: 'Good light'),
              ],
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _buildConnectingView() {
    final step1Done = !_connectingStep.contains('Fetching');
    final step2Done = _connectingStep.contains('Reaching');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 40, height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF555555)),
              ),
            ),
            const SizedBox(height: 28),
            const Text('Connecting',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(_connectingStep,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xFF555555), fontSize: 13, height: 1.5)),
            const SizedBox(height: 40),
            _StepRow(icon: Icons.qr_code_outlined,  label: 'QR scanned',       done: true),
            const SizedBox(height: 12),
            _StepRow(icon: Icons.cloud_outlined,     label: 'Fetching from DB', done: step1Done),
            const SizedBox(height: 12),
            _StepRow(icon: Icons.wifi_outlined,      label: 'Joining hotspot',  done: step2Done),
            const SizedBox(height: 12),
            _StepRow(icon: Icons.smart_toy_outlined, label: 'Reaching robot',   done: false),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2A2A2A)),
            ),
            child: const Icon(Icons.link_off, color: Color(0xFF555555), size: 24),
          ),
          const SizedBox(height: 20),
          const Text('Connection Failed',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(_errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFF555555), fontSize: 13, height: 1.5)),
          const SizedBox(height: 36),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: _resetScan,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('SCAN AGAIN',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                      color: Colors.black)),
            ),
          ),
        ],
      ),
    );
  }
}

enum _ScanState { scanning, connecting, error }

// ── Painters ──────────────────────────────────────────────────────────────────
class _ScanOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.55);
    const boxSize = 200.0;
    final rect = Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: boxSize, height: boxSize);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
  }
  @override bool shouldRepaint(_) => false;
}

class _CornerFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const len = 24.0;
    const r = 12.0;
    canvas.drawPath(Path()..moveTo(0, len+r)..lineTo(0, r)..arcToPoint(Offset(r,0), radius: const Radius.circular(r))..lineTo(len+r,0), p);
    canvas.drawPath(Path()..moveTo(size.width-len-r,0)..lineTo(size.width-r,0)..arcToPoint(Offset(size.width,r), radius: const Radius.circular(r))..lineTo(size.width,len+r), p);
    canvas.drawPath(Path()..moveTo(0,size.height-len-r)..lineTo(0,size.height-r)..arcToPoint(Offset(r,size.height), radius: const Radius.circular(r), clockwise: false)..lineTo(len+r,size.height), p);
    canvas.drawPath(Path()..moveTo(size.width-len-r,size.height)..lineTo(size.width-r,size.height)..arcToPoint(Offset(size.width,size.height-r), radius: const Radius.circular(r), clockwise: false)..lineTo(size.width,size.height-len-r), p);
  }
  @override bool shouldRepaint(_) => false;
}

// ── Shared widgets ────────────────────────────────────────────────────────────
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();
  @override State<_PulsingDot> createState() => _PulsingDotState();
}
class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;
  @override void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _a = Tween<double>(begin: 0.3, end: 1.0).animate(_c);
  }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => FadeTransition(
    opacity: _a,
    child: Container(width: 7, height: 7,
        decoration: const BoxDecoration(color: Color(0xFF8A8A8A), shape: BoxShape.circle)));
}

class _ChipHint extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ChipHint({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E1E1E)),
      ),
      child: Column(children: [
        Icon(icon, color: const Color(0xFF3A3A3A), size: 16),
        const SizedBox(height: 5),
        Text(label, style: const TextStyle(color: Color(0xFF3A3A3A), fontSize: 10)),
      ]),
    ),
  );
}

class _StepRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool done;
  const _StepRow({required this.icon, required this.label, required this.done});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: done ? const Color(0xFF1A1A1A) : const Color(0xFF111111),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: done ? const Color(0xFF3A3A3A) : const Color(0xFF1E1E1E)),
        ),
        child: Icon(done ? Icons.check : icon,
            color: done ? const Color(0xFF8A8A8A) : const Color(0xFF2A2A2A),
            size: 15),
      ),
      const SizedBox(width: 12),
      Text(label,
          style: TextStyle(
              color: done ? const Color(0xFF8A8A8A) : const Color(0xFF2A2A2A),
              fontSize: 13)),
    ],
  );
}