import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:catcheye_studio/main.dart' as app;
import 'package:catcheye_studio/models/app_settings.dart';
import 'package:catcheye_studio/providers/settings_provider.dart';
import 'package:catcheye_studio/services/remote_capture_image_api_service.dart';
import 'package:catcheye_studio/services/remote_pick_api_service.dart';

void main() {
  test('remote device kind parses hss', () {
    expect(RemoteDeviceKind.fromApiValue('hss'), RemoteDeviceKind.hss);
    expect(RemoteDeviceKind.hss.apiValue, 'hss');
    expect(RemoteDeviceKind.hss.label, 'HSS');
  });

  test('remote device kind parses capture', () {
    expect(RemoteDeviceKind.fromApiValue('capture'), RemoteDeviceKind.capture);
    expect(RemoteDeviceKind.capture.apiValue, 'capture');
    expect(RemoteDeviceKind.capture.label, 'Capture');
  });

  test('legacy guard setting migrates to hss', () async {
    SharedPreferences.setMockInitialValues(const {
      'settings.remoteDeviceKind': 'guard',
    });

    final provider = await SettingsProvider.load();
    final prefs = await SharedPreferences.getInstance();

    expect(provider.settings.remoteDeviceKind, RemoteDeviceKind.hss);
    expect(prefs.getString('settings.remoteDeviceKind'), 'hss');
    expect(() => RemoteDeviceKind.fromApiValue('guard'), throwsFormatException);
  });

  test('capture images navigation is capture only', () {
    expect(app.visibleAppItemIndexes(RemoteDeviceKind.capture, false), const [
      0,
      5,
      1,
      3,
    ]);
    expect(app.visibleAppItemIndexes(RemoteDeviceKind.capture, true), const [
      0,
      5,
      1,
    ]);
    expect(
      app.visibleAppItemIndexes(RemoteDeviceKind.hss, false).contains(5),
      isFalse,
    );
    expect(
      app.visibleAppItemIndexes(RemoteDeviceKind.pick, false).contains(5),
      isFalse,
    );
  });

  test('capture image JSON models parse list response', () {
    final dates = CaptureDatesResponse.fromJson(const {
      'storage': {
        'path': '/home/user/catcheye-capture/captures',
        'total_bytes': 250000000000,
        'available_bytes': 180000000000,
        'used_bytes': 70000000000,
        'used_percent': 28.0,
        'capture_bytes': 1234567890,
        'capture_count': 312,
      },
      'dates': [
        {'date': '2026-07-03', 'count': 2},
      ],
    });
    final list = CaptureImageList.fromJson(const {
      'date': '2026-07-03',
      'items': [
        {
          'filename': '142530_015_000012.jpg',
          'captured_at': '2026-07-03T14:25:30.015+09:00',
          'sequence': 12,
          'size_bytes': 184223,
          'width': 2304,
          'height': 1296,
          'url': '/api/captures/file/2026-07-03/142530_015_000012.jpg',
        },
      ],
      'next_cursor': '',
    });

    expect(dates.storage?.availableBytes, 180000000000);
    expect(dates.storage?.captureBytes, 1234567890);
    expect(dates.storage?.captureCount, 312);
    expect(dates.dates.single.date, '2026-07-03');
    expect(dates.dates.single.count, 2);
    expect(list.items.single.date, '2026-07-03');
    expect(list.items.single.sequence, 12);
    expect(list.items.single.width, 2304);
    expect(list.nextCursor, '');
  });

  test('capture dates JSON accepts old response without storage', () {
    final dates = CaptureDatesResponse.fromJson(const {
      'dates': [
        {'date': '2026-07-03', 'count': 2},
      ],
    });

    expect(dates.storage, isNull);
    expect(dates.dates.single.date, '2026-07-03');
    expect(dates.dates.single.count, 2);
  });

  test('camera geometry JSON models parse intrinsics and extrinsics', () {
    final intrinsics = CameraIntrinsics.fromJson(const {
      'camera_path': '/World/Realsense/Color',
      'width': 1280,
      'height': 720,
      'fx': 634.086,
      'fy': 566.49,
      'cx': 640,
      'cy': 360,
      'distortion_model': 'none',
    });
    final extrinsics = CameraExtrinsics.fromJson(const {
      'camera_path': '/World/Realsense/Color',
      'robot_base_path': '/World/INDY7',
      'column_vector': {
        'robot_from_camera_optical': [
          [1, 0, 0, -0.28905],
          [0, -1, 0, 0.57642],
          [0, 0, -1, 1.14099],
          [0, 0, 0, 1],
        ],
      },
    });

    expect(intrinsics.width, 1280);
    expect(intrinsics.fx, 634.086);
    expect(extrinsics.robotBasePath, '/World/INDY7');
    expect(extrinsics.robotFromCameraOptical[0][3], -0.28905);
  });
}
