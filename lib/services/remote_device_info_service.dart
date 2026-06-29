import 'dart:convert';
import 'dart:io';

import '../models/app_settings.dart';

class RemoteDeviceInfo {
  final RemoteDeviceKind kind;
  final bool personRoiAlertDisabled;

  const RemoteDeviceInfo({
    required this.kind,
    required this.personRoiAlertDisabled,
  });
}

class RemoteDeviceInfoService {
  final HttpClient _client = HttpClient();

  Future<RemoteDeviceInfo> fetchInfo(AppSettings settings) async {
    final request = await _client.openUrl(
      'GET',
      settings.buildApiUri('device-info'),
    );
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
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
    final kind = decoded['kind'];
    if (kind is! String) {
      throw const FormatException('device kind string expected');
    }
    final personRoiAlertDisabled = decoded['person_roi_alert_disabled'];
    if (personRoiAlertDisabled is! bool) {
      throw const FormatException(
        'person_roi_alert_disabled bool expected',
      );
    }
    return RemoteDeviceInfo(
      kind: RemoteDeviceKind.fromApiValue(kind),
      personRoiAlertDisabled: personRoiAlertDisabled,
    );
  }
}
