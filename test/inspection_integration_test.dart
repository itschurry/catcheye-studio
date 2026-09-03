import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:catcheye_studio/models/app_settings.dart';
import 'package:catcheye_studio/models/station_viewer_layout.dart';
import 'package:catcheye_studio/providers/settings_provider.dart';
import 'package:catcheye_studio/screens/inspection_results_screen.dart';
import 'package:catcheye_studio/services/remote_capture_api_service.dart';
import 'package:catcheye_studio/services/frame_receiver_service.dart';
import 'package:catcheye_studio/services/remote_reference_api_service.dart';
import 'package:catcheye_studio/services/reference_credential_store.dart';

void main() {
  setUpAll(MediaKit.ensureInitialized);

  test('station targets use explicit capture endpoints', () {
    expect(StationCaptureTarget.values.map((target) => target.path), [
      'bolt-stud',
      'nut',
      'all',
    ]);
  });

  test(
    'station status and result preserve queue and measurement semantics',
    () {
      final status = StationCaptureStatus.fromJson(const {
        'set_id': 'fastener',
        'ready': true,
        'busy': true,
        'pending_count': 1,
        'max_pending_captures': 3,
        'active_cycle_id': 'cycle-a',
        'capture_count': 4,
        'groups': {
          'nut': ['nut_hole_alignment'],
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
      expect(status.setId, 'fastener');
      expect(status.captureTargets, StationCaptureTarget.values);
      expect(status.maxPendingCaptures, 3);
      expect(status.cameras['nut_hole_camera']?.open, isFalse);

      final result = StationCaptureResult.fromJson(const {
        'cycle_id': 'cycle-a',
        'state': 'COMPLETED',
        'status': 'NG',
        'set_id': 'nut',
        'group': 'nut',
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

  test('viewer source accepts legacy singular and multi-camera responses', () {
    final legacy = StationViewerSource.fromJson(const {
      'camera_id': 'bolt_head_camera',
      'cameras': ['bolt_head_camera', 'nut_camera'],
    });
    expect(legacy.cameraIds, ['bolt_head_camera']);

    final multi = StationViewerSource.fromJson(const {
      'camera_id': 'ignored_legacy_value',
      'camera_ids': ['bolt_head_camera', 'nut_camera'],
      'cameras': ['bolt_head_camera', 'nut_camera'],
    });
    expect(multi.cameraIds, ['bolt_head_camera', 'nut_camera']);
    expect(
      () => StationViewerSource.fromJson(const {
        'camera_ids': ['nut_camera', 'nut_camera'],
        'cameras': ['nut_camera'],
      }),
      throwsFormatException,
    );
  });

  test('station stream key keeps camera identity for grid placement', () {
    final frame = ViewerStreamFrame.fromPayload(
      name: 'nut_camera',
      kind: 'camera',
      encoding: ViewerStreamEncoding.jpeg,
      payloadIndex: 1,
      payloadBytes: Uint8List.fromList(const [0xff, 0xd8, 0xff, 0xd9]),
      pointCount: 0,
      stride: 1,
      streamKey: 'nut_camera',
    );
    expect(frame.key, 'nut_camera');
    expect(frame.name, 'nut_camera');
    expect(frame.receivedAt.isAfter(DateTime(2020)), isTrue);
  });

  test('station layout keeps sparse camera slot positions', () {
    final slots = reconcileStationCameraSlots(
      layout: StationViewerLayout.twoByTwo,
      preferredSlots: const ['bolt_head_camera', '', 'nut_camera', ''],
      activeCameraIds: const ['bolt_head_camera', 'nut_camera'],
    );

    expect(slots, const ['bolt_head_camera', '', 'nut_camera', '']);
  });

  test('station layout survives reconnect with fewer active cameras', () {
    const selectedLayout = StationViewerLayout.twoByTwo;
    final reconnectLayout = selectedLayout.accommodate(2);
    final slots = reconcileStationCameraSlots(
      layout: reconnectLayout,
      preferredSlots: const ['bolt_head_camera', '', 'nut_camera', ''],
      activeCameraIds: const ['nut_camera', 'bolt_head_camera'],
    );

    expect(reconnectLayout, StationViewerLayout.twoByTwo);
    expect(slots, const ['bolt_head_camera', '', 'nut_camera', '']);
  });

  test('station layout expands when runtime activates more cameras', () {
    final layout = StationViewerLayout.oneByOne.accommodate(3);
    final slots = reconcileStationCameraSlots(
      layout: layout,
      preferredSlots: const ['bolt_head_camera'],
      activeCameraIds: const ['bolt_head_camera', 'nut_camera', 'stud_camera'],
    );

    expect(layout, StationViewerLayout.twoByTwo);
    expect(slots, const ['bolt_head_camera', 'nut_camera', 'stud_camera', '']);
  });

  test('station layout and sparse slots persist across app reloads', () async {
    SharedPreferences.setMockInitialValues(const {});
    final provider = SettingsProvider();
    await provider.updateStationViewerLayout(
      layout: StationViewerLayout.twoByTwo,
      cameraSlots: const ['bolt_head_camera', '', 'nut_camera', ''],
    );

    final reloaded = await SettingsProvider.load();

    expect(reloaded.settings.stationViewerLayout, StationViewerLayout.twoByTwo);
    expect(reloaded.settings.stationViewerCameraSlots, const [
      'bolt_head_camera',
      '',
      'nut_camera',
      '',
    ]);
  });

  test('station stream freshness advances only with frame sequence', () async {
    final receiver = FrameReceiverService();
    addTearDown(receiver.dispose);
    receiver.setExpectedCameraIds(const ['stud_camera']);

    void sendFrame(int sequence) {
      receiver.processWebSocketDataForTest(
        jsonEncode({
          'type': 'viewer_frame',
          'metadata': {
            'camera_ids': ['stud_camera'],
          },
          'streams': [
            {
              'name': 'stud_camera',
              'kind': 'camera',
              'encoding': 'jpeg',
              'payload_index': 0,
              'payload_size': 3,
              'frame_sequence': sequence,
            },
          ],
        }),
      );
      receiver.processWebSocketDataForTest(Uint8List.fromList(const [1, 2, 3]));
    }

    sendFrame(7);
    final firstReceivedAt = receiver.streams['stud_camera']!.receivedAt;
    await Future<void>.delayed(const Duration(milliseconds: 2));
    sendFrame(7);
    expect(receiver.streams['stud_camera']!.receivedAt, firstReceivedAt);

    await Future<void>.delayed(const Duration(milliseconds: 2));
    sendFrame(8);
    expect(receiver.streams['stud_camera']!.frameSequence, 8);
    expect(
      receiver.streams['stud_camera']!.receivedAt.isAfter(firstReceivedAt),
      isTrue,
    );
  });

  test('station selection change consumes the current payload bundle', () {
    final receiver = FrameReceiverService();
    addTearDown(receiver.dispose);
    receiver.setExpectedCameraIds(const ['camera_a', 'camera_b']);
    receiver.processWebSocketDataForTest(
      jsonEncode({
        'type': 'viewer_frame',
        'metadata': {
          'camera_ids': ['camera_a', 'camera_b'],
        },
        'streams': [
          {
            'name': 'camera_a',
            'kind': 'camera',
            'encoding': 'jpeg',
            'payload_index': 0,
            'payload_size': 1,
            'frame_sequence': 1,
          },
          {
            'name': 'camera_b',
            'kind': 'camera',
            'encoding': 'jpeg',
            'payload_index': 1,
            'payload_size': 1,
            'frame_sequence': 1,
          },
        ],
      }),
    );
    receiver.processWebSocketDataForTest(Uint8List.fromList(const [1]));

    receiver.setExpectedCameraIds(const ['camera_b']);
    receiver.processWebSocketDataForTest(Uint8List.fromList(const [2]));

    expect(receiver.streams.keys, const ['camera_b']);
    expect(receiver.streams.containsKey('camera'), isFalse);
    expect(receiver.streams['camera_b']!.payloadBytes, const [2]);
  });

  test(
    'station result archive retains completed results missing from server',
    () {
      final retained = StationCaptureResult.fromJson(const {
        'cycle_id': 'completed-before-restart',
        'state': 'COMPLETED',
        'status': 'OK',
        'requested_at_ms': 100,
        'inspection_ids': [],
        'inspections': {},
      });
      final running = StationCaptureResult.fromJson(const {
        'cycle_id': 'running-before-restart',
        'state': 'RUNNING',
        'requested_at_ms': 200,
        'inspection_ids': [],
      });

      final merged = mergeStationResultArchive([retained, running], const []);

      expect(merged.map((result) => result.cycleId), [
        'completed-before-restart',
      ]);
    },
  );

  test('station result list parses retained cycles', () {
    final list = StationCaptureResultList.fromJson(const {
      'results': [
        {
          'cycle_id': 'cycle-2',
          'state': 'RUNNING',
          'inspection_ids': ['presence'],
        },
        {
          'cycle_id': 'cycle-1',
          'state': 'COMPLETED',
          'status': 'OK',
          'inspection_ids': [],
          'inspections': {},
        },
      ],
    });

    expect(list.results.map((result) => result.cycleId), [
      'cycle-2',
      'cycle-1',
    ]);
    expect(list.results.first.state, StationCycleState.running);
    expect(list.results.last.presentationStatus, 'OK');
  });

  test('multi-camera source selection sends ordered camera_ids', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final subscription = server.listen((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/viewer/source');
      final body = await utf8.decoder.bind(request).join();
      expect(jsonDecode(body), const {
        'camera_ids': ['bolt_head_camera', 'nut_camera'],
      });
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'camera_ids': ['bolt_head_camera', 'nut_camera'],
          'cameras': ['bolt_head_camera', 'nut_camera'],
        }),
      );
      await request.response.close();
    });
    addTearDown(subscription.cancel);
    final service = RemoteCaptureApiService();
    addTearDown(service.close);
    final settings = AppSettings(
      detectorBaseUrl: 'http://${server.address.host}:${server.port}',
    );

    final source = await service.setViewerSources(settings, const [
      'bolt_head_camera',
      'nut_camera',
    ]);
    expect(source.cameraIds, ['bolt_head_camera', 'nut_camera']);
  });

  test('station POST is not replayed after queue-full response', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requestCount = 0;
    final subscription = server.listen((request) async {
      requestCount++;
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/capture/bolt-stud');
      final body = await utf8.decoder.bind(request).join();
      expect(body, isEmpty);
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
        target: StationCaptureTarget.boltStud,
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

  test(
    'each station target posts once to its fixed route without a selector',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final paths = <String>[];
      final subscription = server.listen((request) async {
        paths.add(request.uri.path);
        expect(request.method, 'POST');
        expect(await utf8.decoder.bind(request).join(), isEmpty);
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'accepted': true,
            'cycle_id': 'cycle-${paths.length}',
            'error': '',
          }),
        );
        await request.response.close();
      });
      addTearDown(subscription.cancel);
      final service = RemoteCaptureApiService();
      addTearDown(service.close);
      final settings = AppSettings(
        detectorBaseUrl: 'http://${server.address.host}:${server.port}',
      );
      for (final target in StationCaptureTarget.values) {
        final accepted = await service.requestStationCapture(
          settings,
          target: target,
        );
        expect(accepted.accepted, isTrue);
        expect(accepted.cycleId, 'cycle-${paths.length}');
      }
      expect(paths, [
        '/api/capture/bolt-stud',
        '/api/capture/nut',
        '/api/capture/all',
      ]);
    },
  );

  test(
    'Capture app keeps its endpoint while single Inspect uses all',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final paths = <String>[];
      final subscription = server.listen((request) async {
        paths.add(request.uri.path);
        expect(request.method, 'POST');
        expect(await utf8.decoder.bind(request).join(), isEmpty);
        request.response.headers.contentType = ContentType.json;
        request.response.write('{}');
        await request.response.close();
      });
      addTearDown(subscription.cancel);
      final service = RemoteCaptureApiService();
      addTearDown(service.close);
      for (final kind in [
        RemoteDeviceKind.capture,
        RemoteDeviceKind.inspection,
      ]) {
        await service.requestCapture(
          AppSettings(
            detectorBaseUrl: 'http://${server.address.host}:${server.port}',
            remoteDeviceKind: kind,
          ),
        );
      }
      expect(paths, ['/api/capture/request', '/api/capture/all']);
    },
  );

  for (final code in [HttpStatus.notFound, HttpStatus.serviceUnavailable]) {
    test(
      'station HTTP $code does not retry a different capture route',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final paths = <String>[];
        final subscription = server.listen((request) async {
          paths.add(request.uri.path);
          await request.drain<void>();
          request.response.statusCode = code;
          request.response.write('{}');
          await request.response.close();
        });
        addTearDown(subscription.cancel);
        final service = RemoteCaptureApiService();
        addTearDown(service.close);
        await expectLater(
          service.requestStationCapture(
            AppSettings(
              detectorBaseUrl: 'http://${server.address.host}:${server.port}',
            ),
            target: StationCaptureTarget.nut,
          ),
          throwsA(
            isA<RemoteCaptureApiException>().having(
              (error) => error.statusCode,
              'statusCode',
              code,
            ),
          ),
        );
        expect(paths, ['/api/capture/nut']);
      },
    );
  }

  test('reference status parses capabilities and camera class mapping', () {
    final status = ReferenceApiStatus.fromJson(const {
      'api_version': 1,
      'capabilities': {
        'reference_capture': true,
        'reference_revisions': true,
        'model_build': false,
        'model_activation': false,
      },
      'device_state': 'RUNNING',
      'active_model_id': 'model_initial',
      'camera_classes': {
        'stud_camera': ['stud'],
        'nut_hole_camera': ['nut_hole', 'plain_hole'],
      },
    });

    expect(status.apiVersion, 1);
    expect(status.isRunning, isTrue);
    expect(status.capabilities.hasReferenceManagement, isTrue);
    expect(status.cameraClasses['nut_hole_camera'], ['nut_hole', 'plain_hole']);
  });

  test('reference API captures image and creates immutable revision', () async {
    const token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final seenRequestIds = <String>[];
    final subscription = server.listen((request) async {
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer $token',
      );
      final path = request.uri.path;
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'POST' && path == '/api/reference/captures') {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(body['camera_id'], 'stud_camera');
        seenRequestIds.add(body['request_id'] as String);
        request.response.statusCode = HttpStatus.accepted;
        request.response.write(
          jsonEncode({'capture_id': 'refcap_123', 'state': 'QUEUED'}),
        );
      } else if (request.method == 'GET' &&
          path == '/api/reference/captures/refcap_123') {
        request.response.write(
          jsonEncode({
            'capture_id': 'refcap_123',
            'state': 'READY',
            'image': {
              'image_id': 'img_123',
              'camera_id': 'stud_camera',
              'camera_serial': '40490627',
              'width': 1280,
              'height': 800,
              'captured_at_ms': 1788415200000,
              'source_timestamp_ms': 123456,
              'url': '/api/reference/images/img_123',
              'sha256': 'image-hash',
            },
            'error': null,
          }),
        );
      } else if (request.method == 'GET' &&
          path == '/api/reference/images/img_123') {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(const [0x89, 0x50, 0x4e, 0x47]);
      } else if (request.method == 'POST' &&
          path == '/api/reference/revisions') {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        seenRequestIds.add(body['request_id'] as String);
        expect(body['base_revision_id'], 'refrev_initial');
        expect(body['entries'], [
          {
            'class_name': 'stud',
            'image_id': 'img_123',
            'boxes': [
              [475, 625, 580, 755],
            ],
          },
        ]);
        request.response.statusCode = HttpStatus.created;
        request.response.write(
          jsonEncode({
            'revision_id': 'refrev_123',
            'base_revision_id': 'refrev_initial',
            'created_at_ms': 1788415300000,
            'entries': [
              {
                'class_name': 'stud',
                'image_id': 'img_123',
                'image_url': '/api/reference/images/img_123',
                'width': 1280,
                'height': 800,
                'boxes': [
                  [475, 625, 580, 755],
                ],
                'context_ratio': 0.1,
              },
            ],
          }),
        );
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    addTearDown(subscription.cancel);

    final settings = AppSettings(
      detectorBaseUrl: 'http://${server.address.host}:${server.port}',
    );
    final service = RemoteReferenceApiService();
    addTearDown(service.close);

    final accepted = await service.requestCapture(
      settings,
      'stud_camera',
      bearerToken: token,
    );
    expect(accepted.state, ReferenceCaptureState.queued);
    final ready = await service.fetchCapture(
      settings,
      accepted.captureId,
      bearerToken: token,
    );
    expect(ready.image?.imageId, 'img_123');
    expect(
      await service.fetchImage(settings, ready.image!, bearerToken: token),
      [0x89, 0x50, 0x4e, 0x47],
    );
    final revision = await service.createRevision(
      settings,
      baseRevisionId: 'refrev_initial',
      className: 'stud',
      imageId: 'img_123',
      boxes: const [ReferenceBox(475, 625, 580, 755)],
      bearerToken: token,
    );
    expect(revision.revisionId, 'refrev_123');
    expect(revision.entries.single.boxes.single.toJson(), [475, 625, 580, 755]);
    expect(seenRequestIds, hasLength(2));
    for (final requestId in seenRequestIds) {
      expect(
        requestId,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    }
  });

  test('reference boxes validate original image coordinates', () {
    expect(const ReferenceBox(0, 0, 1280, 800).isValidFor(1280, 800), isTrue);
    expect(const ReferenceBox(-1, 0, 10, 10).isValidFor(1280, 800), isFalse);
    expect(const ReferenceBox(10, 10, 10, 20).isValidFor(1280, 800), isFalse);
    expect(const ReferenceBox(0, 0, 1281, 800).isValidFor(1280, 800), isFalse);
  });

  test(
    'model build and activation requests require explicit confirmations',
    () async {
      const token = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final subscription = server.listen((request) async {
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer $token',
        );
        request.response.headers.contentType = ContentType.json;
        if (request.method == 'POST' &&
            request.uri.path == '/api/model/builds') {
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          expect(body['reference_revision_id'], 'refrev_123');
          expect(body['maintenance_confirmed'], isTrue);
          request.response.statusCode = HttpStatus.accepted;
          request.response.write(
            jsonEncode({
              'build_id': 'build_123',
              'state': 'SUCCEEDED',
              'reference_revision_id': 'refrev_123',
              'candidate_model_id': 'model_123',
              'created_at_ms': 1788415400000,
              'validation': {
                'technical_passed': true,
                'production_approved': false,
                'results': [
                  {
                    'source': 'prompt',
                    'class_name': 'stud',
                    'status': 'PRESENT',
                    'reason': 'TARGET_CONFIRMED',
                    'latency_ms': 18.2,
                  },
                ],
              },
              'error': null,
            }),
          );
        } else if (request.method == 'GET' &&
            request.uri.path == '/api/models') {
          expect(request.uri.queryParameters['limit'], '100');
          request.response.write(
            jsonEncode({
              'models': [
                {
                  'model_id': 'model_123',
                  'reference_revision_id': 'refrev_123',
                  'created_at_ms': 1788415400000,
                  'engine_sha256': 'engine-hash',
                  'metadata_sha256': 'metadata-hash',
                  'technical_passed': true,
                  'review_required': true,
                  'build_id': 'build_123',
                  'validation': {
                    'technical_passed': true,
                    'production_approved': false,
                    'results': [],
                  },
                },
              ],
              'next_cursor': null,
            }),
          );
        } else if (request.method == 'POST' &&
            request.uri.path == '/api/model/activations') {
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          expect(body['model_id'], 'model_123');
          expect(body['expected_active_model_id'], 'model_initial');
          expect(body['review_confirmed'], isTrue);
          request.response.statusCode = HttpStatus.accepted;
          request.response.write(
            jsonEncode({
              'activation_id': 'activation_123',
              'state': 'SUCCEEDED',
              'requested_model_id': 'model_123',
              'previous_model_id': 'model_initial',
              'active_model_id': 'model_123',
              'created_at_ms': 1788415500000,
              'error': null,
            }),
          );
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });
      addTearDown(subscription.cancel);
      final settings = AppSettings(
        detectorBaseUrl: 'http://${server.address.host}:${server.port}',
      );
      final service = RemoteReferenceApiService();
      addTearDown(service.close);

      final build = await service.requestModelBuild(
        settings,
        referenceRevisionId: 'refrev_123',
        bearerToken: token,
      );
      expect(build.state, ModelBuildState.succeeded);
      expect(build.validation?.productionApproved, isFalse);
      final models = await service.fetchModels(
        settings,
        bearerToken: token,
        limit: 100,
      );
      expect(models.models.single.modelId, 'model_123');
      final activation = await service.requestModelActivation(
        settings,
        modelId: 'model_123',
        expectedActiveModelId: 'model_initial',
        bearerToken: token,
      );
      expect(activation.state, ModelActivationState.succeeded);
      expect(activation.activeModelId, 'model_123');
    },
  );

  test(
    'management tokens are isolated by API origin in credential storage',
    () async {
      final backend = _MemoryCredentialBackend();
      final store = ReferenceCredentialStore(backend: backend);
      final first = AppSettings(detectorBaseUrl: 'http://station-a:8090');
      final second = AppSettings(detectorBaseUrl: 'https://station-a:8090');
      const token = 'cccccccccccccccccccccccccccccccc';

      await store.writeToken(first, token);
      expect(await store.readToken(first), token);
      expect(await store.readToken(second), isNull);
      await store.deleteToken(first);
      expect(await store.readToken(first), isNull);
      await expectLater(
        store.writeToken(first, 'too-short'),
        throwsFormatException,
      );
    },
  );
}

class _MemoryCredentialBackend implements SecureCredentialBackend {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
