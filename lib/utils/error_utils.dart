import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;

// Every message the user sees should say what happened and what to do next,
// in plain words — never a class name, status code or server stack trace.

const String genericErrorMessage = 'Something went wrong. Please try again.';
const String noInternetMessage =
    'No internet connection. Please check your Wi-Fi or mobile data and try again.';
const String slowNetworkMessage =
    'The server is taking too long to respond. Please check your internet connection and try again.';
const String serverDownMessage =
    'Our server is having a problem right now. Please try again in a few minutes.';
const String sessionExpiredMessage =
    'Your session has expired. Please log out and log in again.';
const String noAccessMessage =
    "You don't have access to this. Please contact your admin.";
const String badReplyMessage =
    'We got an unexpected reply from the server. Please try again.';

/// Turns any caught error into a short message an employee can act on.
///
/// Messages this app wrote itself (thrown as `Exception('...')`) pass through
/// with Dart's `Exception: ` prefix removed. Network errors get a plain
/// explanation, and anything else technical falls back to [fallback].
String friendlyError(Object e, {String fallback = genericErrorMessage}) {
  // http 1.x wraps SocketException in ClientException, so check both.
  if (e is SocketException || e is http.ClientException) {
    return noInternetMessage;
  }
  if (e is TimeoutException) return slowNetworkMessage;
  if (e is HandshakeException || e is TlsException) {
    return 'Could not connect securely to the server. Please check that your '
        "phone's date and time are correct, or try a different network.";
  }
  if (e is FormatException) return badReplyMessage;
  if (e is CameraException) return friendlyCameraError(e);

  var text = e.toString().trim();
  if (text.startsWith('Exception: ')) {
    text = text.substring('Exception: '.length).trim();
  }
  if (text.isEmpty || _looksTechnical(text)) return fallback;
  return text;
}

/// Plain-language message for camera failures (permission denied, camera
/// busy, no camera on the device).
String friendlyCameraError(CameraException e) {
  final code = e.code.toLowerCase();
  if (code.contains('accessdenied') || code.contains('permission')) {
    return 'Camera access is turned off. Please allow camera access for this '
        'app in your phone Settings, then try again.';
  }
  if (code.contains('restricted')) {
    return "Camera use is restricted on this phone. Please check your phone's "
        'Screen Time or device management settings.';
  }
  if (code == 'no_camera' || code.contains('nocamera')) {
    return 'No camera was found on this phone.';
  }
  return 'The camera could not be started. Close any other app using the '
      'camera and try again.';
}

/// Builds the message to show for a failed (non-2xx) API [response].
///
/// The server's own `detail` text is used when it is already written for
/// people (e.g. "Your account is blocked. Contact admin."). Technical
/// details — database errors, field names, validation dumps — are replaced
/// with [fallback] or a message that matches the status code.
String serverErrorMessage(http.Response response,
    {String fallback = genericErrorMessage}) {
  final status = response.statusCode;
  final detail = _detailOf(response.body);

  // 503 carries the scheduled-maintenance notice, which is worth showing.
  if (status == 503 && detail is String && !_looksTechnical(detail)) {
    return detail.trim();
  }
  // Other 5xx details are database/exception text, never useful to an employee.
  if (status >= 500) return serverDownMessage;
  if (status == 408) return slowNetworkMessage;
  if (status == 429) {
    return 'Too many attempts. Please wait a minute and try again.';
  }

  if (detail is List) {
    // FastAPI validation errors: a list of {loc, msg, type} objects.
    return 'Some information is missing or not valid. Please check and try again.';
  }
  if (detail is String && detail.trim().isNotEmpty) {
    final known = _translateKnown(detail.trim());
    if (known != null) return known;
    if (!_looksTechnical(detail)) return detail.trim();
  }

  switch (status) {
    case 401:
      return sessionExpiredMessage;
    case 403:
      return noAccessMessage;
    default:
      return fallback;
  }
}

dynamic _detailOf(String body) {
  try {
    final data = jsonDecode(body);
    return data is Map ? data['detail'] : null;
  } catch (_) {
    return null; // HTML error page or plain text — no usable detail.
  }
}

/// Rewrites the backend's terse or technical messages that employees
/// commonly hit. Returns null when the message isn't one of these.
String? _translateKnown(String detail) {
  final d = detail.toLowerCase().replaceAll(RegExp(r'[.!]+$'), '');

  if (d == 'invalid credentials') {
    return 'Incorrect login code or password. Please check and try again.';
  }
  if (d == 'login_code and password are required') {
    return 'Please enter your login code and password.';
  }
  if (d == 'old password is incorrect' ||
      d == 'current password is incorrect') {
    return 'Your current password is incorrect. Please try again.';
  }
  if (d == 'employee not found') {
    return "We couldn't find your employee record. Please contact your admin.";
  }
  if (d == 'employee is inactive') {
    return 'Your account is inactive. Please contact your admin.';
  }
  if (d == 'no face detected') {
    return "We couldn't see your face. Make sure your whole face is in the "
        'frame and well lit, then try again.';
  }
  if (d == 'multiple faces detected') {
    return 'More than one face was detected. Please make sure only you are in '
        'the photo.';
  }
  if (d == 'invalid image' || d == 'invalid base64 image format') {
    return 'The photo could not be read. Please take it again.';
  }
  if (d.contains('database') ||
      d.contains('db connection') ||
      d.contains('internal server error')) {
    return serverDownMessage;
  }
  if (RegExp(r'^\w+ is required$').hasMatch(d)) {
    return 'Some required information is missing. Please try again.';
  }
  return null;
}

/// True for text that reads like a stack trace, exception dump, raw field
/// name or HTML page rather than a sentence meant for a person.
bool _looksTechnical(String text) {
  if (text.length > 220) return true;
  return RegExp(
    r'Exception|Error:|errno|Instance of|is not a subtype|Null check|'
    r'NoSuchMethod|RangeError|<html|<!doctype|Traceback|psycopg|SQL|'
    r'\b[a-z]+_[a-z_]+\b|https?://|\bHTTP \d{3}\b',
    caseSensitive: false,
  ).hasMatch(text);
}
