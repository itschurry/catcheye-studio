// ROI data models — 1:1 mapping with catcheye-guard C++ models

enum RoiConfigKind {
  person(endpoint: 'roi', label: 'Person ROI'),
  pallet(endpoint: 'pallet-roi', label: 'Pallet ROI');

  const RoiConfigKind({required this.endpoint, required this.label});

  final String endpoint;
  final String label;
}

class RoiPoint {
  double x;
  double y;

  RoiPoint({required this.x, required this.y});

  factory RoiPoint.fromJson(List<dynamic> json) {
    return RoiPoint(
      x: (json[0] as num).toDouble(),
      y: (json[1] as num).toDouble(),
    );
  }

  List<double> toJson() => [x, y];

  RoiPoint copyWith({double? x, double? y}) {
    return RoiPoint(x: x ?? this.x, y: y ?? this.y);
  }

  @override
  String toString() => '($x, $y)';
}

class RoiPolygon {
  String id;
  String name;
  bool enabled;
  List<RoiPoint> points;

  RoiPolygon({
    required this.id,
    required this.name,
    this.enabled = true,
    required this.points,
  });

  factory RoiPolygon.fromJson(Map<String, dynamic> json) {
    return RoiPolygon(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      points: (json['points'] as List<dynamic>)
          .map((p) => RoiPoint.fromJson(p as List<dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'enabled': enabled,
    'points': points.map((p) => p.toJson()).toList(),
  };

  RoiPolygon copyWith({
    String? id,
    String? name,
    bool? enabled,
    List<RoiPoint>? points,
  }) {
    return RoiPolygon(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      points: points ?? this.points.map((p) => p.copyWith()).toList(),
    );
  }
}

class CameraRoiConfig {
  String cameraId;
  int imageWidth;
  int imageHeight;
  List<RoiPolygon> allowedZones;

  CameraRoiConfig({
    required this.cameraId,
    required this.imageWidth,
    required this.imageHeight,
    required this.allowedZones,
  });

  factory CameraRoiConfig.fromJson(Map<String, dynamic> json) {
    return CameraRoiConfig(
      cameraId: json['camera_id'] as String? ?? '',
      imageWidth: json['image_width'] as int? ?? 0,
      imageHeight: json['image_height'] as int? ?? 0,
      allowedZones:
          (json['allowed_zones'] as List<dynamic>?)
              ?.map((z) => RoiPolygon.fromJson(z as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'camera_id': cameraId,
    'image_width': imageWidth,
    'image_height': imageHeight,
    'allowed_zones': allowedZones.map((z) => z.toJson()).toList(),
  };

  factory CameraRoiConfig.defaultConfig() {
    return CameraRoiConfig(
      cameraId: 'cam_default',
      imageWidth: 1280,
      imageHeight: 720,
      allowedZones: [],
    );
  }

  CameraRoiConfig copyWith({
    String? cameraId,
    int? imageWidth,
    int? imageHeight,
    List<RoiPolygon>? allowedZones,
  }) {
    return CameraRoiConfig(
      cameraId: cameraId ?? this.cameraId,
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      allowedZones:
          allowedZones ?? this.allowedZones.map((z) => z.copyWith()).toList(),
    );
  }
}
