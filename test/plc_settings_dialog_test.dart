import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:catcheye_studio/models/app_settings.dart';
import 'package:catcheye_studio/services/remote_production_api_service.dart';
import 'package:catcheye_studio/widgets/plc_settings_dialog.dart';

Map<String, dynamic> configuration() => {
  'enabled': false,
  'host': '',
  'port': null,
  'rx_words': null,
  'tx_words': null,
  'byte_order': 'little',
  'exchange_interval_ms': 100,
  'timeout_ms': 5000,
  'rx': <String, dynamic>{
    for (final name in [
      for (var i = 0; i < 4; i++) 'hardware_$i',
      for (var i = 1; i <= 5; i++) 'product_$i',
      'point_1',
      'point_2',
    ])
      name: null,
  },
  'tx': <String, dynamic>{
    for (final name in ['ok', 'ng', 'heartbeat']) name: null,
  },
};

class SettingsApi extends RemoteProductionApiService {
  Map<String, dynamic> config = configuration();
  Map<String, dynamic>? saved;
  bool conflict = false;
  int writes = 0;
  @override
  Future<Map<String, dynamic>> request(
    AppSettings settings,
    String method,
    String endpoint, [
    Map<String, dynamic>? body,
  ]) async {
    expect(endpoint, 'plc/config');
    if (method == 'PUT') {
      writes++;
      if (conflict) {
        throw const ProductionApiException(409, 'PLC_CONFIG_REVISION_CONFLICT');
      }
      saved = body;
      return {'revision': 5, 'config': body!['config']};
    }
    expect(method, 'GET');
    return {'revision': 4, 'config': jsonDecode(jsonEncode(config))};
  }
}

Finder field(String label) => find.widgetWithText(TextFormField, label);

