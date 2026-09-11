import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 요청과 응답 본문 전체에 제한 시간을 적용하며, 실패한 요청은 반복하지 않습니다.
class ApiHttpClient {
  ApiHttpClient({
    HttpClient? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? HttpClient();

  final HttpClient _client;
  final Duration timeout;
  bool _closed = false;

  void close() {
    _closed = true;
    _client.close(force: true);
  }

  Future<T> send<T>(
    String method,
    Uri uri, {
    Object? body,
    String accept = 'application/json',
    Map<String, String> headers = const {},
    int? maxRequestBytes,
    required Future<T> Function(HttpClientResponse response) read,
  }) async {
    if (_closed) throw StateError('종료된 HTTP 클라이언트입니다');
    final encoded = body == null ? null : utf8.encode(jsonEncode(body));
    if (maxRequestBytes != null &&
        encoded != null &&
        encoded.length > maxRequestBytes) {
      throw FormatException('요청 본문이 $maxRequestBytes 바이트를 초과했습니다');
    }
    HttpClientRequest? pending;
    var cancelled = false;
    Future<T> perform() async {
      final request = await _client.openUrl(method, uri);
      pending = request;
      if (cancelled || _closed) {
        request.abort();
        throw StateError('종료된 HTTP 요청입니다');
      }
      request.headers.set(HttpHeaders.acceptHeader, accept);
      headers.forEach(request.headers.set);
      if (encoded != null) {
        request.headers.contentType = ContentType.json;
        request.contentLength = encoded.length;
        request.add(encoded);
      } else if (method == 'POST' || method == 'PUT') {
        request.contentLength = 0;
      }
      return read(await request.close());
    }

    try {
      return await perform().timeout(timeout);
    } catch (_) {
      cancelled = true;
      pending?.abort();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> requestJson(
    String method,
    Uri uri, {
    Object? body,
    Map<String, String> headers = const {},
    Set<int> expectedStatusCodes = const {200},
    bool allowEmpty = false,
    int? maxRequestBytes,
    Exception Function(int status, String body, String reason)? error,
  }) => send(
    method,
    uri,
    body: body,
    headers: headers,
    maxRequestBytes: maxRequestBytes,
    read: (response) async {
      final text = await response.transform(utf8.decoder).join();
      if (!expectedStatusCodes.contains(response.statusCode)) {
        throw error?.call(response.statusCode, text, response.reasonPhrase) ??
            HttpException(
              '요청 실패 (${response.statusCode}) · $uri: ${text.isEmpty ? response.reasonPhrase : text}',
              uri: uri,
            );
      }
      if (allowEmpty && text.isEmpty) return const <String, dynamic>{};
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('JSON 객체 응답이 필요합니다');
      }
      return decoded;
    },
  );
}
