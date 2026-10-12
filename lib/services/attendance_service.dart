import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/error_utils.dart';
import 'api_config.dart';

class AttendanceException implements Exception {
  final String message;
  AttendanceException(this.message);

  @override
  String toString() => message;
}

class AttendanceService {
  static const String baseUrl = '${ApiConfig.baseHost}/events';

  static Future<Map<String, dynamic>> getTodayStatus({
    required String companyCode,
    required String employeeId,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/today_status/$companyCode/$employeeId'),
    );

    if (response.statusCode != 200) {
      throw AttendanceException(
        serverErrorMessage(
          response,
          fallback: "Couldn't load today's attendance status. Please try again.",
        ),
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    return body;
  }

  static Future<Map<String, dynamic>> _postEvent(
    String path,
    Map<String, dynamic> data,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );

    if (response.statusCode != 200) {
      throw AttendanceException(
        serverErrorMessage(
          response,
          fallback: "Couldn't save your attendance. Please try again.",
        ),
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    return body;
  }

  static Future<Map<String, dynamic>> checkIn(Map<String, dynamic> data) {
    return _postEvent('advance-checkin', data);
  }

  static Future<Map<String, dynamic>> checkOut(Map<String, dynamic> data) {
    return _postEvent('advance-checkout', data);
  }
}
