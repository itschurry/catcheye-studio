import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:catcheye_studio/models/app_settings.dart';
import 'package:catcheye_studio/services/remote_production_api_service.dart';
import 'package:catcheye_studio/widgets/camera_setup_panel.dart';

Map<String, dynamic> options() => {
  'device_user_id': '',
  'width': 1920,
  'height': 1200,
  'offset_x': 8,
  'offset_y': 8,
  'pixel_format': 'Mono8',
  'exposure_auto': 'Continuous',
  'exposure_us': 25000.0,
  'gain_auto': 'Continuous',
  'gain_db': 0.0,
  'balance_white_auto': 'Continuous',
  'frame_rate_enable': true,
  'frame_rate_hz': 15.0,
  'timeout_ms': 3000,
  'trigger_mode': 'free_run',
  'trigger_source': 'Line1',
};
List<Map<String, dynamic>> descriptors() => [
  for (final entry in options().entries)
    {
      'key': entry.key,
      'label': entry.key,
      'type': entry.value is bool
          ? 'boolean'
          : entry.value is int
          ? 'integer'
          : entry.value is double
          ? 'number'
          : 'string',
      'nullable': [
        'width',
        'height',
        'offset_x',
        'offset_y',
        'pixel_format',
        'balance_white_auto',
        'frame_rate_enable',
        'frame_rate_hz',
      ].contains(entry.key),
      if (entry.key.endsWith('_auto')) 'choices': ['Off', 'Once', 'Continuous'],
      if (entry.key == 'trigger_mode')
        'choices': ['free_run', 'software', 'hardware'],
      if (['width', 'height', 'timeout_ms'].contains(entry.key)) 'min': 1,
    },
];

Map<String, dynamic> setup() => {
  'revision': 3,
  'settings_fields': descriptors(),
  'hardware': [
    for (var i = 0; i < 4; i++)
      {
        'hardware_id': i,
        'label': ['볼트 머리', '스터드', '너트', '너트 홀'][i],
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
        'settings': options(),
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
        if (!(body!['cameras'] as List).any(
          (row) => row['serial'] == camera['serial'],
        )) {
          continue;
        }
        final row = (body['cameras'] as List).singleWhere(
          (row) => row['serial'] == camera['serial'],
        );
        camera['hardware_id'] = row['hardware_id'];
        camera['settings'] = row['settings'];
        if (row['clear_calibration'] == true) camera['calibration_name'] = '';
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
      home: Scaffold(
        body: CameraSetupPanel(
          settings: AppSettings(),
          api: api,
          canSave: canSave ?? () => true,
          pickCalibration: pick,
          onPreview: preview ?? (_) async {},
        ),
      ),
    ),
  );
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
    'expanded settings fit a narrow screen and calibration can be removed',
    (tester) async {
      final api = CameraApi();
      await open(tester, api);
      await tester.binding.setSurfaceSize(const Size(390, 900));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('촬영 설정').first);
      await tester.tap(find.text('촬영 설정').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('보정 파일 해제').first);
      await tester.tap(find.text('보정 파일 해제').first);
      await tester.tap(find.text('저장 및 적용'));
      await tester.pumpAndSettle();
      expect(api.saved!['cameras'][0]['clear_calibration'], true);
      expect(api.saved!['cameras'][0]['undistortion_enabled'], false);
      expect(api.data['cameras'][0]['calibration_name'], '');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('server options are editable and sent as typed values', (
    tester,
  ) async {
    final api = CameraApi();
    await open(tester, api);
    await tester.ensureVisible(find.text('촬영 설정').first);
    await tester.tap(find.text('촬영 설정').first);
    await tester.pumpAndSettle();
    final width = find.byKey(const ValueKey('option-S0-width-1'));
    await tester.ensureVisible(width);
    await tester.enterText(width, '1280');
    final exposure = find.byKey(const ValueKey('option-S0-exposure_us-1'));
    await tester.ensureVisible(exposure);
    await tester.enterText(exposure, '1250.5');
    await tester.tap(find.text('저장 및 적용'));
    await tester.pumpAndSettle();
    expect(api.saved!['cameras'][0]['settings']['width'], 1280);
    expect(api.saved!['cameras'][0]['settings']['exposure_us'], 1250.5);
  });
  testWidgets('invalid camera setting blocks saving and preserves the edit', (
    tester,
  ) async {
    final api = CameraApi();
    await open(tester, api);
    await tester.tap(find.text('촬영 설정').first);
    await tester.pumpAndSettle();
    final width = find.byKey(const ValueKey('option-S0-width-1'));
    await tester.ensureVisible(width);
    await tester.enterText(width, 'wrong');
    await tester.tap(find.text('저장 및 적용'));
    await tester.pumpAndSettle();
    expect(api.writes, 0);
    expect(find.textContaining('width 값을 확인'), findsOneWidget);
    expect(find.text('wrong'), findsOneWidget);
  });
  testWidgets('option descriptors and hardware labels come from the server', (
    tester,
  ) async {
    final api = CameraApi();
    api.data['hardware'].add({
      'hardware_id': 7,
      'camera_id': 'extra',
      'label': '추가 검사',
    });
    api.data['settings_fields'].add({
      'key': 'extra_option',
      'label': '추가 옵션',
      'type': 'integer',
      'nullable': true,
    });
    for (final row in api.data['cameras']) {
      row['settings']['extra_option'] = 42;
    }
    await open(tester, api);
    await choose(tester, 'S0', '추가 검사 (7)');
    await tester.tap(find.text('촬영 설정').first);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('option-S0-extra_option-1')),
      findsOneWidget,
    );
    await tester.tap(find.text('저장 및 적용'));
    await tester.pumpAndSettle();
    expect(api.saved!['cameras'][0]['hardware_id'], 7);
    expect(api.saved!['cameras'][0]['settings']['extra_option'], 42);
  });

  testWidgets(
    'only connected cameras are shown and preview uses logical camera id',
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
      expect(find.text('시리얼 S1'), findsNothing);
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
  testWidgets(
    'saving connected cameras does not submit or clear offline cameras',
    (tester) async {
      final api = CameraApi();
      api.data['cameras'][1]['discovered'] = false;
      await open(tester, api);
      await tester.tap(find.text('저장 및 적용'));
      await tester.pumpAndSettle();
      expect(api.saved!['cameras'], hasLength(1));
      expect(api.data['cameras'][1]['hardware_id'], 1);
    },
  );
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
