import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../errors/app_exception.dart';

class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = Uri.parse(baseUrl ?? AppConfig.apiBaseUrl);

  final http.Client _client;
  final Uri _baseUrl;

  Future<Map<String, dynamic>> getJson(String path) async {
    final response = await _client
        .get(_baseUrl.resolve(path))
        .timeout(const Duration(seconds: 15));
    return _decodeMap(response);
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _client
        .post(
          _baseUrl.resolve(path),
          headers: {'Content-Type': 'application/json'},
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    return _decodeMap(response);
  }

  Future<Map<String, dynamic>> deleteJson(String path) async {
    final response = await _client
        .delete(_baseUrl.resolve(path))
        .timeout(const Duration(seconds: 30));
    return _decodeMap(response);
  }

  /// presigned GET URL에서 파일 bytes를 다운로드합니다.
  Future<Uint8List> getBytes(String url) async {
    final response = await _client
        .get(Uri.parse(url))
        .timeout(const Duration(minutes: 5));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AppException('파일 다운로드에 실패했습니다: ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  Future<void> putBytes(
    String url, {
    required Uint8List bytes,
    required String contentType,
  }) async {
    final response = await _client
        .put(
          Uri.parse(url),
          headers: {'Content-Type': contentType},
          body: bytes,
        )
        .timeout(const Duration(minutes: 5));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AppException('Presigned 업로드에 실패했습니다: ${response.statusCode}');
    }
  }

  Map<String, dynamic> _decodeMap(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AppException(
        response.body.isEmpty
            ? '요청에 실패했습니다: ${response.statusCode}'
            : response.body,
      );
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map<String, dynamic>) return decoded;
    throw const AppException('예상하지 못한 JSON 응답입니다.');
  }
}
