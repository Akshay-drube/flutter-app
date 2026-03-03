import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:rcs/core/services/auth_service.dart';

// ── Robot Config (parsed from QR code) ────────────────────────────────────────
// QR code contains just a robot code string e.g. "RBT-001"
// We fetch the real config from MongoDB via your backend
class RobotConfig {
  final String ssid;
  final String password;
  final String ip;
  final int port;

  RobotConfig({
    required this.ssid,
    required this.password,
    required this.ip,
    required this.port,
  });

  String get streamUrl => 'http://$ip:$port/stream';
  String get statusUrl => 'http://$ip:$port/status';
  String get dataUrl   => 'http://$ip:$port/data';

  factory RobotConfig.fromJson(Map<String, dynamic> json) {
    return RobotConfig(
      ssid:     json['ssid']     ?? '',
      password: json['password'] ?? '',
      ip:       json['ip']       ?? '192.168.4.1',
      port:     int.tryParse(json['port']?.toString() ?? '8080') ?? 8080,
    );
  }

  Map<String, dynamic> toJson() => {
    'ssid':     ssid,
    'password': password,
    'ip':       ip,
    'port':     port,
  };
}

// ── Pi status response ─────────────────────────────────────────────────────────
class PiStatus {
  final bool online;
  final String name;

  PiStatus({required this.online, required this.name});
}

// ── Pi live data response ──────────────────────────────────────────────────────
class PiData {
  final double mbits;
  final String distance;
  final String txBitrate;
  final double latitude;
  final double longitude;
  final String location;
  final String gpsStatus;
  final bool connected;

  PiData({
    required this.mbits,
    required this.distance,
    required this.txBitrate,
    required this.latitude,
    required this.longitude,
    required this.location,
    required this.gpsStatus,
    required this.connected,
  });

  factory PiData.empty() => PiData(
    mbits: 0,
    distance: '—',
    txBitrate: '—',
    latitude: 0,
    longitude: 0,
    location: '—',
    gpsStatus: 'unknown',
    connected: false,
  );
}

// ── Pi Service — talks directly to Raspberry Pi ───────────────────────────────
class PiService {
  static Future<PiStatus> fetchStatus(RobotConfig config) async {
    try {
      final res = await http
          .get(Uri.parse(config.statusUrl))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return PiStatus(
          online: data['status'] == 'online',
          name:   data['name']   ?? 'Pi_Robot',
        );
      }
    } catch (_) {}
    return PiStatus(online: false, name: 'Pi_Robot');
  }

  static Future<PiData> fetchData(RobotConfig config) async {
    try {
      final res = await http
          .get(Uri.parse(config.dataUrl))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final signal = json['signal'] ?? {};
        final gps    = json['gps']    ?? {};
        return PiData(
          mbits:     (signal['mbits']    ?? 0).toDouble(),
          distance:   signal['distance'] ?? '—',
          txBitrate:  signal['tx_bitrate'] ?? '—',
          latitude:  (gps['latitude']   ?? 0).toDouble(),
          longitude: (gps['longitude']  ?? 0).toDouble(),
          location:   gps['location']   ?? '—',
          gpsStatus:  gps['gps_status'] ?? 'unknown',
          connected:  json['status']    == 'connected',
        );
      }
    } catch (_) {}
    return PiData.empty();
  }
}

// ── Robot Service — talks to your MongoDB backend ─────────────────────────────
class RobotService {
  static const String baseUrl = AuthService.baseUrl;

  /// Scan QR → get robot code string → fetch robot info from MongoDB
  static Future<RobotResult> connectByQRCode(String qrCode) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/robot/connect"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"qr_code": qrCode}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return RobotResult(
          success: true,
          message: data["message"] ?? "Robot connected",
          robot: RobotInfo.fromJson(data["robot"] ?? {}),
        );
      } else {
        return RobotResult(
          success: false,
          message: data["message"] ?? "Robot not found",
        );
      }
    } catch (e) {
      return RobotResult(
        success: false,
        message: "Connection failed. Check your network.",
      );
    }
  }
}

// ── Robot Info ────────────────────────────────────────────────────────────────
class RobotInfo {
  final String id;
  final String name;
  final String model;
  final String status;
  final String location;
  final String firmware;
  final String lastSeen;
  final RobotConfig? config; // Pi hotspot config — may come from MongoDB

  RobotInfo({
    required this.id,
    required this.name,
    required this.model,
    required this.status,
    required this.location,
    required this.firmware,
    required this.lastSeen,
    this.config,
  });

  /// Build RobotInfo from QR scan result + Pi status
  factory RobotInfo.fromQR(RobotConfig config, PiStatus status) {
    return RobotInfo(
      id:       config.ip,
      name:     status.name,
      model:    'Raspberry Pi',
      status:   status.online ? 'online' : 'offline',
      location: config.ip,
      firmware: '—',
      lastSeen: DateTime.now().toIso8601String(),
      config:   config,
    );
  }

  /// Build RobotInfo from MongoDB response
  /// MongoDB should return robot details including hotspot config
  factory RobotInfo.fromJson(Map<String, dynamic> json) {
    // If MongoDB returns hotspot config inside robot object
    RobotConfig? config;
    if (json['config'] != null) {
      config = RobotConfig.fromJson(json['config'] as Map<String, dynamic>);
    } else if (json['ip'] != null) {
      // Flat format — ip/port at top level
      config = RobotConfig(
        ssid:     json['ssid']     ?? 'Robot_Hotspot',
        password: json['password'] ?? 'robot1234',
        ip:       json['ip']       ?? '192.168.4.1',
        port:     int.tryParse(json['port']?.toString() ?? '8080') ?? 8080,
      );
    }

    return RobotInfo(
      id:       json["id"]        ?? "—",
      name:     json["name"]      ?? "Unknown Robot",
      model:    json["model"]     ?? "—",
      status:   json["status"]    ?? "offline",
      location: json["location"]  ?? "—",
      firmware: json["firmware"]  ?? "—",
      lastSeen: json["last_seen"] ?? "—",
      config:   config,
    );
  }

  Map<String, dynamic> toJson() => {
    "id":        id,
    "name":      name,
    "model":     model,
    "status":    status,
    "location":  location,
    "firmware":  firmware,
    "last_seen": lastSeen,
    if (config != null) "config": config!.toJson(),
  };
}

// ── Robot Result ──────────────────────────────────────────────────────────────
class RobotResult {
  final bool success;
  final String message;
  final RobotInfo? robot;

  RobotResult({
    required this.success,
    required this.message,
    this.robot,
  });
}