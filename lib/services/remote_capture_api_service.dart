import 'dart:convert';
import 'dart:io';

import '../models/app_settings.dart';

class RemoteCaptureApiService {
  final HttpClient _client = HttpClient();

  Future<void> requestCapture(AppSettings settings) async {
    await _requestJson('POST', settings.buildApiUri('capture/request'));
  }

  Future<Map<String, dynamic>> _requestJson(String method, Uri uri) async {
    final request = await _client.openUrl(method, uri);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.contentLength = 0;

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      final errorBody = responseBody.isEmpty
          ? response.reasonPhrase
          : responseBody;
      throw HttpException(
        'Request failed (${response.statusCode}) for $uri: $errorBody',
        uri: uri,
      );
    }

    if (responseBody.isEmpty) {
      return const <String, dynamic>{};
    }

    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('JSON object response expected');
    }
    return decoded;
  }
}
