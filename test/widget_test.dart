import 'package:flutter_test/flutter_test.dart';

import 'package:catcheye_studio/models/app_settings.dart';
import 'package:catcheye_studio/services/remote_pick_api_service.dart';

void main() {
  test('remote device kind parses capture', () {
    expect(RemoteDeviceKind.fromApiValue('capture'), RemoteDeviceKind.capture);
    expect(RemoteDeviceKind.capture.apiValue, 'capture');
    expect(RemoteDeviceKind.capture.label, 'Capture');
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
