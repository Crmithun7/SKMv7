import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

Uint8List? decodeSelfie(dynamic selfieImg) {
  if (selfieImg is! String || selfieImg.isEmpty) return null;
  final commaIndex = selfieImg.indexOf(',');
  final raw = commaIndex != -1
      ? selfieImg.substring(commaIndex + 1)
      : selfieImg;
  try {
    return base64Decode(raw);
  } catch (_) {
    return null;
  }
}

Color flagColor(String flag) {
  switch (flag) {
    case 'CHECK_IN':
      return Colors.green;
    case 'CHECK_OUT':
      return Colors.red;
    case 'BREAK_IN':
      return Colors.orange;
    case 'BREAK_OUT':
      return Colors.blue;
    default:
      return Colors.grey;
  }
}
