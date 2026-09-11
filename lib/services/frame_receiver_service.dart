import '../models/viewer_frame.dart';
export '../models/viewer_frame.dart';
import 'websocket_frame_decoder.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

enum StreamTransport { rtsp, websocket }

/// Receives RTSP streams via media_kit or JPEG frames over WebSocket.
class FrameReceiverService extends ChangeNotifier {
  Player? _nativePlayer;
  Player get _player {
    if (_disposed) throw StateError('종료된 영상 수신기입니다');
    if (_nativePlayer != null) return _nativePlayer!;
    final player = Player();
    _nativePlayer = player;
    _playingSubscription = player.stream.playing.listen((playing) {
      if (_disposed || _transport != StreamTransport.rtsp) return;
      if (_connected != playing) {
        _connected = playing;
        _notifyListeners();
      }
    });
    return player;
  }

  late final VideoController _videoController = VideoController(_player);

  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<dynamic>? _webSocketSubscription;
  WebSocket? _webSocket;
  bool _connected = false;
  bool _connecting = false;
  String? _errorMessage;
  Uri? _connectedUri;
  final _decoder = WebSocketFrameDecoder();
  StreamTransport? _transport;
  bool _disposed = false;
  int _connectionGeneration = 0;
  bool _currentConnection(int generation) =>
      !_disposed && generation == _connectionGeneration;
  Map<String, dynamic>? get _latestMetadata => _decoder.latestMetadata;
  bool get connected => _connected;
  bool get connecting => _connecting;
  String? get errorMessage => _errorMessage ?? _decoder.errorMessage;
  Uint8List? get currentFrame => _decoder.currentFrame;
  Map<String, ViewerStreamFrame> get streams => _decoder.streams;
  String? get selectedStreamKey => _decoder.selectedStreamKey;
  ViewerStreamFrame? get selectedFrame => _decoder.selectedFrame;
  bool get hasMultiStream => _decoder.hasMultiStream;
  Map<String, dynamic>? get latestMetadata => _latestMetadata;
  Set<String>? get expectedCameraIds => _decoder.expectedCameraIds;
  DateTime? get lastFrameReceivedAt => _decoder.lastFrameReceivedAt;
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

  int get frameCount => _decoder.frameCount;
  double get fps => _decoder.fps;
  Uri? get connectedUri => _connectedUri;
  VideoController? get videoController => isRtsp ? _videoController : null;
  StreamTransport? get transport => _transport;
  bool get isRtsp => _transport == StreamTransport.rtsp;
  bool get isWebSocket => _transport == StreamTransport.websocket;
  Size? get frameSize => _decoder.frameSize;

  static const String defaultStreamUrl = 'ws://127.0.0.1:8080';

  Future<void> connect([String streamUrl = defaultStreamUrl]) async {
    if (_disposed) return;
    if (_connected || _connecting) return;

    final generation = ++_connectionGeneration;
    _connecting = true;
    _errorMessage = null;
    _decoder.reset();
    _notifyListeners();

    try {
      final uri = _normalizeUri(streamUrl);
      await _disconnect();
      if (!_currentConnection(generation)) return;
      _connecting = true;

      if (_isWebSocketUri(uri)) {
        await _connectWebSocket(uri, generation);
      } else {
        await _connectRtsp(uri, generation);
      }
      if (!_currentConnection(generation)) return;

      _notifyListeners();
    } catch (e) {
      if (!_currentConnection(generation)) return;
      _connecting = false;
      _connected = false;
      _transport = null;
      _errorMessage = '연결 실패: $e';
      _notifyListeners();
    }
  }

  Future<void> disconnect() async {
    if (_disposed) return;
    final generation = ++_connectionGeneration;
    await _disconnect();
    if (!_currentConnection(generation)) return;
    _errorMessage = null;
    _notifyListeners();
  }

  Future<void> _disconnect() async {
    if (_disposed) return;
    final socket = _webSocket;
    final subscription = _webSocketSubscription;
    _webSocket = null;
    _webSocketSubscription = null;
    _connected = _connecting = false;
    _connectedUri = null;
    _decoder.reset();
    _transport = null;
    // 자원을 먼저 분리하여 이전 연결의 종료가 새 연결을 지우지 않도록 합니다.
    await Future.wait<void>([
      if (subscription != null) subscription.cancel(),
      if (socket != null) socket.close().then((_) {}),
      if (_nativePlayer != null) _nativePlayer!.stop(),
    ]);
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

  Future<void> _connectRtsp(Uri uri, int generation) async {
    _transport = StreamTransport.rtsp;
    await _player.open(Media(uri.toString()), play: true);
    if (!_currentConnection(generation)) return;

    _connected = true;
    _connecting = false;
    _errorMessage = null;
    _connectedUri = uri;
  }

  Future<void> _connectWebSocket(Uri uri, int generation) async {
    _transport = StreamTransport.websocket;
    _decoder.reset();
    final socket = await WebSocket.connect(uri.toString());
    if (!_currentConnection(generation)) {
      await socket.close();
      return;
    }
    _webSocket = socket;
    _webSocketSubscription = socket.listen(
      (data) {
        if (_currentConnection(generation)) _onWebSocketData(data);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (_currentConnection(generation)) {
          _handleSocketClosed('연결 오류: $error');
        }
      },
      onDone: () {
        if (!_currentConnection(generation) || (!_connected && !_connecting)) {
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
              ? '서버가 연결을 종료했습니다'
              : '서버가 연결을 종료했습니다 ($closeDetail)',
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
    if (_disposed) return;
    if (_decoder.process(data)) {
      _errorMessage = null;
      _notifyListeners();
    }
  }

  @visibleForTesting
  void processWebSocketDataForTest(dynamic data) => _onWebSocketData(data);

  void setExpectedCameraIds(Iterable<String>? ids) {
    if (_disposed) return;
    _decoder.setExpectedCameraIds(ids);
    _notifyListeners();
  }

  void setExpectedCameraId(String? id) => setExpectedCameraIds(
    id == null
        ? null
        : id.isEmpty
        ? const []
        : [id],
  );
  void selectStream(String key) {
    _decoder.selectStream(key);
    _notifyListeners();
  }

  static String _metadataString(Object? value, {String defaultValue = ''}) =>
      value is String ? value : defaultValue;
  static int? _metadataInt(Object? value) =>
      value is num ? value.toInt() : null;
  static double? _metadataDouble(Object? value) =>
      value is num ? value.toDouble() : null;

  bool _isWebSocketUri(Uri uri) => uri.scheme == 'ws' || uri.scheme == 'wss';

  void _handleSocketClosed(String message) {
    if (_disposed) return;
    _errorMessage = message;
    final generation = ++_connectionGeneration;
    unawaited(
      _disconnect().then((_) {
        if (!_currentConnection(generation)) return;
        _notifyListeners();
      }),
    );
  }

  void _notifyListeners() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _playingSubscription?.cancel();
    _webSocketSubscription?.cancel();
    _webSocket?.close();
    _nativePlayer?.dispose();
    super.dispose();
  }
}
