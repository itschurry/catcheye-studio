import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:catcheye_studio/models/app_settings.dart';
import 'package:catcheye_studio/services/remote_production_api_service.dart';
import 'package:catcheye_studio/widgets/camera_setup_dialog.dart';

Map<String, dynamic> setup() => {
  'revision': 3,
  'hardware': [
    for (var i = 0; i < 4; i++)
      {
        'hardware_id': i,
        'camera_id': 'camera_$i',
        'width': 1920,
        'height': 1200,
        'offset_x': 8,
        'offset_y': 8,
      },
  ],
  'cameras': [
    for (var i = 0; i < 2; i++)
      {
        'serial': 'S$i',
        'ip': '192.168.1.${101 + i}',
        'model': 'Basler',
        'discovered': true,
        'hardware_id': i,
        'calibration_name': i == 0 ? 'S0.yaml' : '',
        'undistortion_enabled': false,
        'open': false,
        'last_error': '',
      },
  ],
};

class CameraApi extends RemoteProductionApiService {
  Map<String, dynamic> data = setup();
  Map<String, dynamic>? saved;
  int writes = 0;
  bool fail = false;
  @override
  Future<Map<String, dynamic>> request(
    AppSettings settings,
    String method,
    String endpoint, [
    Map<String, dynamic>? body,
  ]) async {
    expect(endpoint, 'camera-setup');
    if (method == 'PUT') {
      writes++;
      if (fail) {
        throw const ProductionApiException(
          409,
          'CAMERA_CONFIG_REVISION_CONFLICT',
        );
      }
      saved = body;
      data['revision'] = 4;
      for (final camera in data['cameras'] as List) {
        final row = (body!['cameras'] as List).singleWhere(
          (row) => row['serial'] == camera['serial'],
        );
        camera['hardware_id'] = row['hardware_id'];
        camera['undistortion_enabled'] = row['undistortion_enabled'];
        if (row['calibration'] != null) {
          camera['calibration_name'] = row['calibration']['file_name'];
        }
      }
    }
    return jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
  }
}

Future<void> open(
  WidgetTester tester,
  CameraApi api, {
  bool Function()? canSave,
  Future<CalibrationUpload?> Function()? pick,
  Future<void> Function(String)? preview,
}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(api.close);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => CameraSetupDialog(
                settings: AppSettings(),
                api: api,
                canSave: canSave ?? () => true,
                pickCalibration: pick,
                onPreview: preview ?? (_) async {},
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String serial, String label) async {
  final selector = find.byWidgetPredicate(
    (w) =>
        w is DropdownButtonFormField<int> &&
        w.key.toString().contains('hardware-$serial-'),
  );
  await tester.ensureVisible(selector);
  await tester.tap(selector);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'discovery includes missing saved cameras and preview uses logical camera id',
    (tester) async {
      final api = CameraApi();
      api.data['cameras'][1]['discovered'] = false;
      String? preview;
      await open(
        tester,
        api,
        preview: (id) async {
          preview = id;
        },
      );
      expect(find.textContaining('검색 안 됨'), findsOneWidget);
      await tester.ensureVisible(find.text('영상 확인').first);
      await tester.tap(find.text('영상 확인').first);
      await tester.pumpAndSettle();
      expect(preview, 'camera_0');
    },
  );
  testWidgets(
    'upload content and mapping are saved with revision and tied to serial',
    (tester) async {
      final api = CameraApi();
      await open(
        tester,
        api,
        pick: () async =>
            const CalibrationUpload('new.yaml', 'image_width: 1920'),
      );
      await choose(tester, 'S0', '너트 (2)');
      final file = find.byKey(const ValueKey('file-S0'));
      await tester.ensureVisible(file);
      await tester.tap(file);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(Switch).first);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('저장 및 적용'));
      await tester.pumpAndSettle();
      expect(api.saved!['base_revision'], 3);
      final row = api.saved!['cameras'][0];
      expect(row['serial'], 'S0');
      expect(row['hardware_id'], 2);
      expect(row['undistortion_enabled'], true);
      expect(row['calibration'], {
        'file_name': 'new.yaml',
        'content': 'image_width: 1920',
      });
      expect(find.textContaining('저장·적용 완료'), findsOneWidget);
    },
  );
  testWidgets('duplicate hardware is rejected before writing', (tester) async {
    final api = CameraApi();
    await open(tester, api);
    await choose(tester, 'S1', '볼트 머리 (0)');
    await tester.tap(find.text('저장 및 적용'));
    await tester.pumpAndSettle();
    expect(api.writes, 0);
    expect(find.textContaining('한 대만 배정'), findsOneWidget);
  });
  testWidgets('offline assigned camera must be unassigned explicitly', (
    tester,
  ) async {
    final api = CameraApi();
    api.data['cameras'][1]['discovered'] = false;
    await open(tester, api);
    await tester.tap(find.text('저장 및 적용'));
    await tester.pumpAndSettle();
    expect(api.writes, 0);
    await choose(tester, 'S1', '미사용');
    await tester.tap(find.text('저장 및 적용'));
    await tester.pumpAndSettle();
    expect(api.saved!['cameras'][1]['hardware_id'], null);
  });
  testWidgets('enabling correction requires a calibration file', (
    tester,
  ) async {
    final api = CameraApi();
    await open(tester, api);
    await tester.ensureVisible(find.byType(Switch).last);
    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장 및 적용'));
    await tester.pumpAndSettle();
    expect(api.writes, 0);
    expect(find.textContaining('파일을 선택하세요'), findsOneWidget);
  });
  testWidgets('connection started during editing blocks apply', (tester) async {
    final api = CameraApi();
    var idle = true;
    await open(tester, api, canSave: () => idle);
    idle = false;
    await tester.tap(find.text('저장 및 적용'));
    await tester.pumpAndSettle();
    expect(api.writes, 0);
    expect(find.textContaining('PLC 연결 해제'), findsWidgets);
  });
  testWidgets(
    'save conflict retains selection and requires reload without retry',
    (tester) async {
      final api = CameraApi()..fail = true;
      await open(tester, api);
      await choose(tester, 'S0', '너트 (2)');
      await tester.tap(find.text('저장 및 적용'));
      await tester.pumpAndSettle();
      expect(api.writes, 1);
      expect(
        find.textContaining('CAMERA_CONFIG_REVISION_CONFLICT'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '저장 및 적용'))
            .onPressed,
        null,
      );
      expect(find.text('너트 (2)'), findsWidgets);
    },
  );
  testWidgets(
    'oversized upload is rejected and narrow window has no overflow',
    (tester) async {
      final api = CameraApi();
      await open(
        tester,
        api,
        pick: () async => CalibrationUpload('big.yaml', 'x' * 65537),
      );
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpAndSettle();
      final file = find.byKey(const ValueKey('file-S0'));
      await tester.ensureVisible(file);
      await tester.tap(file);
      await tester.pumpAndSettle();
      expect(find.textContaining('64 KiB'), findsOneWidget);
      expect(api.writes, 0);
      expect(tester.takeException(), null);
    },
  );
}
