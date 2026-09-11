import 'dart:typed_data';
import 'dart:ui' show Size;

enum ViewerStreamEncoding {
  jpeg,
  pointcloudXyzF32,
  projectedDepthXyDepthF32,
  unknown;

  static ViewerStreamEncoding parse(String value) {
    return switch (value) {
      'jpeg' => ViewerStreamEncoding.jpeg,
      'pointcloud_xyz_f32' => ViewerStreamEncoding.pointcloudXyzF32,
      'projected_depth_xy_depth_f32' =>
        ViewerStreamEncoding.projectedDepthXyDepthF32,
      _ => ViewerStreamEncoding.unknown,
    };
  }
}

class PointCloudData {
  final Float32List xyz;
  final int pointCount;
  final double minZ;
  final double maxZ;

  const PointCloudData({
    required this.xyz,
    required this.pointCount,
    required this.minZ,
    required this.maxZ,
  });

  factory PointCloudData.parse(Uint8List bytes, int pointCount) {
    const bytesPerPoint = 12;
    final expectedBytes = pointCount * bytesPerPoint;
    if (pointCount <= 0 || bytes.length != expectedBytes) {
      throw FormatException(
        '포인트클라우드 데이터 크기 오류: 예상 $expectedBytes, 수신 ${bytes.length}',
      );
    }

    final data = ByteData.sublistView(bytes);
    final xyz = Float32List(pointCount * 3);
    var validPointCount = 0;
    double? minZ;
    double? maxZ;
    for (var i = 0; i < pointCount; i++) {
      final offset = i * bytesPerPoint;
      final x = data.getFloat32(offset, Endian.little);
      final y = data.getFloat32(offset + 4, Endian.little);
      final z = data.getFloat32(offset + 8, Endian.little);
      if (!x.isFinite || !y.isFinite || !z.isFinite) {
        continue;
      }
      final writeOffset = validPointCount * 3;
      xyz[writeOffset] = x;
      xyz[writeOffset + 1] = y;
      xyz[writeOffset + 2] = z;
      validPointCount++;
      minZ = minZ == null ? z : (z < minZ ? z : minZ);
      maxZ = maxZ == null ? z : (z > maxZ ? z : maxZ);
    }

    return PointCloudData(
      xyz: xyz,
      pointCount: validPointCount,
      minZ: minZ ?? 0,
      maxZ: maxZ ?? 1,
    );
  }

  double xAt(int index) => xyz[index * 3];

  double yAt(int index) => xyz[index * 3 + 1];

  double zAt(int index) => xyz[index * 3 + 2];
}

class ProjectedDepthData {
  final Float32List xyDepth;
  final int pointCount;
  final double minDepth;
  final double maxDepth;

  const ProjectedDepthData({
    required this.xyDepth,
    required this.pointCount,
    required this.minDepth,
    required this.maxDepth,
  });

  factory ProjectedDepthData.parse(Uint8List bytes, int pointCount) {
    const bytesPerPoint = 12;
    final expectedBytes = pointCount * bytesPerPoint;
    if (pointCount <= 0 || bytes.length != expectedBytes) {
      throw FormatException(
        '투영 깊이 데이터 크기 오류: 예상 $expectedBytes, 수신 ${bytes.length}',
      );
    }

    final data = ByteData.sublistView(bytes);
    final points = Float32List(pointCount * 3);
    var validPointCount = 0;
    double? minDepth;
    double? maxDepth;
    for (var i = 0; i < pointCount; i++) {
      final offset = i * bytesPerPoint;
      final x = data.getFloat32(offset, Endian.little);
      final y = data.getFloat32(offset + 4, Endian.little);
      final depth = data.getFloat32(offset + 8, Endian.little);
      if (!x.isFinite || !y.isFinite || !depth.isFinite || depth <= 0) {
        continue;
      }
      final writeOffset = validPointCount * 3;
      points[writeOffset] = x;
      points[writeOffset + 1] = y;
      points[writeOffset + 2] = depth;
      validPointCount++;
      minDepth = minDepth == null
          ? depth
          : (depth < minDepth ? depth : minDepth);
      maxDepth = maxDepth == null
          ? depth
          : (depth > maxDepth ? depth : maxDepth);
    }

    return ProjectedDepthData(
      xyDepth: points,
      pointCount: validPointCount,
      minDepth: minDepth ?? 0,
      maxDepth: maxDepth ?? 1,
    );
  }

