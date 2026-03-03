import 'package:flutter/material.dart';
import 'package:rcs/screens/home/login_screen.dart';
import 'package:rcs/screens/home/rb_connect.dart';
import 'package:rcs/screens/home/rb_control.dart';
import 'package:rcs/core/services/rb_service.dart';
import 'package:rcs/core/services/session_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  bool _isLoggedIn = false;
  bool _isLoading = false;
  final List<RobotInfo> _connectedRobots = [];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);

    // ✅ Prefs already loaded in main() — read synchronously, no delay
    _isLoggedIn = SessionService.getLoginState();
    _connectedRobots.addAll(SessionService.getRobots());
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  // ── Navigate to Login ──
  void _goToLogin(BuildContext context) async {
    Navigator.pop(context);
    final result = await Navigator.of(context).push<bool>(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const LoginScreen(),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
    if (result == true && mounted) {
      setState(() => _isLoggedIn = true);
      await SessionService.saveLoginState(true); // ✅ persist
    }
  }

  // ── Navigate to Robot Connect (from drawer) ──
  void _goToRobotConnect(BuildContext context) async {
    Navigator.pop(context);
    _openRobotConnectDirect(context);
  }

  // ── Navigate to Robot Connect (from home button) ──
  void _openRobotConnectDirect(BuildContext context) async {
    final robot = await Navigator.of(context).push<RobotInfo>(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const RobotConnectScreen(),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );

    if (robot != null && mounted) {
      setState(() {
        _connectedRobots.removeWhere((r) => r.id == robot.id);
        _connectedRobots.add(robot);
      });
      await SessionService.saveRobots(_connectedRobots); // ✅ persist
    }
  }

  // ── Navigate to Robot Control ──
  void _goToRobotControl(BuildContext context, RobotInfo robot) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => RobotControlScreen(robot: robot),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  // ── Logout with confirmation ──
  void _confirmLogout(BuildContext context) async {
    Navigator.pop(context);
    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Logout",
      barrierColor: Colors.black.withOpacity(0.85),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => const _LogoutDialog(),
      transitionBuilder: (_, animation, __, child) {
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
    if (confirmed == true && mounted) {
      setState(() {
        _isLoggedIn = false;
        _connectedRobots.clear();
      });
      await SessionService.clearSession(); // ✅ wipe persisted data
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "STUDIO",
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 4,
          ),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xCC000000), Colors.transparent],
            ),
          ),
        ),
      ),
      drawer: _buildDrawer(context),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Stack(
          children: [
            Positioned.fill(
              child:
                  Image.asset('assets/images/Drubebackground.jpg', fit: BoxFit.cover),
            ),
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xBB000000),
                      Color(0x88000000),
                      Color(0xCC000000),
                    ],
                    stops: [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
            _HomeContent(
              isLoggedIn: _isLoggedIn,
              connectedRobots: _connectedRobots,
              onConnectRobot: () => _openRobotConnectDirect(context),
              onRobotTap: (robot) => _goToRobotControl(context, robot),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF0D0D0D),
      child: Column(
        children: [
          Container(
            height: 160,
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFF1E1E1E), width: 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text(
                  "MENU",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isLoggedIn ? "You are signed in" : "Navigate",
                  style: const TextStyle(
                    color: Color(0xFF555555),
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _DrawerItem(
                  icon: Icons.home_outlined,
                  label: "Home",
                  onTap: () => Navigator.pop(context),
                ),
                _DrawerItem(
                  icon: Icons.settings_outlined,
                  label: "Settings",
                  onTap: () => Navigator.pop(context),
                ),
                if (_isLoggedIn) ...[
                  Container(
                    height: 0.5,
                    margin: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 6),
                    color: const Color(0xFF1A1A1A),
                  ),
                ],
                _isLoggedIn
                    ? _DrawerItem(
                        icon: Icons.logout,
                        label: "Logout",
                        onTap: () => _confirmLogout(context),
                        isDestructive: true,
                      )
                    : _DrawerItem(
                        icon: Icons.login_outlined,
                        label: "Login",
                        onTap: () => _goToLogin(context),
                      ),
              ],
            ),
          ),

          if (_isLoggedIn)
            Container(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF1E1E1E)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.circle,
                      color: Color(0xFF4CAF50), size: 8),
                  const SizedBox(width: 8),
                  Text(
                    _connectedRobots.isEmpty
                        ? "Signed in"
                        : "Signed in · ${_connectedRobots.length} robot${_connectedRobots.length > 1 ? 's' : ''} connected",
                    style: const TextStyle(
                      color: Color(0xFF8A8A8A),
                      fontSize: 12,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              "v1.0.0",
              style: TextStyle(
                color: Colors.white.withOpacity(0.2),
                fontSize: 11,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Home Content ──────────────────────────────────────────────────────────────
class _HomeContent extends StatelessWidget {
  final bool isLoggedIn;
  final List<RobotInfo> connectedRobots;
  final VoidCallback onConnectRobot;
  final void Function(RobotInfo) onRobotTap;

  const _HomeContent({
    required this.isLoggedIn,
    required this.connectedRobots,
    required this.onConnectRobot,
    required this.onRobotTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 32),
            const Center(
              child: Column(
                children: [
                  Text(
                    "WELCOME",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 6,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Home",
                    style: TextStyle(
                      color: Color(0xFF555555),
                      fontSize: 14,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),

            if (isLoggedIn) ...[
              const SizedBox(height: 40),

              // Section label
              Row(
                children: [
                  const Text(
                    "MY ROBOT",
                    style: TextStyle(
                      color: Color(0xFF3A3A3A),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.5,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
              ),

              const SizedBox(height: 12),

              if (connectedRobots.isEmpty)
                GestureDetector(
                  onTap: onConnectRobot,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFF2A2A2A)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: const Color(0xFF111111),
                            borderRadius: BorderRadius.circular(13),
                            border:
                                Border.all(color: const Color(0xFF2A2A2A)),
                          ),
                          child: const Icon(Icons.add,
                              color: Color(0xFF555555), size: 20),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Connect a Robot",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                "Scan QR code to pair your device",
                                style: TextStyle(
                                  color: Color(0xFF555555),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios,
                            color: Color(0xFF3A3A3A), size: 13),
                      ],
                    ),
                  ),
                )
              else ...[
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      ...connectedRobots.map((robot) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _RobotCard(
                              robot: robot,
                              onTap: () => onRobotTap(robot),
                            ),
                          )),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

// ── Robot Card ────────────────────────────────────────────────────────────────
class _RobotCard extends StatelessWidget {
  final RobotInfo robot;
  final VoidCallback onTap;

  const _RobotCard({required this.robot, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isOnline = robot.status.toLowerCase() == "online";

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0xFF2A2A2A)),
              ),
              child: const Icon(Icons.smart_toy_outlined,
                  color: Color(0xFF8A8A8A), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    robot.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(Icons.circle,
                          size: 7,
                          color: isOnline
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFF555555)),
                      const SizedBox(width: 5),
                      Text(
                        robot.status.toUpperCase(),
                        style: TextStyle(
                          color: isOnline
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFF555555),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        robot.model,
                        style: const TextStyle(
                          color: Color(0xFF3A3A3A),
                          fontSize: 10,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                color: Color(0xFF3A3A3A), size: 13),
          ],
        ),
      ),
    );
  }
}

// ── Logout Dialog ─────────────────────────────────────────────────────────────
class _LogoutDialog extends StatelessWidget {
  const _LogoutDialog();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          constraints: const BoxConstraints(maxWidth: 360),
          decoration: BoxDecoration(
            color: const Color(0xFF0E0E0E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF1E1E1E), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.6),
                blurRadius: 50,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFF141414),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF2A2A2A)),
                  ),
                  child: const Icon(Icons.logout,
                      color: Color(0xFF8A8A8A), size: 22),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Sign out?",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Are you sure you want to\nsign out of your account?",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF555555),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                Container(height: 0.5, color: const Color(0xFF1A1A1A)),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF8A8A8A),
                            side: const BorderSide(
                                color: Color(0xFF1E1E1E)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text("CANCEL",
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text("SIGN OUT",
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2,
                                  color: Colors.black)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Drawer Item ───────────────────────────────────────────────────────────────
class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;
  final String? badge;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        isDestructive ? const Color(0xFF666666) : const Color(0xFF8A8A8A);
    final textColor =
        isDestructive ? const Color(0xFFAAAAAA) : Colors.white;

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      leading: Icon(icon, color: color, size: 20),
      title: Row(
        children: [
          Text(label,
              style: TextStyle(
                color: textColor,
                fontSize: 15,
                fontWeight: FontWeight.w400,
                letterSpacing: 0.3,
              )),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF2A2A2A)),
              ),
              child: Text(badge!,
                  style: const TextStyle(
                    color: Color(0xFF555555),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  )),
            ),
          ],
        ],
      ),
      trailing: const Icon(Icons.arrow_forward_ios,
          color: Color(0xFF2A2A2A), size: 12),
      onTap: onTap,
    );
  }
}