import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/error_utils.dart';
import 'api_config.dart';
import 'session_service.dart';

class EventException implements Exception {
  final String message;
  EventException(this.message);

  @override
  String toString() => message;
}

class EventService {
  static const String baseUrl = '${ApiConfig.baseHost}/events';

  static Future<List<Map<String, dynamic>>> getEventsByCompany({
    required String companyCode,
    String? attendanceDate,
  }) async {
    final uri = Uri.parse('$baseUrl/company/$companyCode').replace(
      queryParameters: attendanceDate != null
          ? {'attendance_date': attendanceDate}
          : null,
    );

    final headers = await SessionService.authHeaders();
    final http.Response response;
    try {
      response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));
    } catch (e) {
      throw EventException(friendlyError(e));
    }

    if (response.statusCode != 200) {
      throw EventException(
        serverErrorMessage(
          response,
          fallback: "Couldn't load attendance records. Please try again.",
        ),
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    final data = body['data'] as List<dynamic>? ?? [];
    return data.cast<Map<String, dynamic>>();
  }
}
