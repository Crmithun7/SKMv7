import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/error_utils.dart';
import 'api_config.dart';
import 'session_service.dart';

class EmployeeException implements Exception {
  final String message;
  EmployeeException(this.message);

  @override
  String toString() => message;
}

class EmployeeService {
  static const String baseUrl = '${ApiConfig.baseHost}/api/v1/admin';

  static Future<Map<String, dynamic>> getEmployeeSolo({
    required String companyCode,
    required String employeeId,
  }) async {
    final uri = Uri.parse('$baseUrl/employee/solo').replace(
      queryParameters: {'company_code': companyCode, 'employee_id': employeeId},
    );

    final response = await http.get(uri, headers: await SessionService.authHeaders());
    if (response.statusCode != 200) {
      throw EmployeeException(
        serverErrorMessage(
          response,
          fallback: "Couldn't load your profile. Please try again.",
        ),
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    return body['employee'] as Map<String, dynamic>;
  }

  static Future<List<Map<String, dynamic>>> getEmployees({
    required String companyCode,
    bool includeBlocked = false,
  }) async {
    final uri = Uri.parse('$baseUrl/employees').replace(
      queryParameters: {
        'company_code': companyCode,
        'include_blocked': includeBlocked.toString(),
      },
    );

    final response = await http.get(uri, headers: await SessionService.authHeaders());
    if (response.statusCode != 200) {
      throw EmployeeException(
        serverErrorMessage(
          response,
          fallback: "Couldn't load the employee list. Please try again.",
        ),
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    return (body['employees'] as List).cast<Map<String, dynamic>>();
  }

  static Future<void> changePassword({
    required String companyCode,
    required String employeeId,
    required String oldPassword,
    required String newPassword,
  }) async {
    final response = await http.put(
      Uri.parse('${ApiConfig.baseHost}/api/v1/employee/change_password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'company_code': companyCode,
        'employee_id': employeeId,
        'old_password': oldPassword,
        'new_password': newPassword,
      }),
    );

    if (response.statusCode != 200) {
      throw EmployeeException(
        serverErrorMessage(
          response,
          fallback: "Couldn't change your password. Please try again.",
        ),
      );
    }
  }
}
