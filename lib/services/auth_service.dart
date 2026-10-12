import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/error_utils.dart';
import 'api_config.dart';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  static const String baseUrl = '${ApiConfig.baseHost}/api/v1/auth';

  // The SKM super admin grants each company access per application; this
  // header tells the backend the request comes from the skmv7 mobile app.
  static const Map<String, String> appHeaders = {'X-SKM-App': 'skmv7'};

  static Future<Map<String, dynamic>> login({
    required String loginCode,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/json', ...appHeaders},
      body: jsonEncode({'login_code': loginCode, 'password': password}),
    );

    if (response.statusCode == 401) {
      throw AuthException(
        'Incorrect login code or password. Please check and try again.',
      );
    }
    if (response.statusCode != 200) {
      throw AuthException(
        serverErrorMessage(
          response,
          fallback: "Couldn't log you in. Please try again.",
        ),
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    return body;
  }

  /// Null while the signed-in company may keep using the mobile app, else the
  /// reason it may not (app access removed, company blocked or expired).
  /// Network and server errors return null so being offline never signs the
  /// user out.
  static Future<String?> checkAppAccess(String token) async {
    try {
      final response = await http
          .get(
            Uri.parse('${ApiConfig.baseHost}/api/v1/app-access/check'),
            headers: {...appHeaders, 'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 401 && response.statusCode != 403) {
        return null;
      }
      return serverErrorMessage(
        response,
        fallback: 'Your session has ended. Please sign in again.',
      );
    } catch (_) {
      return null;
    }
  }
}
