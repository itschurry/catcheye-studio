class AppSettings {
  static const int defaultRtspPort = 8554;
  static const String defaultDetectorBaseUrl = 'http://127.0.0.1:8090';
  static const String defaultStreamPath = 'ws://127.0.0.1:8080';
  static const String defaultApiBasePath = '/api';
  static const int defaultCubeEyeFramerate = 15;
  static const bool defaultCubeEyeAutoExposure = false;
  static const bool defaultCubeEyeIllumination = false;
  static const int defaultCubeEyeDepthRangeMin = 0;
  static const int defaultCubeEyeDepthRangeMax = 8192;

  String detectorBaseUrl;
  String streamPath;
  String apiBasePath;
  int cubeEyeFramerate;
  bool cubeEyeAutoExposure;
  bool cubeEyeIllumination;
  int cubeEyeDepthRangeMin;
  int cubeEyeDepthRangeMax;

  AppSettings({
    this.detectorBaseUrl = defaultDetectorBaseUrl,
    this.streamPath = defaultStreamPath,
    this.apiBasePath = defaultApiBasePath,
    this.cubeEyeFramerate = defaultCubeEyeFramerate,
    this.cubeEyeAutoExposure = defaultCubeEyeAutoExposure,
    this.cubeEyeIllumination = defaultCubeEyeIllumination,
    this.cubeEyeDepthRangeMin = defaultCubeEyeDepthRangeMin,
    this.cubeEyeDepthRangeMax = defaultCubeEyeDepthRangeMax,
  });

  Uri get streamUri => _resolveUri(streamPath);

  Uri buildApiUri(String endpoint) {
    final normalizedBase = apiBasePath.endsWith('/')
        ? apiBasePath.substring(0, apiBasePath.length - 1)
        : apiBasePath;
    final normalizedEndpoint = endpoint.startsWith('/')
        ? endpoint.substring(1)
        : endpoint;
    final path = '$normalizedBase/$normalizedEndpoint';
    return _normalizeBaseUri(detectorBaseUrl).replace(path: path);
  }

  Uri _resolveUri(String pathOrUrl) {
    if (pathOrUrl.startsWith('http://') ||
        pathOrUrl.startsWith('https://') ||
        pathOrUrl.startsWith('ws://') ||
        pathOrUrl.startsWith('wss://') ||
        pathOrUrl.startsWith('rtsp://') ||
        pathOrUrl.startsWith('rtsps://')) {
      return Uri.parse(pathOrUrl);
    }

    final rtspBase = _buildRtspBaseUri(detectorBaseUrl);
    final normalizedPath = pathOrUrl.startsWith('/')
        ? pathOrUrl
        : '/$pathOrUrl';
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
    final withScheme =
        trimmed.startsWith('http://') || trimmed.startsWith('https://')
        ? trimmed
        : 'http://$trimmed';
    final uri = Uri.parse(withScheme);
    if (uri.path.isEmpty) {
      return uri.replace(path: '/');
    }
    return uri;
  }
}
