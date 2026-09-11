import 'dart:convert';
import 'dart:ui' show Size;
import 'package:flutter/foundation.dart';
import '../models/viewer_frame.dart';

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
  final int? frameSequence;

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
    this.frameSequence,
  });

  String get label {
    if (kind.isNotEmpty) return kind;
    if (name.isNotEmpty) return name;
    return 'stream_$payloadIndex';
  }
}

/// WebSocket 메시지의 묶음·크기·카메라 식별을 검증합니다. 플레이어를 생성하지 않습니다.
class WebSocketFrameDecoder {
  String? _errorMessage;
  bool _changed = false;
  Uint8List? _currentFrame;
  final Map<String, ViewerStreamFrame> _streams = {};
  String? _selectedStreamKey;
  List<_PendingStreamInfo>? _pendingStreams;
  final Map<int, Uint8List> _pendingPayloads = {};
  bool _discardPendingFrame = false;
  bool _requiresMetadata = false;
  Set<String>? _expectedCameraIds;
  Map<String, dynamic>? _latestMetadata;
  DateTime? _lastFrameReceivedAt;
  int _frameCount = 0;
  double _fps = 0;
  double? _previousSourceTimestampMs;

  Size? _frameSize;
  Uint8List? get currentFrame => _currentFrame;
  Map<String, ViewerStreamFrame> get streams => Map.unmodifiable(_streams);
  String? get selectedStreamKey => _selectedStreamKey;
  ViewerStreamFrame? get selectedFrame {
    final key = _selectedStreamKey;
    if (key != null) return _streams[key];
    if (_streams.isEmpty) return null;
    return _streams.values.first;
  }

  Set<String>? get expectedCameraIds =>
      _expectedCameraIds == null ? null : Set.unmodifiable(_expectedCameraIds!);
  bool get hasMultiStream => _streams.length > 1;
  String? get errorMessage => _errorMessage;
  Map<String, dynamic>? get latestMetadata => _latestMetadata;
  DateTime? get lastFrameReceivedAt => _lastFrameReceivedAt;
  int get frameCount => _frameCount;
  double get fps => _fps;
  Size? get frameSize => _frameSize;

  bool process(Object? data) {
    _changed = false;
    if (data is String) {
      _onWebSocketMetadata(data);
    } else if (data is List<int>) {
      _onWebSocketPayload(Uint8List.fromList(data));
    } else {
      _errorMessage = 'WebSocket 메시지 형식이 올바르지 않습니다';
      _changed = true;
    }
    return _changed;
  }

  void _notifyListeners() => _changed = true;
  void reset() {
    _clearVisibleFrames();
    _pendingStreams = null;
    _pendingPayloads.clear();
    _discardPendingFrame = false;
    _errorMessage = null;
    _requiresMetadata = false;
    _frameCount = 0;
    _fps = 0;
    _previousSourceTimestampMs = null;
  }

