import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:catcheye_studio/models/production.dart';

Map<String, dynamic> sessionJson({
  String origin = 'studio',
  String state = 'READY',
}) =>
    jsonDecode(
          jsonEncode({
            'session_id': 'session-1',
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
            'step': 0,
            'pending_cycle_id': null,
            'result_request_id': null,
            'error': '',
            'results': [],
          }),
        )
        as Map<String, dynamic>;
Map<String, dynamic> plcJson() =>
    jsonDecode(
          '''{"state":"DISABLED","enabled":false,"host":"","port":0,"protocol":"inspect_words_v1","error":"","result_acknowledged":false,"events":[],"rx_map":{},"tx_map":{}}''',
        )
        as Map<String, dynamic>;

void main() {
  test(
    'completed session preserves count mismatch and saved inspection evidence',
    () {
      final json = sessionJson(state: 'COMPLETED')
        ..['step'] = 1
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
      final session = ProductionSession.fromJson(json);
      expect(session.active, isFalse);
      expect(session.canCapture, isFalse);
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
  test('manual controls honor state, pending capture and PLC ownership', () {
    final ready = ProductionSession.fromJson(sessionJson());
    expect(ready.canCapture, isTrue);
    expect(ready.nextPoint!.expectedCount, 3);
    expect(ready.canEnd, isFalse);
    final plc = ProductionSession.fromJson(sessionJson(origin: 'plc'));
    expect(plc.canCapture, isFalse);
    expect(plc.canAbort, isFalse);
    expect(
      ProductionSession.fromJson(
        sessionJson(origin: 'plc', state: 'FAULT'),
      ).canAbort,
      isTrue,
    );
    final pending = ProductionSession.fromJson(
      sessionJson(state: 'INSPECTING')..['pending_cycle_id'] = 'cycle-1',
    );
    expect(pending.canCapture, isFalse);
    expect(pending.canAbort, isFalse);
    final ack = ProductionSession.fromJson(
      sessionJson(state: 'WAITING_ACK')..['result_request_id'] = 'result-1',
    );
    expect(ack.canAcknowledge, isTrue);
  });
  test('malformed session is rejected before it can enable a command', () {
    for (final bad in [
      sessionJson()..remove('session_id'),
      sessionJson()..['state'] = 'UNKNOWN',
      sessionJson()..['step'] = 2,
      sessionJson()..['origin'] = 'unknown',
      sessionJson(state: 'WAITING_ACK'),
    ]) {
      expect(() => ProductionSession.fromJson(bad), throwsFormatException);
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
      'api_version': 1,
      'control_epoch': 'boot-1',
      'session': null,
      'error': '',
      'events': [],
    };
    expect(ProductionStatus.fromJson(json).session, isNull);
    expect(
      () => ProductionStatus.fromJson({...json}..remove('session')),
      throwsFormatException,
    );
    expect(
      () => ProductionStatus.fromJson({...json, 'api_version': 2}),
      throwsFormatException,
    );
  });
}
