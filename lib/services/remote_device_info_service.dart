import 'api_http_client.dart';
import 'dart:async';

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
      throw const FormatException('장비 종류 문자열이 필요합니다');
    }
    final kind = RemoteDeviceKind.fromApiValue(kindValue);
    final personRoiAlertDisabled = json['person_roi_alert_disabled'];
    if (personRoiAlertDisabled != null && personRoiAlertDisabled is! bool) {
      throw const FormatException('person_roi_alert_disabled 불리언 값이 필요합니다');
    }
    final runtimeMode = json['runtime_mode'];
    if (runtimeMode != null && runtimeMode is! String) {
      throw const FormatException('runtime_mode 문자열이 필요합니다');
    }
    if (kind == RemoteDeviceKind.inspection &&
        runtimeMode != null &&
        runtimeMode != 'station') {
      throw FormatException('지원하지 않는 검사 실행 모드: $runtimeMode');
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
  }) : _client = ApiHttpClient(timeout: requestTimeout);

  final ApiHttpClient _client;

  void close() => _client.close();

  Future<RemoteDeviceInfo> fetchInfo(AppSettings settings) async =>
      RemoteDeviceInfo.fromJson(
        await _client.requestJson('GET', settings.buildApiUri('device-info')),
      );
}
