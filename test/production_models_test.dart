import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:catcheye_studio/models/production.dart';

Map<String, dynamic> captureJson({
  String origin = 'studio',
  String state = 'INSPECTING',
}) =>
    jsonDecode(
          jsonEncode({
            'capture_id': 'capture-1',
            'product_id': 1,
            'recipe_revision': 2,
            'recipe': {
              'name': '제품 A',
              'points': [
                {
                  'name': '포인트 1',
                  'inspection_id': 'bolt_head',
                  'expected_count': 3,
                  'candidate_confidence': 0.4,
                  'present_confidence': 0.5,
                  'geometry': null,
                },
              ],
            },
            'origin': origin,
            'state': state,
            'status': 'PENDING',
            'point_number': 1,
            'pending_cycle_id': null,
            'error': '',
            'results': [],
          }),
        )
        as Map<String, dynamic>;
Map<String, dynamic> plcJson() =>
    jsonDecode(
          '''{"state":"DISABLED","enabled":false,"host":"","port":0,"error":"","events":[],"rx_map":{},"tx_map":{}}''',
        )
        as Map<String, dynamic>;

void main() {
  test(
    'completed session preserves count mismatch and saved inspection evidence',
    () {
      final json = captureJson(state: 'COMPLETED')
        ..['point_number'] = 1
        ..['status'] = 'NG'
        ..['results'] = [
          <String, dynamic>{
            'cycle_id': 'cycle-1',
            'state': 'COMPLETED',
            'status': 'NG',
            'set_id': 'fastener',
            'group': 'bolt_stud',
            'inspection_ids': ['bolt_head'],
            'storage_path': 'bolt_stud/2026-09-11/cycle-1',
            'inspections': <String, dynamic>{
              'bolt_head': <String, dynamic>{
                'inspection_id': 'bolt_head',
                'camera_id': 'bolt_head_camera',
                'status': 'ABSENT',
                'reason': 'COUNT_MISMATCH',
                'expected_count': 3,
                'present_count': 2,
                'artifacts': <String, String>{'raw': 'bolt_head.png'},
              },
            },
          },
        ];
      final session = ProductionCapture.fromJson(json);
      expect(session.active, isFalse);
      expect(session.results.single.summaries.single.expectedCount, 3);
      expect(session.results.single.summaries.single.presentCount, 2);
      expect(session.results.single.capture.presentationStatus, 'NG');
      expect(
        session
            .results
            .single
            .capture
            .inspections['bolt_head']!
            .artifacts['raw'],
        'bolt_head.png',
      );
    },
  );
  test('equipment failure without inspection images preserves its cause', () {
    final record = ProductionCapture.fromJson(
      captureJson(state: 'COMPLETED')
        ..['status'] = 'NG'
        ..['results'] = [
          {
            'cycle_id': 'failed-1',
            'state': 'COMPLETED',
            'status': 'EQUIPMENT_ERROR',
            'reason': 'synthetic detector failure',
          },
        ],
    );
    expect(record.results.single.reason, 'synthetic detector failure');
    expect(record.results.single.summaries, isEmpty);
    expect(record.active, isFalse);
    expect(
      () => ProductionResult.fromJson({
        'cycle_id': 'bad',
        'state': 'COMPLETED',
        'status': 'OK',
      }),
      throwsFormatException,
    );
  });
  test('a completed capture releases the next independent request', () {
    expect(ProductionCapture.fromJson(captureJson()).active, isTrue);
    expect(
      ProductionCapture.fromJson(
        captureJson(state: 'COMPLETED')..['status'] = 'NG',
      ).active,
      isFalse,
    );
    final expanded = ProductionCapture.fromJson(
      captureJson()..['product_id'] = 255,
    );
    expect(expanded.productId, 255);
  });
  test(
    'hardware zero is preserved and historical records stay unspecified',
    () {
      expect(
        ProductionCapture.fromJson(
          captureJson()..['hardware_id'] = 0,
        ).hardwareId,
        0,
      );
      expect(ProductionCapture.fromJson(captureJson()).hardwareId, isNull);
      expect(PlcStatus.fromJson(plcJson()..['hardware_id'] = 3).hardwareId, 3);
      for (final invalid in [-1, 4, '0']) {
        expect(
          () => ProductionCapture.fromJson(
            captureJson()..['hardware_id'] = invalid,
          ),
          throwsFormatException,
        );
      }
    },
  );
  test('malformed capture and removed ACK state fail explicitly', () {
    for (final bad in [
      captureJson()..remove('capture_id'),
      captureJson()..['point_number'] = 0,
      captureJson()..['point_number'] = 2,
      captureJson()..['product_id'] = 256,
      captureJson()..['origin'] = 'unknown',
      captureJson(state: 'WAITING_ACK'),
    ]) {
      expect(() => ProductionCapture.fromJson(bad), throwsFormatException);
    }
  });
  test(
    'PLC allows absent initial words but rejects invalid mappings and values',
    () {
      final initial = PlcStatus.fromJson(plcJson());
      expect(initial.rxWords, isNull);
      expect(initial.word('rx', 0), isNull);
      expect(initial.canConnect, isFalse);
      for (final bad in [
        plcJson()..['rx_map'] = {'command': -1},
        plcJson()..['rx_words'] = [65536],
        plcJson()..remove('enabled'),
      ]) {
        expect(() => PlcStatus.fromJson(bad), throwsFormatException);
      }
    },
  );
  test('missing API version or session key fails explicitly', () {
    final json = <String, dynamic>{
      'api_version': 3,
      'control_epoch': 'boot-1',
      'capture': null,
      'error': '',
      'events': [],
    };
    expect(ProductionStatus.fromJson(json).capture, isNull);
    expect(
      () => ProductionStatus.fromJson({...json}..remove('capture')),
      throwsFormatException,
    );
    expect(
      () => ProductionStatus.fromJson({...json, 'api_version': 2}),
      throwsFormatException,
    );
  });
}
