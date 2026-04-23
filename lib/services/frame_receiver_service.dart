import 'dart:async';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

enum StreamTransport { rtsp, websocket }

/// Receives RTSP streams via media_kit or JPEG frames over WebSocket.
class FrameReceiverService extends ChangeNotifier {
  final Player _player = Player();
  late final VideoController _videoController = VideoController(_player);

  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<dynamic>? _webSocketSubscription;
  WebSocket? _webSocket;
  Timer? _fpsTimer;
  bool _closingWebSocket = false;
  bool _connected = false;
  bool _connecting = false;
  String? _errorMessage;
  Uri? _connectedUri;
  Uint8List? _currentFrame;
  int _frameCount = 0;
  int _fps = 0;
  int _framesThisSecond = 0;
  StreamTransport? _transport;

  Size? _frameSize;

  bool get connected => _connected;
  bool get connecting => _connecting;
  String? get errorMessage => _errorMessage;
  Uint8List? get currentFrame => _currentFrame;
  int get frameCount => _frameCount;
  int get fps => _fps;
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
    _framesThisSecond = 0;
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
    _fpsTimer?.cancel();
    _fpsTimer = null;
    await _webSocketSubscription?.cancel();
    _webSocketSubscription = null;
    await _closeWebSocket();
    await _player.stop();
    _connectedUri = null;
    _currentFrame = null;
    _frameCount = 0;
    _fps = 0;
    _framesThisSecond = 0;
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
    _startFpsCounter();

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
      return;
    }

    if (data is List<int>) {
      _currentFrame = Uint8List.fromList(data);
      _frameCount++;
      _framesThisSecond++;
      if (_frameSize == null) {
        final detected = _parseJpegSize(_currentFrame!);
        if (detected != null) {
          _frameSize = detected;
        }
      }
      notifyListeners();
    }
  }

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
      if (marker >= 0xC0 && marker <= 0xC3 && segLen >= 7 && i + 9 <= bytes.length) {
        final h = (bytes[i + 5] << 8) | bytes[i + 6];
        final w = (bytes[i + 7] << 8) | bytes[i + 8];
        if (w > 0 && h > 0) return Size(w.toDouble(), h.toDouble());
      }
      i += 2 + segLen;
    }
    return null;
  }

  void _startFpsCounter() {
    _fpsTimer?.cancel();
    _framesThisSecond = 0;
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _fps = _framesThisSecond;
      _framesThisSecond = 0;
      notifyListeners();
    });
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
    _fpsTimer?.cancel();
    _webSocketSubscription?.cancel();
    _webSocket?.close();
    _player.dispose();
    super.dispose();
  }
}
