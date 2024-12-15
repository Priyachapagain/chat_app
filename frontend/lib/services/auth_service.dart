import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class AuthService {
  final String baseUrl = 'http://192.168.1.11:5000'; // Your backend URL
  final storage = const FlutterSecureStorage();

  // Login function
  Future<String?> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await storage.write(key: 'token', value: data['token']);
      return null;
    } else {
      return jsonDecode(response.body)['error'];
    }
  }

  // Register function without profile picture (Base64)
  Future<String?> register(String email, String password, String username) async {
    final response = await http.post(
      Uri.parse('$baseUrl/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'username': username,
      }),
    );

    if (response.statusCode == 201) {
      return null;
    } else {
      return jsonDecode(response.body)['error'];
    }
  }

  // Get token from secure storage
  Future<String?> getToken() async {
    return await storage.read(key: 'token');
  }

  // Logout and remove the token from secure storage
  Future<void> logout() async {
    await storage.delete(key: 'token');
  }
}
