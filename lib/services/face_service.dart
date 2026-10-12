import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../utils/error_utils.dart';
import 'api_config.dart';

class FaceException implements Exception {
  final String message;
  FaceException(this.message);

  @override
  String toString() => message;
}

class FaceService {
  static const String baseUrl = '${ApiConfig.baseHost}/api/v1/face';

  static Future<Map<String, dynamic>> registerFace({
    required String companyCode,
    required String employeeId,
    required String employeeName,
    required String pose,
    required File image,
  }) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/register'))
          ..fields['company_code'] = companyCode
          ..fields['employee_id'] = employeeId
          ..fields['employee_name'] = employeeName
          ..fields['pose'] = pose
          ..files.add(await http.MultipartFile.fromPath('image', image.path));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode != 200) {
      throw FaceException(
        serverErrorMessage(
          response,
          fallback: "Couldn't register the face. Please try again.",
        ),
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    return body;
  }

  static Future<Map<String, dynamic>> groupVerify({
    required String companyCode,
    required File image,
  }) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/group-verify'))
          ..fields['company_code'] = companyCode
          ..files.add(await http.MultipartFile.fromPath('image', image.path));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode != 200) {
      throw FaceException(
        serverErrorMessage(
          response,
          fallback: "Couldn't verify the face. Please try again.",
        ),
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    return body;
  }
}
