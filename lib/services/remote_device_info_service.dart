import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/app_settings.dart';

class RemoteDeviceInfo {
  final RemoteDeviceKind kind;
  final bool personRoiAlertDisabled;
  final String? runtimeMode;

  const RemoteDeviceInfo({
    required this.kind,
    required this.personRoiAlertDisabled,
    this.runtimeMode,
  });

  bool get isInspectionStation =>
      kind == RemoteDeviceKind.inspection && runtimeMode == 'station';

  factory RemoteDeviceInfo.fromJson(Map<String, dynamic> json) {
    final kindValue = json['kind'];
    if (kindValue is! String) {
      throw const FormatException('device kind string expected');
    }
    final kind = RemoteDeviceKind.fromApiValue(kindValue);
    final personRoiAlertDisabled = json['person_roi_alert_disabled'];
    if (personRoiAlertDisabled != null && personRoiAlertDisabled is! bool) {
      throw const FormatException('person_roi_alert_disabled bool expected');
    }
    final runtimeMode = json['runtime_mode'];
    if (runtimeMode != null && runtimeMode is! String) {
      throw const FormatException('runtime_mode string expected');
    }
    if (kind == RemoteDeviceKind.inspection &&
        runtimeMode != null &&
        runtimeMode != 'station') {
      throw FormatException(
        'unsupported inspection runtime mode: $runtimeMode',
      );
    }
    return RemoteDeviceInfo(
      kind: kind,
      personRoiAlertDisabled: personRoiAlertDisabled == true,
      runtimeMode: runtimeMode as String?,
    );
  }
}

class RemoteDeviceInfoService {
  RemoteDeviceInfoService({
    Duration requestTimeout = const Duration(seconds: 10),
  }) : _requestTimeout = requestTimeout;

  final HttpClient _client = HttpClient();
  final Duration _requestTimeout;

  void close() => _client.close(force: true);

  Future<RemoteDeviceInfo> fetchInfo(AppSettings settings) async {
    final request = await _client
        .openUrl('GET', settings.buildApiUri('device-info'))
        .timeout(_requestTimeout);
    try {
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response = await request.close().timeout(_requestTimeout);
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_requestTimeout);
      if (response.statusCode != 200) {
        final errorBody = responseBody.isEmpty
            ? response.reasonPhrase
            : responseBody;
        throw HttpException(
          'Request failed (${response.statusCode}) for ${settings.buildApiUri('device-info')}: $errorBody',
        );
      }

      final decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('JSON object response expected');
      }
      return RemoteDeviceInfo.fromJson(decoded);
    } on TimeoutException {
      request.abort();
      rethrow;
    } catch (_) {
      request.abort();
      rethrow;
    }
  }
}