  void _onWebSocketMetadata(String data) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('WebSocket JSON 객체가 필요합니다');
      }
      if (decoded['type'] == 'viewer_frame' || decoded['type'] == 'frame') {
        _requiresMetadata = true;
      }
      _failIncompletePendingFrame();
      _pendingStreams = _parsePendingStreams(decoded);
      _pendingPayloads.clear();
      _discardPendingFrame = !_matchesExpectedCameras(decoded);
      if (!_discardPendingFrame) {
        _latestMetadata = decoded;
        _updateFpsFromMetadata(decoded);
      }
    } catch (e) {
      _errorMessage = 'WebSocket 메타데이터 오류: $e';
      _requiresMetadata = true;
      _pendingStreams = null;
      _pendingPayloads.clear();
      _discardPendingFrame = false;
    }
    _notifyListeners();
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
    if (_discardPendingFrame) {
      if (pendingStreams == null) {
        _discardPendingFrame = false;
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
      if (streamInfo.payloadIndex >= 0) {
        _pendingPayloads[streamInfo.payloadIndex] = Uint8List(0);
      }
      if (_pendingPayloads.length == pendingStreams.length) {
        _pendingStreams = null;
        _pendingPayloads.clear();
        _discardPendingFrame = false;
      }
      return;
    }
    if (pendingStreams == null) {
      if (_requiresMetadata || _expectedCameraIds != null) return;
      _setSingleFrame(payload);
      _notifyListeners();
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
      _errorMessage = '예상하지 못한 WebSocket 데이터입니다';
      _notifyListeners();
      return;
    }

    final expectedPayloadSize = streamInfo.payloadSize;
    if (expectedPayloadSize != null && payload.length != expectedPayloadSize) {
      _errorMessage =
          '${streamInfo.label} 데이터 크기 오류: 예상 $expectedPayloadSize, 수신 ${payload.length}';
      _pendingStreams = null;
      _pendingPayloads.clear();
      _notifyListeners();
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
        _errorMessage = 'WebSocket 데이터 누락: ${stream.label}';
        _pendingStreams = null;
        _pendingPayloads.clear();
        _notifyListeners();
        return;
      }
      try {
        final streamKey = _streamKeyFor(stream);
        final previous =
            _streams[streamKey ??
                (stream.kind.isEmpty ? stream.name : stream.kind)];
        final receivedAt =
            stream.frameSequence != null &&
                previous?.frameSequence == stream.frameSequence
            ? previous!.receivedAt
            : DateTime.now();
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
          frameSequence: stream.frameSequence,
          receivedAt: receivedAt,
          payloadBytes: jpegBytes,
          streamKey: streamKey,
        );
        if (_streamMatchesExpected(stream)) {
          nextStreams[frame.key] = frame;
        }
      } catch (e) {
        _errorMessage = '${stream.label} 데이터 형식이 올바르지 않습니다: $e';
        _pendingStreams = null;
        _pendingPayloads.clear();
        _notifyListeners();
        return;
      }
    }

    if (nextStreams.isEmpty) {
      _pendingStreams = null;
      _pendingPayloads.clear();
      return;
    }
    _streams.addAll(nextStreams);
    _selectedStreamKey = _selectNextStreamKey();
    _syncSelectedFrameState();
    _errorMessage = null;
    _frameCount++;
    _lastFrameReceivedAt = DateTime.now();
    _pendingStreams = null;
    _pendingPayloads.clear();
    _notifyListeners();
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
      receivedAt: DateTime.now(),
      payloadBytes: payload,
    );
    _streams
      ..clear()
      ..[frame.key] = frame;
    _selectedStreamKey = frame.key;
    _syncSelectedFrameState();
    _errorMessage = null;
    _frameCount++;
    _lastFrameReceivedAt = DateTime.now();
  }

  /// Restricts station preview frames to the globally selected cameras.
  ///
  /// `null` disables filtering for non-station streams, while an empty set
  /// represents an explicitly disabled station preview.
  void setExpectedCameraIds(Iterable<String>? cameraIds) {
    final next = cameraIds
        ?.map((cameraId) => cameraId.trim())
        .where((cameraId) => cameraId.isNotEmpty)
        .toSet();
    if (setEquals(_expectedCameraIds, next)) return;
    _expectedCameraIds = next;
    _clearVisibleFrames();
    _notifyListeners();
  }

  void setExpectedCameraId(String? cameraId) {
    setExpectedCameraIds(
      cameraId == null
          ? null
          : cameraId.trim().isEmpty
          ? const <String>[]
          : [cameraId],
    );
  }

  void _clearVisibleFrames() {
    _currentFrame = null;
    _streams.clear();
    _selectedStreamKey = null;
    _latestMetadata = null;
    _frameSize = null;
    _lastFrameReceivedAt = null;
  }

  bool _matchesExpectedCameras(Map<String, dynamic> metadataFrame) {
    final expected = _expectedCameraIds;
    if (expected == null) return true;
    if (expected.isEmpty) return false;

    final metadata = metadataFrame['metadata'];
    final nestedCameraId = metadata is Map ? metadata['camera_id'] : null;
    final nestedCameraIds = metadata is Map ? metadata['camera_ids'] : null;
    final streamName = metadataFrame['stream_name'];
    final rawStreams = metadataFrame['streams'];
    final actual = <String>{
      if (nestedCameraId is String && nestedCameraId.isNotEmpty) nestedCameraId,
      if (nestedCameraIds is List) ...nestedCameraIds.whereType<String>(),
      if (streamName is String && streamName.isNotEmpty) streamName,
      if (rawStreams is List)
        for (final stream in rawStreams)
          if (stream is Map && stream['name'] is String)
            stream['name'] as String,
    };
    return actual.any(expected.contains);
  }

  bool _streamMatchesExpected(_PendingStreamInfo stream) {
    final expected = _expectedCameraIds;
    if (expected == null) return true;
    return expected.contains(stream.name) || expected.contains(stream.kind);
  }

  String? _streamKeyFor(_PendingStreamInfo stream) {
    final expected = _expectedCameraIds;
    if (expected != null && expected.contains(stream.name)) return stream.name;
    return null;
  }

  List<_PendingStreamInfo>? _parsePendingStreams(
    Map<String, dynamic> metadata,
  ) {
    if (metadata['type'] == 'frame') {
      return [
        _PendingStreamInfo(
          name: _metadataString(metadata['stream_name']),
          kind: _metadataString(metadata['stream_name']),
          encoding: ViewerStreamEncoding.parse(
            _metadataString(metadata['payload_encoding'], defaultValue: 'jpeg'),
          ),
          payloadIndex: 0,
          width: _metadataInt(metadata['width']),
          height: _metadataInt(metadata['height']),
          payloadSize: _metadataInt(metadata['payload_size']),
          sourceTimestampMs: _metadataDouble(metadata['source_timestamp_ms']),
          frameSequence:
              _metadataInt(metadata['frame_sequence']) ??
              (metadata['metadata'] is Map
                  ? _metadataInt(
                      (metadata['metadata'] as Map)['frame_sequence'],
                    )
                  : null),
        ),
      ];
    }
    if (metadata['type'] != 'viewer_frame') return null;
    final rawStreams = metadata['streams'];
    if (rawStreams is! List || rawStreams.isEmpty) {
      throw const FormatException('WebSocket 영상 목록이 필요합니다');
    }

    final streams = <_PendingStreamInfo>[];
    final indexes = <int>{};
    for (final rawStream in rawStreams) {
      if (rawStream is! Map<String, dynamic>) {
        throw const FormatException('WebSocket 영상 메타데이터가 올바르지 않습니다');
      }
      final payloadIndex = rawStream['payload_index'];
      if (payloadIndex is! int || payloadIndex < 0) {
        throw const FormatException('WebSocket payload_index가 올바르지 않습니다');
      }
      if (!indexes.add(payloadIndex)) {
        throw const FormatException('WebSocket payload_index가 중복되었습니다');
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
          frameSequence: _metadataInt(rawStream['frame_sequence']),
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
        'WebSocket 프레임 데이터 누락: 예상 ${pendingStreams.length}개, 수신 ${_pendingPayloads.length}개';
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
    _notifyListeners();
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
}