Future<void> open(
  WidgetTester tester,
  SettingsApi api, {
  bool Function()? canSave,
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
              builder: (_) => PlcSettingsDialog(
                api: api,
                settings: AppSettings(),
                canSave: canSave ?? () => true,
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

void main() {
  testWidgets('hardware selection map is mandatory', (tester) async {
    final api = SettingsApi();
    api.config['rx'].remove('hardware_0');
    await open(tester, api);
    expect(find.textContaining('PLC 신호 매핑이 올바르지 않습니다'), findsOneWidget);
    expect(api.writes, 0);
  });

  testWidgets(
    'disabled draft saves address with revision and leaves unknown maps null',
    (tester) async {
      final api = SettingsApi();
      await open(tester, api);
      await tester.enterText(field('PLC IPv4 주소'), '192.168.1.50');
      await tester.enterText(field('PLC 포트'), '30000');
      await tester.tap(find.text('저장 및 적용'));
      await tester.pumpAndSettle();
      expect(api.saved!['base_revision'], 4);
      final saved = api.saved!['config'] as Map;
      expect(saved['host'], '192.168.1.50');
      expect(saved['port'], 30000);
      expect(saved['enabled'], false);
      expect(saved.containsKey('protocol'), isFalse);
      expect((saved['rx'] as Map).values.every((value) => value == null), true);
      expect(find.text('PLC 통신 설정'), findsNothing);
    },
  );

  testWidgets('enabling requires complete settings and rejects an invalid IP', (
    tester,
  ) async {
    final api = SettingsApi();
    await open(tester, api);
    await tester.tap(find.byType(Switch));
    await tester.enterText(field('PLC IPv4 주소'), '192.168.1.999');
    await tester.tap(find.text('저장 및 적용'));
    await tester.pumpAndSettle();
    expect(find.text('올바른 IPv4 주소를 입력하세요'), findsOneWidget);
    expect(api.writes, 0);
  });

  testWidgets('complete big endian map is sent without automatic connection', (
    tester,
  ) async {
    final api = SettingsApi();
    api.config.addAll({
      'enabled': true,
      'host': '192.168.1.50',
      'port': 30000,
      'rx_words': 23,
      'tx_words': 23,
      'byte_order': 'big',
    });
    for (final direction in ['rx', 'tx']) {
      final map = api.config[direction] as Map<String, dynamic>;
      var index = 0;
      for (final key in map.keys.toList()) {
        map[key] = index++;
      }
    }
    await open(tester, api);
    await tester.tap(find.text('저장 및 적용'));
    await tester.pumpAndSettle();
    expect(api.saved!['config'], api.config);
    expect(api.writes, 1);
  });

  testWidgets('duplicate signal positions cannot be saved', (tester) async {
    final api = SettingsApi();
    api.config['rx_words'] = 23;
    api.config['rx']['hardware_0'] = 0;
    api.config['rx']['product_1'] = 0;
    await open(tester, api);
    await tester.tap(find.text('저장 및 적용'));
    await tester.pumpAndSettle();
    expect(find.textContaining('신호 위치가 중복'), findsOneWidget);
    expect(api.writes, 0);
  });

  testWidgets('adding product 6 preserves product 5 and point 2 offsets', (
    tester,
  ) async {
    final api = SettingsApi();
    api.config['rx_words'] = 23;
    api.config['rx']['product_5'] = 4;
    api.config['rx']['point_2'] = 6;
    api.config['rx']['hardware_0'] = 22;
    await open(tester, api);
    final number = find.byKey(const ValueKey('selection-number'));
    await tester.ensureVisible(number);
    await tester.enterText(number, '6');
    await tester.ensureVisible(find.text('선택 신호 추가'));
    await tester.tap(find.text('선택 신호 추가'));
    await tester.pumpAndSettle();
    final newField = field('제품 6 선택 (rx.product_6)');
    await tester.ensureVisible(newField);
    await tester.enterText(newField, '21');
    await tester.tap(find.text('저장 및 적용'));
    await tester.pumpAndSettle();
    final rx = api.saved!['config']['rx'] as Map;
    expect(rx['product_5'], 4);
    expect(rx['point_2'], 6);
    expect(rx['hardware_0'], 22);
    expect(rx['product_6'], 21);
    expect(rx.keys.any((key) => key.toString().contains('bit')), false);
  });

  testWidgets('point signals can be added and removed without renumbering', (
    tester,
  ) async {
    final api = SettingsApi();
    await open(tester, api);
    final kind = find.byKey(const ValueKey('selection-kind'));
    await tester.ensureVisible(kind);
    await tester.tap(kind);
    await tester.pumpAndSettle();
    await tester.tap(find.text('포인트').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('selection-number')), '3');
    await tester.ensureVisible(find.text('선택 신호 추가'));
    await tester.tap(find.text('선택 신호 추가'));
    await tester.pumpAndSettle();
    expect(field('포인트 3 선택 (rx.point_3)'), findsOneWidget);
    final remove = find.byKey(const ValueKey('remove-point_1'));
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장 및 적용'));
    await tester.pumpAndSettle();
    final rx = api.saved!['config']['rx'] as Map;
    expect(rx.containsKey('point_1'), false);
    expect(rx.containsKey('point_2'), true);
    expect(rx.containsKey('point_3'), true);
  });

  testWidgets('conflict preserves edits and does not retry', (tester) async {
    final api = SettingsApi()..conflict = true;
    await open(tester, api);
    await tester.enterText(field('PLC IPv4 주소'), '192.168.1.99');
    await tester.tap(find.text('저장 및 적용'));
    await tester.pumpAndSettle();
    expect(find.textContaining('PLC_CONFIG_REVISION_CONFLICT'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(field('PLC IPv4 주소')).controller!.text,
      '192.168.1.99',
    );
    expect(api.writes, 1);
  });

  testWidgets('a session started during editing blocks save', (tester) async {
    final api = SettingsApi();
    var idle = true;
    await open(tester, api, canSave: () => idle);
    idle = false;
    await tester.tap(find.text('저장 및 적용'));
    await tester.pumpAndSettle();
    expect(find.textContaining('촬영이 끝나고'), findsOneWidget);
    expect(api.writes, 0);
  });
}
