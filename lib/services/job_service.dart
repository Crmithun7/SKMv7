import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../utils/error_utils.dart';
import 'api_config.dart';

class JobException implements Exception {
  final String message;
  JobException(this.message);

  @override
  String toString() => message;
}

class JobService {
  static const String baseUrl = '${ApiConfig.baseHost}/jobs';

  static Future<List<Map<String, dynamic>>> getJobsByCompany(
    String companyCode,
  ) async {
    final http.Response response;
    try {
      response = await http
          .get(Uri.parse('$baseUrl/$companyCode'))
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      throw JobException(friendlyError(e));
    }

    debugPrint('JOBS RESPONSE (${response.statusCode}): ${response.body}');

    if (response.statusCode != 200) {
      throw JobException(
        serverErrorMessage(
          response,
          fallback: "Couldn't load the job list. Please try again.",
        ),
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    final data = body['data'] as List<dynamic>? ?? [];
    return data.cast<Map<String, dynamic>>();
  }
}
