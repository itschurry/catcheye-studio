import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:catcheye_studio/models/app_settings.dart';
import 'package:catcheye_studio/services/remote_capture_api_service.dart';

void main() {
  test(
    'station selector omits empty selectors and sends exactly one selector',
    () {
      expect(const StationCaptureSelector.all().toJson(), isEmpty);
      expect(StationCaptureSelector.group(' a ').toJson(), const {
        'group': 'a',
      });
      expect(
        StationCaptureSelector.inspection('nut_hole_alignment').toJson(),
        const {'inspection_id': 'nut_hole_alignment'},
      );
      expect(() => StationCaptureSelector.group(''), throwsFormatException);
    },
  );

  test(
    'station status and result preserve queue and measurement semantics',
    () {
      final status = StationCaptureStatus.fromJson(const {
        'ready': true,
        'busy': true,
        'pending_count': 1,
        'max_pending_captures': 3,
        'active_cycle_id': 'cycle-a',
        'capture_count': 4,
        'groups': {
          'a': ['nut_hole_alignment'],
        },
        'cameras': {
          'nut_hole_camera': {
            'open': false,
            'frame_sequence': 42,
            'last_error': '',
          },
        },
        'last_result': null,
        'last_error': '',
      });
      expect(status.pendingCount, 1);
      expect(status.maxPendingCaptures, 3);
      expect(status.cameras['nut_hole_camera']?.open, isFalse);

      final result = StationCaptureResult.fromJson(const {
        'cycle_id': 'cycle-a',
        'state': 'COMPLETED',
        'status': 'NG',
        'set_id': 'set-b',
        'group': 'a',
        'inspection_ids': ['nut_hole_alignment'],
        'requested_at_ms': 1000,
        'started_at_ms': 1100,
        'finished_at_ms': 1200,
        'inspections': {
          'nut_hole_alignment': {
            'inspection_id': 'nut_hole_alignment',
            'camera_id': 'nut_hole_camera',
            'camera_serial': 'serial',
            'source_timestamp_ms': 123456,
            'status': 'NG',
            'reason': 'SHAPE_LIMIT_FAILED',
            'latency_ms': 18.432,
            'detections': [
              {'class_name': 'nut_hole'},
            ],
            'measurements': {
              'center_distance_px': 3.2,
              'quality_metrics': {'relative_eccentricity': 0.12},
              'quality_limits': {'relative_eccentricity': 0.08},
              'failed_metrics': ['relative_eccentricity'],
            },
          },
        },
        'artifact_error': '',
      });
      final inspection = result.inspections['nut_hole_alignment']!;
      expect(result.presentationStatus, 'NG');
      expect(inspection.detections, isNotEmpty);
      expect(inspection.status, 'NG');
      expect(inspection.failedMetrics, ['relative_eccentricity']);
      expect(
        (inspection.measurements['quality_metrics']
            as Map)['relative_eccentricity'],
        0.12,
      );
    },
  );

  test('artifact failure is presented as equipment fault', () {
    final result = StationCaptureResult.fromJson(const {
      'cycle_id': 'cycle-storage',
      'state': 'COMPLETED',
      'status': 'NG',
      'inspection_ids': [],
      'inspections': {},
      'artifact_error': 'disk full',
    });
    expect(result.isEquipmentFault, isTrue);
    expect(result.presentationStatus, 'EQUIPMENT_ERROR');
  });

  test('cycle presentation applies documented aggregate priority', () {
    final result = StationCaptureResult.fromJson(const {
      'cycle_id': 'cycle-recheck',
      'state': 'COMPLETED',
      'status': 'OK',
      'inspection_ids': ['presence', 'shape'],
      'inspections': {
        'presence': {
          'inspection_id': 'presence',
          'status': 'PRESENT',
          'reason': 'TARGET_CONFIRMED',
          'detections': [],
          'measurements': {},
        },
        'shape': {
          'inspection_id': 'shape',
          'status': 'RECHECK',
          'reason': 'LIMIT_MISSING',
          'detections': [],
          'measurements': {},
        },
      },
      'artifact_error': '',
    });
    expect(result.presentationStatus, 'RECHECK');
  });

  test('station POST is not replayed after queue-full response', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requestCount = 0;
    final subscription = server.listen((request) async {
      requestCount++;
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/capture/request');
      final body = await utf8.decoder.bind(request).join();
      expect(jsonDecode(body), const {'group': 'a'});
      request.response.statusCode = HttpStatus.conflict;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': 'queue full'}));
      await request.response.close();
    });
    addTearDown(subscription.cancel);
    final service = RemoteCaptureApiService();
    addTearDown(service.close);
    final settings = AppSettings(
      detectorBaseUrl: 'http://${server.address.host}:${server.port}',
    );

    await expectLater(
      service.requestStationCapture(
        settings,
        selector: StationCaptureSelector.group('a'),
      ),
      throwsA(
        isA<RemoteCaptureApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          HttpStatus.conflict,
        ),
      ),
    );
    expect(requestCount, 1);
  });
}
