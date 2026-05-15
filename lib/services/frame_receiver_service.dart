import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

enum StreamTransport { rtsp, websocket }

enum ViewerStreamEncoding {
  jpeg,
  pointcloudXyzF32,
  unknown;

  static ViewerStreamEncoding parse(String value) {
    return switch (value) {
      'jpeg' => ViewerStreamEncoding.jpeg,
      'pointcloud_xyz_f32' => ViewerStreamEncoding.pointcloudXyzF32,
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
        'Invalid pointcloud payload size: expected $expectedBytes, got ${bytes.length}',
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
  final Uint8List payloadBytes;
  final PointCloudData? pointCloud;

  const ViewerStreamFrame({
    required this.name,
    required this.kind,
    required this.encoding,
    required this.payloadIndex,
    required this.payloadBytes,
    this.pointCount = 0,
    this.stride = 1,
    this.width,
    this.height,
    this.sourceTimestampMs,
    this.pointCloud,
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
      payloadBytes: payloadBytes,
      pointCloud: encoding == ViewerStreamEncoding.pointcloudXyzF32
          ? PointCloudData.parse(payloadBytes, pointCount)
          : null,
    );
  }

  String get key => kind.isEmpty ? name : kind;

  Uint8List get jpegBytes => payloadBytes;

  bool get isJpeg => encoding == ViewerStreamEncoding.jpeg;

  bool get isPointCloud => encoding == ViewerStreamEncoding.pointcloudXyzF32;

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

class _PendingStreamInfo {
  final String name;
  final String kind;
  final ViewerStreamEncoding encoding;
  final int payloadIndex;
  final int? width;
  final int? height;
  final int? payloadSize;
  final int pointCount;
  final int stride;
  final double? sourceTimestampMs;

  const _PendingStreamInfo({
    required this.name,
    required this.kind,
    required this.encoding,
    required this.payloadIndex,
    this.width,
    this.height,
    this.payloadSize,
    this.pointCount = 0,
    this.stride = 1,
    this.sourceTimestampMs,
  });

  String get label {
    if (kind.isNotEmpty) return kind;
    if (name.isNotEmpty) return name;
    return 'stream_$payloadIndex';
  }
}

/// Receives RTSP streams via media_kit or JPEG frames over WebSocket.
class FrameReceiverService extends ChangeNotifier {
  final Player _player = Player();
  late final VideoController _videoController = VideoController(_player);

  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<dynamic>? _webSocketSubscription;
  WebSocket? _webSocket;
  bool _closingWebSocket = false;
  bool _connected = false;
  bool _connecting = false;
  String? _errorMessage;
  Uri? _connectedUri;
  Uint8List? _currentFrame;
  final Map<String, ViewerStreamFrame> _streams = {};
  String? _selectedStreamKey;
  List<_PendingStreamInfo>? _pendingStreams;
  final Map<int, Uint8List> _pendingPayloads = {};
  Map<String, dynamic>? _latestMetadata;
  int _frameCount = 0;
  double _fps = 0;
  double? _previousSourceTimestampMs;
  StreamTransport? _transport;

  Size? _frameSize;

  bool get connected => _connected;
  bool get connecting => _connecting;
  String? get errorMessage => _errorMessage;
  Uint8List? get currentFrame => _currentFrame;
  Map<String, ViewerStreamFrame> get streams => Map.unmodifiable(_streams);
  String? get selectedStreamKey => _selectedStreamKey;
  ViewerStreamFrame? get selectedFrame {
    final key = _selectedStreamKey;
    if (key != null) return _streams[key];
    if (_streams.isEmpty) return null;
    return _streams.values.first;
  }

  bool get hasMultiStream => _streams.length > 1;
  Map<String, dynamic>? get latestMetadata => _latestMetadata;
  List<DetectionPosition> get detectionPositions =>
      _parseDetectionPositions(_latestMetadata);
  double? get inferenceMs {
    final metadata = _latestMetadata?['metadata'];
    if (metadata is! Map<String, dynamic>) return null;

    final value = metadata['inference_ms'];
    if (value is num) return value.toDouble();
    return null;
  }

  List<DetectionPosition> _parseDetectionPositions(
    Map<String, dynamic>? metadata,
  ) {
    final positions = <DetectionPosition>[];
    final rawCandidates = metadata?['pick_candidates'];
    if (rawCandidates is List) {
      for (final rawCandidate in rawCandidates) {
        if (rawCandidate is! Map<String, dynamic>) continue;
        final rawCenter = rawCandidate['center_camera_m'];
        if (rawCenter is! List || rawCenter.length < 3) continue;
        final x = _metadataDouble(rawCenter[0]);
        final y = _metadataDouble(rawCenter[1]);
        final z = _metadataDouble(rawCenter[2]);
        if (x == null || y == null || z == null) continue;
        final rawBbox = rawCandidate['bbox_camera_m'];
        final bbox = rawBbox is List
            ? rawBbox
                  .map(_metadataDouble)
                  .whereType<double>()
                  .take(6)
                  .toList(growable: false)
            : null;
        final candidateId = _metadataInt(rawCandidate['id']) ?? 0;
        positions.add(
          DetectionPosition(
            className:
                (rawCandidate['product_id'] as String?) ??
                'candidate_$candidateId',
            score: _metadataDouble(rawCandidate['confidence']) ?? 0,
            x: x,
            y: y,
            z: z,
            sampleCount: _metadataInt(rawCandidate['sample_count']) ?? 0,
            pointcloudX: 0,
            pointcloudY: 0,
            isCandidate: true,
            candidateId: candidateId,
            bboxCameraM: bbox,
          ),
        );
      }
    }

    final rawDetections = metadata?['detections'];
    if (rawDetections is! List) return positions;

    for (final rawDetection in rawDetections) {
      if (rawDetection is! Map<String, dynamic>) continue;
      final rawPosition = rawDetection['position'];
      if (rawPosition is! Map<String, dynamic>) continue;

      final x = _metadataDouble(rawPosition['x']);
      final y = _metadataDouble(rawPosition['y']);
      final z = _metadataDouble(rawPosition['z']);
      if (x == null || y == null || z == null) continue;

      positions.add(
        DetectionPosition(
          className: _metadataString(rawDetection['class_name']),
          score: _metadataDouble(rawDetection['score']) ?? 0,
          x: x,
          y: y,
          z: z,
          sampleCount: _metadataInt(rawPosition['sample_count']) ?? 0,
          pointcloudX: _metadataInt(rawPosition['pointcloud_x']) ?? 0,
          pointcloudY: _metadataInt(rawPosition['pointcloud_y']) ?? 0,
        ),
      );
    }
    return positions;
  }

  String? get wallClockText {
    final timestamp = _latestMetadata?['wall_timestamp_ms'];
    if (timestamp is! num) return null;

    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp.toInt());
    final year = dateTime.year.toString().padLeft(4, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final second = dateTime.second.toString().padLeft(2, '0');
    return '$year-$month-$day'
        '_$hour:$minute:$second';
  }

  int get frameCount => _frameCount;
  double get fps => _fps;
  Uri? get connectedUri => _connectedUri;
  VideoController get videoController => _videoController;
  StreamTransport? get transport => _transport;
  bool get isRtsp => _transport == StreamTransport.rtsp;
  bool get isWebSocket => _transport == StreamTransport.websocket;
  Size? get frameSize => _frameSize;

  static const String defaultStreamUrl = 'ws://127.0.0.1:8080';

  FrameReceiverService() {
    _playingSubscription = _player.stream.playing.listen((isPlaying) {
      if (_connected != isPlaying) {
        _connected = isPlaying;
        notifyListeners();
      }
    });
  }

  Future<void> connect([String streamUrl = defaultStreamUrl]) async {
    if (_connected || _connecting) return;

    _connecting = true;
    _errorMessage = null;
    _fps = 0;
    _frameCount = 0;
    _previousSourceTimestampMs = null;
    notifyListeners();

    try {
      final uri = _normalizeUri(streamUrl);
      await _disconnect();

      if (_isWebSocketUri(uri)) {
        await _connectWebSocket(uri);
      } else {
        await _connectRtsp(uri);
      }

      notifyListeners();
    } catch (e) {
      _connecting = false;
      _connected = false;
      _transport = null;
      _errorMessage = 'Connection failed: $e';
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await _disconnect();
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _disconnect() async {
    _closingWebSocket = true;
    _connected = false;
    _connecting = false;
    await _webSocketSubscription?.cancel();
    _webSocketSubscription = null;
    await _closeWebSocket();
    await _player.stop();
    _connectedUri = null;
    _currentFrame = null;
    _streams.clear();
    _selectedStreamKey = null;
    _pendingStreams = null;
    _pendingPayloads.clear();
    _latestMetadata = null;
    _frameCount = 0;
    _fps = 0;
    _previousSourceTimestampMs = null;
    _transport = null;
    _frameSize = null;
    _closingWebSocket = false;
  }

  Uri _normalizeUri(String rawUrl) {
    final trimmed = rawUrl.trim();
    final normalized =
        trimmed.startsWith('rtsp://') ||
            trimmed.startsWith('rtsps://') ||
            trimmed.startsWith('ws://') ||
            trimmed.startsWith('wss://') ||
            trimmed.startsWith('http://') ||
            trimmed.startsWith('https://')
        ? trimmed
        : 'rtsp://$trimmed';
    return Uri.parse(normalized);
  }

  Future<void> _connectRtsp(Uri uri) async {
    _transport = StreamTransport.rtsp;
    await _player.open(Media(uri.toString()), play: true);

    _connected = true;
    _connecting = false;
    _errorMessage = null;
    _connectedUri = uri;
  }

  Future<void> _connectWebSocket(Uri uri) async {
    _transport = StreamTransport.websocket;
    _currentFrame = null;
    _webSocket = await WebSocket.connect(uri.toString());

    _webSocketSubscription = _webSocket!.listen(
      _onWebSocketData,
      onError: (Object error, StackTrace stackTrace) {
        _handleSocketClosed('Connection error: $error');
      },
      onDone: () {
        if (_closingWebSocket || (!_connected && !_connecting)) {
          return;
        }
        final closeCode = _webSocket?.closeCode;
        final closeReason = _webSocket?.closeReason;
        final closeDetail = [
          if (closeCode != null) 'code=$closeCode',
          if (closeReason != null && closeReason.isNotEmpty)
            'reason=$closeReason',
        ].join(', ');
        _handleSocketClosed(
          closeDetail.isEmpty
              ? 'Connection closed by server'
              : 'Connection closed by server ($closeDetail)',
        );
      },
      cancelOnError: false,
    );

    _connected = true;
    _connecting = false;
    _errorMessage = null;
    _connectedUri = uri;
  }

  void _onWebSocketData(dynamic data) {
    if (data is String) {
      _onWebSocketMetadata(data);
      return;
    }

    if (data is List<int>) {
      _onWebSocketPayload(Uint8List.fromList(data));
    }
  }

  void _onWebSocketMetadata(String data) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) return;
      _failIncompletePendingFrame();
      _latestMetadata = decoded;
      _updateFpsFromMetadata(decoded);
      _pendingStreams = _parsePendingStreams(decoded);
      _pendingPayloads.clear();
    } catch (e) {
      _errorMessage = 'Invalid WebSocket metadata: $e';
      _pendingStreams = null;
      _pendingPayloads.clear();
    }
    notifyListeners();
  }

  void _updateFpsFromMetadata(Map<String, dynamic> metadataFrame) {
    final timestamp =
        metadataFrame['source_timestamp_ms'] ??
        metadataFrame['wall_timestamp_ms'];
    if (timestamp is! num) return;

    final currentTimestampMs = timestamp.toDouble();
    final previousTimestampMs = _previousSourceTimestampMs;
    if (previousTimestampMs != null) {
      final frameIntervalMs = currentTimestampMs - previousTimestampMs;
      if (frameIntervalMs > 0) {
        _fps = 1000.0 / frameIntervalMs;
      }
    }
    _previousSourceTimestampMs = currentTimestampMs;
  }

  void _onWebSocketPayload(Uint8List payload) {
    final pendingStreams = _pendingStreams;
    if (pendingStreams == null) {
      _setSingleFrame(payload);
      notifyListeners();
      return;
    }

    final streamInfo = pendingStreams.firstWhere(
      (stream) => !_pendingPayloads.containsKey(stream.payloadIndex),
      orElse: () => const _PendingStreamInfo(
        name: '',
        kind: '',
        encoding: ViewerStreamEncoding.unknown,
        payloadIndex: -1,
      ),
    );
    if (streamInfo.payloadIndex < 0) {
      _errorMessage = 'Unexpected WebSocket payload';
      notifyListeners();
      return;
    }

    final expectedPayloadSize = streamInfo.payloadSize;
    if (expectedPayloadSize != null && payload.length != expectedPayloadSize) {
      _errorMessage =
          'Invalid ${streamInfo.label} payload size: expected $expectedPayloadSize, got ${payload.length}';
      _pendingStreams = null;
      _pendingPayloads.clear();
      notifyListeners();
      return;
    }

    _pendingPayloads[streamInfo.payloadIndex] = payload;
    if (_pendingPayloads.length != pendingStreams.length) {
      return;
    }

    final nextStreams = <String, ViewerStreamFrame>{};
    for (final stream in pendingStreams) {
      final jpegBytes = _pendingPayloads[stream.payloadIndex];
      if (jpegBytes == null) {
        _errorMessage = 'Missing WebSocket payload: ${stream.label}';
        _pendingStreams = null;
        _pendingPayloads.clear();
        notifyListeners();
        return;
      }
      try {
        final frame = ViewerStreamFrame.fromPayload(
          name: stream.name,
          kind: stream.kind,
          encoding: stream.encoding,
          payloadIndex: stream.payloadIndex,
          width: stream.width,
          height: stream.height,
          pointCount: stream.pointCount,
          stride: stream.stride,
          sourceTimestampMs: stream.sourceTimestampMs,
          payloadBytes: jpegBytes,
        );
        nextStreams[frame.key] = frame;
      } catch (e) {
        _errorMessage = 'Invalid ${stream.label} payload: $e';
        _pendingStreams = null;
        _pendingPayloads.clear();
        notifyListeners();
        return;
      }
    }

    _streams.addAll(nextStreams);
    _selectedStreamKey = _selectNextStreamKey();
    _syncSelectedFrameState();
    _errorMessage = null;
    _frameCount++;
    _pendingStreams = null;
    _pendingPayloads.clear();
    notifyListeners();
  }

  void _setSingleFrame(Uint8List payload) {
    _currentFrame = payload;
    final detectedSize = _parseJpegSize(payload);
    _frameSize = detectedSize ?? _frameSize;
    final frame = ViewerStreamFrame(
      name: 'camera',
      kind: 'camera',
      encoding: ViewerStreamEncoding.jpeg,
      payloadIndex: 0,
      width: detectedSize?.width.toInt(),
      height: detectedSize?.height.toInt(),
      payloadBytes: payload,
    );
    _streams
      ..clear()
      ..[frame.key] = frame;
    _selectedStreamKey = frame.key;
    _syncSelectedFrameState();
    _errorMessage = null;
    _frameCount++;
  }

  List<_PendingStreamInfo>? _parsePendingStreams(
    Map<String, dynamic> metadata,
  ) {
    if (metadata['type'] != 'viewer_frame') return null;
    final rawStreams = metadata['streams'];
    if (rawStreams is! List || rawStreams.isEmpty) return null;

    final streams = <_PendingStreamInfo>[];
    final indexes = <int>{};
    for (final rawStream in rawStreams) {
      if (rawStream is! Map<String, dynamic>) {
        throw const FormatException('Invalid WebSocket stream metadata');
      }
      final payloadIndex = rawStream['payload_index'];
      if (payloadIndex is! int || payloadIndex < 0) {
        throw const FormatException('Invalid WebSocket payload_index');
      }
      if (!indexes.add(payloadIndex)) {
        throw const FormatException('Duplicated WebSocket payload_index');
      }
      streams.add(
        _PendingStreamInfo(
          name: _metadataString(rawStream['name']),
          kind: _metadataString(rawStream['kind']),
          encoding: ViewerStreamEncoding.parse(
            _metadataString(rawStream['encoding'], defaultValue: 'jpeg'),
          ),
          payloadIndex: payloadIndex,
          width: _metadataInt(rawStream['width']),
          height: _metadataInt(rawStream['height']),
          payloadSize: _metadataInt(rawStream['payload_size']),
          pointCount: _metadataInt(rawStream['point_count']) ?? 0,
          stride: _metadataInt(rawStream['stride']) ?? 1,
          sourceTimestampMs: _metadataDouble(rawStream['source_timestamp_ms']),
        ),
      );
    }
    streams.sort((a, b) => a.payloadIndex.compareTo(b.payloadIndex));
    return streams;
  }

  void _failIncompletePendingFrame() {
    final pendingStreams = _pendingStreams;
    if (pendingStreams == null ||
        _pendingPayloads.length == pendingStreams.length) {
      return;
    }
    _errorMessage =
        'Incomplete WebSocket frame: expected ${pendingStreams.length} payloads, got ${_pendingPayloads.length}';
    _pendingStreams = null;
    _pendingPayloads.clear();
  }

  String _selectNextStreamKey() {
    final current = _selectedStreamKey;
    if (current != null && _streams.containsKey(current)) return current;
    if (_streams.containsKey('camera')) return 'camera';
    return _streams.keys.first;
  }

  void selectStream(String key) {
    if (!_streams.containsKey(key) || _selectedStreamKey == key) return;
    _selectedStreamKey = key;
    _syncSelectedFrameState();
    notifyListeners();
  }

  void _syncSelectedFrameState() {
    final frame = selectedFrame;
    if (frame == null) {
      _currentFrame = null;
      _frameSize = null;
      return;
    }
    if (!frame.isJpeg) {
      _currentFrame = null;
      _frameSize = frame.size;
      return;
    }

    _currentFrame = frame.jpegBytes;
    _frameSize = frame.size ?? _parseJpegSize(frame.jpegBytes);
  }

  static String _metadataString(Object? value, {String defaultValue = ''}) =>
      value is String ? value : defaultValue;

  static int? _metadataInt(Object? value) =>
      value is num ? value.toInt() : null;

  static double? _metadataDouble(Object? value) =>
      value is num ? value.toDouble() : null;

  /// Parses JPEG SOF marker to extract image dimensions.
  Size? _parseJpegSize(Uint8List bytes) {
    if (bytes.length < 4) return null;
    if (bytes[0] != 0xFF || bytes[1] != 0xD8) return null;

    int i = 2;
    while (i + 4 <= bytes.length) {
      if (bytes[i] != 0xFF) break;
      final marker = bytes[i + 1];
      if (marker == 0xD8 || marker == 0xD9) {
        i += 2;
        continue;
      }
      if (i + 4 > bytes.length) break;
      final segLen = (bytes[i + 2] << 8) | bytes[i + 3];
      if (marker >= 0xC0 &&
          marker <= 0xC3 &&
          segLen >= 7 &&
          i + 9 <= bytes.length) {
        final h = (bytes[i + 5] << 8) | bytes[i + 6];
        final w = (bytes[i + 7] << 8) | bytes[i + 8];
        if (w > 0 && h > 0) return Size(w.toDouble(), h.toDouble());
      }
      i += 2 + segLen;
    }
    return null;
  }

  bool _isWebSocketUri(Uri uri) => uri.scheme == 'ws' || uri.scheme == 'wss';

  Future<void> _closeWebSocket() async {
    final socket = _webSocket;
    _webSocket = null;
    if (socket != null) {
      await socket.close();
    }
  }

  void _handleSocketClosed(String message) {
    _errorMessage = message;
    _closingWebSocket = true;
    unawaited(
      _disconnect().then((_) {
        notifyListeners();
      }),
    );
  }

  @override
  void dispose() {
    _playingSubscription?.cancel();
    _webSocketSubscription?.cancel();
    _webSocket?.close();
    _player.dispose();
    super.dispose();
  }
}
