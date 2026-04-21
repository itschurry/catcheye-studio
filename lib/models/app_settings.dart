// catcheye-guard remote detector settings model

class AppSettings {
  static const int defaultRtspPort = 8554;

  String detectorBaseUrl;
  String streamPath;
  String apiBasePath;
  String cameraPipeline;
  String modelParamPath;
  String modelBinPath;
  String metadataPath;
  String roiConfigPath;
  bool roiEnabled;
  bool roiAutoReload;
  bool renderPreview;
  bool filterByClass;
  int filterClassId;

  AppSettings({
    this.detectorBaseUrl = 'http://127.0.0.1:8080',
    this.streamPath = 'rtsp://127.0.0.1:8554/live',
    this.apiBasePath = '/api',
    this.cameraPipeline =
        'libcamerasrc ! '
        'video/x-raw,width=1280,height=720,framerate=30/1,format=NV12 ! '
        'videoflip video-direction=vert ! '
        'videoconvert ! '
        'video/x-raw,format=BGR ! '
        'appsink drop=true max-buffers=1 sync=false',
    this.modelParamPath = '',
    this.modelBinPath = '',
    this.metadataPath = '',
    this.roiConfigPath = '',
    this.roiEnabled = true,
    this.roiAutoReload = true,
    this.renderPreview = true,
    this.filterByClass = true,
    this.filterClassId = 0,
  });

  AppSettings copyWith({
    String? detectorBaseUrl,
    String? streamPath,
    String? apiBasePath,
    String? cameraPipeline,
    String? modelParamPath,
    String? modelBinPath,
    String? metadataPath,
    String? roiConfigPath,
    bool? roiEnabled,
    bool? roiAutoReload,
    bool? renderPreview,
    bool? filterByClass,
    int? filterClassId,
  }) {
    return AppSettings(
      detectorBaseUrl: detectorBaseUrl ?? this.detectorBaseUrl,
      streamPath: streamPath ?? this.streamPath,
      apiBasePath: apiBasePath ?? this.apiBasePath,
      cameraPipeline: cameraPipeline ?? this.cameraPipeline,
      modelParamPath: modelParamPath ?? this.modelParamPath,
      modelBinPath: modelBinPath ?? this.modelBinPath,
      metadataPath: metadataPath ?? this.metadataPath,
      roiConfigPath: roiConfigPath ?? this.roiConfigPath,
      roiEnabled: roiEnabled ?? this.roiEnabled,
      roiAutoReload: roiAutoReload ?? this.roiAutoReload,
      renderPreview: renderPreview ?? this.renderPreview,
      filterByClass: filterByClass ?? this.filterByClass,
      filterClassId: filterClassId ?? this.filterClassId,
    );
  }

  Uri get streamUri => _resolveUri(streamPath);

  Uri buildApiUri(String endpoint) {
    final normalizedBase = apiBasePath.endsWith('/')
        ? apiBasePath.substring(0, apiBasePath.length - 1)
        : apiBasePath;
    final normalizedEndpoint =
        endpoint.startsWith('/') ? endpoint.substring(1) : endpoint;
    return _resolveUri('$normalizedBase/$normalizedEndpoint');
  }

  Map<String, dynamic> toRemoteJson() {
    return {
      'camera_pipeline': cameraPipeline,
      'model_param_path': modelParamPath,
      'model_bin_path': modelBinPath,
      'metadata_path': metadataPath,
      'roi_config_path': roiConfigPath,
      'roi_enabled': roiEnabled,
      'roi_auto_reload': roiAutoReload,
      'render_preview': renderPreview,
      'filter_by_class': filterByClass,
      'filter_class_id': filterClassId,
    };
  }

  factory AppSettings.fromRemoteJson(Map<String, dynamic> json) {
    return AppSettings(
      cameraPipeline: _readString(json, 'camera_pipeline', 'cameraPipeline'),
      modelParamPath: _readString(json, 'model_param_path', 'modelParamPath'),
      modelBinPath: _readString(json, 'model_bin_path', 'modelBinPath'),
      metadataPath: _readString(json, 'metadata_path', 'metadataPath'),
      roiConfigPath: _readString(json, 'roi_config_path', 'roiConfigPath'),
      roiEnabled: _readBool(json, 'roi_enabled', 'roiEnabled', fallback: true),
      roiAutoReload: _readBool(
        json,
        'roi_auto_reload',
        'roiAutoReload',
        fallback: true,
      ),
      renderPreview: _readBool(
        json,
        'render_preview',
        'renderPreview',
        fallback: true,
      ),
      filterByClass: _readBool(
        json,
        'filter_by_class',
        'filterByClass',
        fallback: true,
      ),
      filterClassId: _readInt(
        json,
        'filter_class_id',
        'filterClassId',
        fallback: 0,
      ),
    );
  }

  Uri _resolveUri(String pathOrUrl) {
    if (pathOrUrl.startsWith('http://') ||
            pathOrUrl.startsWith('https://') ||
            pathOrUrl.startsWith('rtsp://') ||
            pathOrUrl.startsWith('rtsps://')
    ) {
      return Uri.parse(pathOrUrl);
    }

    final rtspBase = _buildRtspBaseUri(detectorBaseUrl);
    final normalizedPath = pathOrUrl.startsWith('/') ? pathOrUrl : '/$pathOrUrl';
    return rtspBase.replace(path: normalizedPath);
  }

  static Uri _buildRtspBaseUri(String rawUrl) {
    final httpBase = _normalizeBaseUri(rawUrl);
    return Uri(
      scheme: 'rtsp',
      host: httpBase.host,
      port: defaultRtspPort,
      path: '/',
    );
  }

  static Uri _normalizeBaseUri(String rawUrl) {
    final trimmed = rawUrl.trim();
    final withScheme = trimmed.startsWith('http://') || trimmed.startsWith('https://')
        ? trimmed
        : 'http://$trimmed';
    final uri = Uri.parse(withScheme);
    if (uri.path.isEmpty) {
      return uri.replace(path: '/');
    }
    return uri;
  }

  static String _readString(
    Map<String, dynamic> json,
    String primary,
    String secondary,
  ) {
    final value = json[primary] ?? json[secondary];
    return value is String ? value : '';
  }

  static bool _readBool(
    Map<String, dynamic> json,
    String primary,
    String secondary, {
    required bool fallback,
  }) {
    final value = json[primary] ?? json[secondary];
    return value is bool ? value : fallback;
  }

  static int _readInt(
    Map<String, dynamic> json,
    String primary,
    String secondary, {
    required int fallback,
  }) {
    final value = json[primary] ?? json[secondary];
    return value is int ? value : fallback;
  }
}