  double xAt(int index) => xyDepth[index * 3];

  double yAt(int index) => xyDepth[index * 3 + 1];

  double depthAt(int index) => xyDepth[index * 3 + 2];
}

class ViewerStreamFrame {
  final String name;
  final String kind;
  final ViewerStreamEncoding encoding;
  final int payloadIndex;
  final int? width;
  final int? height;
  final int pointCount;
  final int stride;
  final double? sourceTimestampMs;
  final int? frameSequence;
  final DateTime receivedAt;
  final Uint8List payloadBytes;
  final PointCloudData? pointCloud;
  final ProjectedDepthData? projectedDepth;
  final String? streamKey;

  const ViewerStreamFrame({
    required this.name,
    required this.kind,
    required this.encoding,
    required this.payloadIndex,
    required this.payloadBytes,
    required this.receivedAt,
    this.pointCount = 0,
    this.stride = 1,
    this.width,
    this.height,
    this.sourceTimestampMs,
    this.frameSequence,
    this.pointCloud,
    this.projectedDepth,
    this.streamKey,
  });

  factory ViewerStreamFrame.fromPayload({
    required String name,
    required String kind,
    required ViewerStreamEncoding encoding,
    required int payloadIndex,
    required Uint8List payloadBytes,
    required int pointCount,
    required int stride,
    int? width,
    int? height,
    double? sourceTimestampMs,
    int? frameSequence,
    DateTime? receivedAt,
    String? streamKey,
  }) {
    return ViewerStreamFrame(
      name: name,
      kind: kind,
      encoding: encoding,
      payloadIndex: payloadIndex,
      width: width,
      height: height,
      pointCount: pointCount,
      stride: stride,
      sourceTimestampMs: sourceTimestampMs,
      frameSequence: frameSequence,
      receivedAt: receivedAt ?? DateTime.now(),
      payloadBytes: payloadBytes,
      pointCloud: encoding == ViewerStreamEncoding.pointcloudXyzF32
          ? PointCloudData.parse(payloadBytes, pointCount)
          : null,
      projectedDepth: encoding == ViewerStreamEncoding.projectedDepthXyDepthF32
          ? ProjectedDepthData.parse(payloadBytes, pointCount)
          : null,
      streamKey: streamKey,
    );
  }

  String get key => streamKey ?? (kind.isEmpty ? name : kind);

  Uint8List get jpegBytes => payloadBytes;

  bool get isJpeg => encoding == ViewerStreamEncoding.jpeg;

  bool get isPointCloud => encoding == ViewerStreamEncoding.pointcloudXyzF32;

  bool get isProjectedDepth =>
      encoding == ViewerStreamEncoding.projectedDepthXyDepthF32;

  String get label {
    if (kind.isNotEmpty) return kind;
    if (name.isNotEmpty) return name;
    return 'stream_$payloadIndex';
  }

  Size? get size {
    final w = width;
    final h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return Size(w.toDouble(), h.toDouble());
  }
}

class DetectionPosition {
  final String className;
  final double score;
  final double x;
  final double y;
  final double z;
  final int sampleCount;
  final int pointcloudX;
  final int pointcloudY;
  final bool isCandidate;
  final int candidateId;
  final List<double>? bboxCameraM;

  const DetectionPosition({
    required this.className,
    required this.score,
    required this.x,
    required this.y,
    required this.z,
    required this.sampleCount,
    required this.pointcloudX,
    required this.pointcloudY,
    this.isCandidate = false,
    this.candidateId = 0,
    this.bboxCameraM,
  });

  bool containsPoint(double px, double py, double pz) {
    final bbox = bboxCameraM;
    if (bbox == null || bbox.length < 6) return false;
    return px >= bbox[0] &&
        px <= bbox[3] &&
        py >= bbox[1] &&
        py <= bbox[4] &&
        pz >= bbox[2] &&
        pz <= bbox[5];
  }
}
