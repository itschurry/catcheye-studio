import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/frame_receiver_service.dart';
import '../widgets/live_viewer.dart';

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key, this.isPhone = false});

  final bool isPhone;

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  final List<_MonitorCamera> _cameras = [];
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) {
      return;
    }
    _loaded = true;
    final settings = context.read<SettingsProvider>().settings;
    _replaceCameras(settings.guardMonitorStreams, connect: true);
  }

  @override
  void dispose() {
    for (final camera in _cameras) {
      camera.receiver.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildToolbar(context, isPhone: widget.isPhone),
        const Divider(height: 1),
        Expanded(
          child: _cameras.isEmpty
              ? const _EmptyMonitor()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 1500
                        ? 3
                        : constraints.maxWidth >= 900
                        ? 2
                        : 1;
                    return GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 16 / 10,
                      ),
                      itemCount: _cameras.length,
                      itemBuilder: (context, index) {
                        return _MonitorCameraTile(
                          camera: _cameras[index],
                          index: index,
                          onConnect: () => _connect(index),
                          onDisconnect: () => _disconnect(index),
                          onRemove: () => _removeCamera(index),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context, {required bool isPhone}) {
    if (isPhone) {
      return _buildPhoneToolbar(context);
    }

    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colorScheme.surface,
      child: Row(
        children: [
          Icon(Icons.grid_view, size: 20, color: colorScheme.secondary),
          const SizedBox(width: 8),
          const Text(
            'Guard Monitor',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          OutlinedButton.icon(
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('Connect All'),
            onPressed: _cameras.isEmpty ? null : _connectAll,
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.stop, size: 16),
            label: const Text('Disconnect All'),
            onPressed: _cameras.isEmpty ? null : _disconnectAll,
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Camera'),
            onPressed: () => _showAddCameraDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneToolbar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: colorScheme.surface,
      child: Row(
        children: [
          Icon(Icons.grid_view, size: 22, color: colorScheme.secondary),
          const SizedBox(width: 8),
          const Flexible(
            child: Text(
              'Monitor',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: 'Connect all',
                    child: IconButton.outlined(
                      icon: const Icon(Icons.play_arrow, size: 20),
                      onPressed: _cameras.isEmpty ? null : _connectAll,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Disconnect all',
                    child: IconButton.outlined(
                      icon: const Icon(Icons.stop, size: 20),
                      onPressed: _cameras.isEmpty ? null : _disconnectAll,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Add camera',
                    child: IconButton.filled(
                      icon: const Icon(Icons.add, size: 20),
                      onPressed: () => _showAddCameraDialog(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddCameraDialog(BuildContext context) async {
    final settings = context.read<SettingsProvider>().settings;
    final controller = TextEditingController(
      text: settings.streamUri.toString(),
    );
    final streamUrl = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add camera'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Stream URL',
              hintText: 'ws://192.168.1.10:8080/',
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (streamUrl == null || streamUrl.isEmpty) {
      return;
    }
    await _addCamera(streamUrl);
  }

  Future<void> _addCamera(String streamUrl) async {
    final camera = _MonitorCamera(streamUrl: streamUrl);
    setState(() => _cameras.add(camera));
    await _saveStreams();
    unawaited(camera.receiver.connect(streamUrl));
  }

  Future<void> _removeCamera(int index) async {
    final camera = _cameras.removeAt(index);
    setState(() {});
    await camera.receiver.disconnect();
    camera.receiver.dispose();
    await _saveStreams();
  }

  void _replaceCameras(List<String> streams, {required bool connect}) {
    for (final camera in _cameras) {
      camera.receiver.dispose();
    }
    _cameras
      ..clear()
      ..addAll(streams.map((stream) => _MonitorCamera(streamUrl: stream)));
    if (connect) {
      for (final camera in _cameras) {
        unawaited(camera.receiver.connect(camera.streamUrl));
      }
    }
  }

  Future<void> _saveStreams() {
    return context.read<SettingsProvider>().updateGuardMonitorStreams(
      _cameras.map((camera) => camera.streamUrl).toList(growable: false),
    );
  }

  void _connect(int index) {
    final camera = _cameras[index];
    unawaited(camera.receiver.connect(camera.streamUrl));
  }

  void _disconnect(int index) {
    unawaited(_cameras[index].receiver.disconnect());
  }

  void _connectAll() {
    for (final camera in _cameras) {
      unawaited(camera.receiver.connect(camera.streamUrl));
    }
  }

  void _disconnectAll() {
    for (final camera in _cameras) {
      unawaited(camera.receiver.disconnect());
    }
  }
}

class _MonitorCamera {
  _MonitorCamera({required this.streamUrl}) : receiver = FrameReceiverService();

  final String streamUrl;
  final FrameReceiverService receiver;
}

class _MonitorCameraTile extends StatelessWidget {
  const _MonitorCameraTile({
    required this.camera,
    required this.index,
    required this.onConnect,
    required this.onDisconnect,
    required this.onRemove,
  });

  final _MonitorCamera camera;
  final int index;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: camera.receiver,
      builder: (context, _) {
        final receiver = camera.receiver;
        final frame = receiver.selectedFrame;
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF4A4A4A)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TileHeader(
                title: 'Camera ${index + 1}',
                streamUrl: camera.streamUrl,
                receiver: receiver,
                onConnect: onConnect,
                onDisconnect: onDisconnect,
                onRemove: onRemove,
              ),
              Expanded(
                child: LiveViewer(
                  controller: receiver.videoController,
                  connected: receiver.connected,
                  isRtsp: receiver.isRtsp,
                  frameData: frame?.isJpeg == true
                      ? frame!.jpegBytes
                      : receiver.currentFrame,
                  fit: BoxFit.contain,
                ),
              ),
              _TileFooter(receiver: receiver),
            ],
          ),
        );
      },
    );
  }
}

class _TileHeader extends StatelessWidget {
  const _TileHeader({
    required this.title,
    required this.streamUrl,
    required this.receiver,
    required this.onConnect,
    required this.onDisconnect,
    required this.onRemove,
  });

  final String title;
  final String streamUrl;
  final FrameReceiverService receiver;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: const Color(0xFF252525),
      child: Row(
        children: [
          Icon(
            receiver.connected ? Icons.videocam : Icons.videocam_off,
            size: 18,
            color: receiver.connected ? Colors.greenAccent : Colors.grey,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  streamUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: receiver.connected ? 'Disconnect' : 'Connect',
            icon: Icon(receiver.connected ? Icons.stop : Icons.play_arrow),
            onPressed: receiver.connecting
                ? null
                : receiver.connected
                ? onDisconnect
                : onConnect,
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _TileFooter extends StatelessWidget {
  const _TileFooter({required this.receiver});

  final FrameReceiverService receiver;

  @override
  Widget build(BuildContext context) {
    final frame = receiver.selectedFrame;
    final size = frame?.size;
    final error = receiver.errorMessage;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: const Color(0xFF252525),
      child: Row(
        children: [
          _FooterText(
            receiver.connected
                ? receiver.isWebSocket
                      ? '${receiver.fps.toStringAsFixed(1)} fps'
                      : 'RTSP'
                : receiver.connecting
                ? 'connecting'
                : 'idle',
          ),
          const SizedBox(width: 12),
          if (size != null)
            _FooterText('${size.width.toInt()} x ${size.height.toInt()}'),
          if (error != null) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                error,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Colors.redAccent),
              ),
            ),
          ] else
            const Spacer(),
        ],
      ),
    );
  }
}

class _FooterText extends StatelessWidget {
  const _FooterText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 10, color: Colors.grey),
    );
  }
}

class _EmptyMonitor extends StatelessWidget {
  const _EmptyMonitor();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('No cameras', style: TextStyle(color: Colors.grey)),
    );
  }
}
