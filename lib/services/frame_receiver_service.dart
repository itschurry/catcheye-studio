import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Receives and plays RTSP streams using media_kit.
class FrameReceiverService extends ChangeNotifier {
  final Player _player = Player();
  late final VideoController _videoController = VideoController(_player);

  StreamSubscription<bool>? _playingSubscription;
  bool _connected = false;
  bool _connecting = false;
  String? _errorMessage;
  Uri? _connectedUri;

  bool get connected => _connected;
  bool get connecting => _connecting;
  String? get errorMessage => _errorMessage;
  int get frameCount => 0;
  int get fps => 0;
  Uri? get connectedUri => _connectedUri;
  VideoController get videoController => _videoController;

  static const String defaultStreamUrl = 'rtsp://127.0.0.1:8554/live';

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
    notifyListeners();

    try {
      final uri = _normalizeUri(streamUrl);
      await _player.open(Media(uri.toString()), play: true);

      _connected = true;
      _connecting = false;
      _errorMessage = null;
      _connectedUri = uri;
      notifyListeners();
    } catch (e) {
      _connecting = false;
      _connected = false;
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
    await _player.stop();
    _connected = false;
    _connecting = false;
    _connectedUri = null;
  }

  Uri _normalizeUri(String rawUrl) {
    final trimmed = rawUrl.trim();
    final normalized = trimmed.startsWith('rtsp://') ||
            trimmed.startsWith('rtsps://') ||
            trimmed.startsWith('http://') ||
            trimmed.startsWith('https://')
        ? trimmed
        : 'rtsp://$trimmed';
    return Uri.parse(normalized);
  }

  @override
  void dispose() {
    _playingSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }
}
