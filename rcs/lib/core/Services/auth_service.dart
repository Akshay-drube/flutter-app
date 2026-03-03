import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthService {
  
  static const String baseUrl = "http://209.74.81.208:8000";

  static Future<AuthResult> login({
  required String username,
  required String password,
}) async {
  try {
    print("Sending login request...");
    print("Username: $username");

    final response = await http.post(
      Uri.parse("$baseUrl/app_login"),
      headers: {
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "username": username,
        "password": password,
      }),
    );

    print("Status Code: ${response.statusCode}");
    print("Response Body: ${response.body}");

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      return AuthResult(
        success: true,
        message: data["message"] ?? "Login successful",
      );
    } else {
      final data = jsonDecode(response.body);

      return AuthResult(
        success: false,
        message: data["message"] ?? "Invalid credentials",
      );
    }
  } catch (e) {
    print("Error occurred: $e");

    return AuthResult(
      success: false,
      message: "Server error",
    );
  }
}
}

class AuthResult {
  final bool success;
  final String message;

  AuthResult({
    required this.success,
    required this.message,
  });
}