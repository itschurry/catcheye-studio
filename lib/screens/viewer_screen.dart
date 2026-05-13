import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../providers/settings_provider.dart';
import '../services/frame_receiver_service.dart';
import '../services/remote_cubeeye_api_service.dart';
import '../widgets/live_viewer.dart';
import '../widgets/point_cloud_viewer.dart';

/// Live preview viewer screen — connects to the remote detector RTSP or WebSocket stream.

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key});

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  double _pointSize = 2.0;
  bool _showAxis = true;
  double _axisScale = AppSettings.defaultPointCloudAxisScale;
  PointCloudPalette _palette = PointCloudPalette.depth;
  double _viewYaw = -0.55;
  double _viewPitch = 0.35;
  double _viewZoom = 1.0;
  Offset _viewPanOffset = Offset.zero;
  double? _depthMin;
  double? _depthMax;
  bool _hasManualDepthRange = false;
  String? _lastPointCloudKey;
  bool _viewportLocked = false;
  PointCloudViewport? _lockedViewport;
  String? _lockedViewportStreamKey;
  bool _pointCloudSettingsLoaded = false;
  bool _splitView = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pointCloudSettingsLoaded) {
      return;
    }
    _pointCloudSettingsLoaded = true;
    final settings = context.read<SettingsProvider>().settings;
    _pointSize = settings.pointCloudPointSize;
    _showAxis = settings.pointCloudShowAxis;
    _axisScale = settings.pointCloudAxisScale.clamp(0.0, 3.0).toDouble();
    _palette = _paletteFromName(settings.pointCloudPalette);
    _depthMin = settings.pointCloudDepthMin;
    _depthMax = settings.pointCloudDepthMax;
    _hasManualDepthRange =
        settings.pointCloudDepthMin != null &&
        settings.pointCloudDepthMax != null;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<FrameReceiverService, SettingsProvider>(
      builder: (context, receiver, settingsProvider, _) {
        final settings = settingsProvider.settings;
        return Column(
          children: [
            // Toolbar
            _buildToolbar(
              context,
              receiver,
              settings.streamUri.toString(),
              settings.detectorBaseUrl,
            ),
            const Divider(height: 1),

            // Frame viewer
            Expanded(child: _buildViewerArea(receiver)),

            // Status bar
            _buildStatusBar(context, receiver, settings.streamUri.toString()),
          ],
        );
      },
    );
  }

  Widget _buildViewerArea(FrameReceiverService receiver) {
    final selectedFrame = receiver.selectedFrame;
    final viewer = _splitView && receiver.connected && receiver.isWebSocket
        ? _buildSplitViewer(receiver)
        : _buildMainViewer(receiver, selectedFrame);

    if (!receiver.connected || receiver.isRtsp) {
      return viewer;
    }

    return Row(
      children: [
        Expanded(child: viewer),
        Container(
          width: 260,
          decoration: const BoxDecoration(
            color: Color(0xFF0B1416),
            border: Border(left: BorderSide(color: Color(0xFF30474B))),
          ),
          child: _StreamSelector(
            receiver: receiver,
            pointSize: _pointSize,
            showAxis: _showAxis,
            axisScale: _axisScale,
            palette: _palette,
            yaw: _viewYaw,
            pitch: _viewPitch,
            zoom: _viewZoom,
            depthMin: _effectiveDepthMin(selectedFrame),
            depthMax: _effectiveDepthMax(selectedFrame),
            viewportLocked: _isViewportLocked(selectedFrame),
            onPointSizeChanged: (value) {
              setState(() => _pointSize = value);
              _persistPointCloudViewerSettings();
            },
            onShowAxisChanged: (value) {
              setState(() => _showAxis = value);
              _persistPointCloudViewerSettings();
            },
            onAxisScaleChanged: (value) {
              setState(() => _axisScale = value);
              _persistPointCloudViewerSettings();
            },
            onPaletteChanged: (value) {
              setState(() => _palette = value);
              _persistPointCloudViewerSettings();
            },
            onYawChanged: (value) => setState(() => _viewYaw = value),
            onPitchChanged: (value) => setState(() => _viewPitch = value),
            onZoomChanged: (value) => setState(() => _viewZoom = value),
            onResetCamera: () => setState(() {
              _viewYaw = -0.55;
              _viewPitch = 0.35;
              _viewZoom = 1.0;
              _viewPanOffset = Offset.zero;
            }),
            onDepthRangeChanged: (values) {
              setState(() {
                _depthMin = values.start;
                _depthMax = values.end;
                _hasManualDepthRange = true;
              });
              _persistPointCloudViewerSettings();
            },
            onLockView: () => _lockViewport(selectedFrame),
            onUnlockView: _unlockViewport,
            onResetView: () => _resetViewport(selectedFrame),
          ),
        ),
      ],
    );
  }

  Widget _buildSplitViewer(FrameReceiverService receiver) {
    final streams = receiver.streams.values.toList()
      ..sort((a, b) => a.payloadIndex.compareTo(b.payloadIndex));
    ViewerStreamFrame? cameraStream;
    ViewerStreamFrame? pointCloudStream;
    for (final stream in streams) {
      if (cameraStream == null &&
          stream.isJpeg &&
          stream.name.toLowerCase() == 'camera') {
        cameraStream = stream;
      }
      if (pointCloudStream == null &&
          stream.isPointCloud &&
          stream.pointCloud != null) {
        pointCloudStream = stream;
      }
    }
    final splitStreams = <ViewerStreamFrame>[?cameraStream, ?pointCloudStream];

    if (splitStreams.isEmpty) {
      return _buildMainViewer(receiver, receiver.selectedFrame);
    }

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          for (var i = 0; i < splitStreams.length; i++) ...[
            Expanded(
              child: _SplitStreamPanel(
                stream: splitStreams[i],
                selected: splitStreams[i].key == receiver.selectedStreamKey,
                onTap: () => receiver.selectStream(splitStreams[i].key),
                child: _buildStreamContent(receiver, splitStreams[i]),
              ),
            ),
            if (i != splitStreams.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildMainViewer(
    FrameReceiverService receiver,
    ViewerStreamFrame? selectedFrame,
  ) {
    _syncDepthRange(selectedFrame);
    if (receiver.connected &&
        !receiver.isRtsp &&
        selectedFrame?.isPointCloud == true &&
        selectedFrame?.pointCloud != null) {
      return PointCloudViewer(
        data: selectedFrame!.pointCloud!,
        pointSize: _pointSize,
        showAxis: _showAxis,
        axisScale: _axisScale,
        palette: _palette,
        minDepth: _effectiveDepthMin(selectedFrame),
        maxDepth: _effectiveDepthMax(selectedFrame),
        viewport: _activeViewport(selectedFrame),
        yaw: _viewYaw,
        pitch: _viewPitch,
        zoom: _viewZoom,
        panOffset: _viewPanOffset,
        detectionPositions: receiver.detectionPositions,
        onViewChanged: (yaw, pitch) => setState(() {
          _viewYaw = yaw;
          _viewPitch = pitch;
        }),
        onZoomChanged: (zoom) => setState(() => _viewZoom = zoom),
        onPanChanged: (offset) => setState(() => _viewPanOffset = offset),
      );
    }

    if (receiver.connected &&
        !receiver.isRtsp &&
        selectedFrame != null &&
        !selectedFrame.isJpeg) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Text(
            'Unsupported stream encoding: ${selectedFrame.encoding.name}',
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return LiveViewer(
      controller: receiver.videoController,
      connected: receiver.connected,
      isRtsp: receiver.isRtsp,
      frameData: selectedFrame?.isJpeg == true
          ? selectedFrame!.jpegBytes
          : receiver.currentFrame,
    );
  }

  Widget _buildStreamContent(
    FrameReceiverService receiver,
    ViewerStreamFrame stream,
  ) {
    if (stream.isPointCloud && stream.pointCloud != null) {
      final minDepth = _hasManualDepthRange
          ? _effectiveDepthMin(stream)
          : stream.pointCloud!.minZ;
      final maxDepth = _hasManualDepthRange
          ? _effectiveDepthMax(stream)
          : stream.pointCloud!.maxZ;
      return PointCloudViewer(
        data: stream.pointCloud!,
        pointSize: _pointSize,
        showAxis: _showAxis,
        axisScale: _axisScale,
        palette: _palette,
        minDepth: minDepth,
        maxDepth: maxDepth,
        viewport: _activeViewport(stream),
        yaw: _viewYaw,
        pitch: _viewPitch,
        zoom: _viewZoom,
        panOffset: _viewPanOffset,
        detectionPositions: receiver.detectionPositions,
        onViewChanged: (yaw, pitch) => setState(() {
          _viewYaw = yaw;
          _viewPitch = pitch;
        }),
        onZoomChanged: (zoom) => setState(() => _viewZoom = zoom),
        onPanChanged: (offset) => setState(() => _viewPanOffset = offset),
      );
    }
    if (stream.isJpeg) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Image.memory(
          stream.jpegBytes,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
        ),
      );
    }
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Text(
        'Unsupported stream encoding: ${stream.encoding.name}',
        style: const TextStyle(color: Colors.grey),
      ),
    );
  }

  void _syncDepthRange(ViewerStreamFrame? selectedFrame) {
    if (selectedFrame?.isPointCloud != true ||
        selectedFrame?.pointCloud == null) {
      _lastPointCloudKey = null;
      return;
    }
    final key = selectedFrame!.key;
    if (_lastPointCloudKey == key) return;
    _lastPointCloudKey = key;
    if (!_hasManualDepthRange) {
      _depthMin = selectedFrame.pointCloud!.minZ;
      _depthMax = selectedFrame.pointCloud!.maxZ;
    }
    if (_lockedViewportStreamKey != key) {
      _viewportLocked = false;
      _lockedViewport = null;
      _lockedViewportStreamKey = null;
    }
  }

  double _effectiveDepthMin(ViewerStreamFrame? selectedFrame) {
    return _depthMin ?? selectedFrame?.pointCloud?.minZ ?? 0;
  }

  double _effectiveDepthMax(ViewerStreamFrame? selectedFrame) {
    return _depthMax ?? selectedFrame?.pointCloud?.maxZ ?? 1;
  }

  bool _isViewportLocked(ViewerStreamFrame? selectedFrame) {
    return _viewportLocked &&
        selectedFrame != null &&
        _lockedViewportStreamKey == selectedFrame.key &&
        _lockedViewport != null;
  }

  PointCloudViewport? _activeViewport(ViewerStreamFrame? selectedFrame) {
    return _isViewportLocked(selectedFrame) ? _lockedViewport : null;
  }

  void _persistPointCloudViewerSettings() {
    unawaited(
      context.read<SettingsProvider>().updatePointCloudViewerSettings(
        pointSize: _pointSize,
        showAxis: _showAxis,
        axisScale: _axisScale,
        palette: _palette.name,
        depthMin: _depthMin,
        depthMax: _depthMax,
      ),
    );
  }

  PointCloudPalette _paletteFromName(String value) {
    return PointCloudPalette.values.firstWhere(
      (palette) => palette.name == value,
      orElse: () => PointCloudPalette.depth,
    );
  }

  void _lockViewport(ViewerStreamFrame? selectedFrame) {
    final viewport = _currentViewport(selectedFrame);
    if (viewport == null || selectedFrame == null) return;
    setState(() {
      _viewportLocked = true;
      _lockedViewport = viewport;
      _lockedViewportStreamKey = selectedFrame.key;
    });
  }

  void _unlockViewport() {
    setState(() {
      _viewportLocked = false;
      _lockedViewport = null;
      _lockedViewportStreamKey = null;
    });
  }

  void _resetViewport(ViewerStreamFrame? selectedFrame) {
    final viewport = _currentViewport(selectedFrame);
    if (viewport == null || selectedFrame == null) return;
    setState(() {
      _lockedViewport = viewport;
      _lockedViewportStreamKey = selectedFrame.key;
      _viewportLocked = true;
    });
  }

  PointCloudViewport? _currentViewport(ViewerStreamFrame? selectedFrame) {
    final pointCloud = selectedFrame?.pointCloud;
    if (pointCloud == null) return null;
    return PointCloudViewport.fromData(
      pointCloud,
      minDepth: _effectiveDepthMin(selectedFrame),
      maxDepth: _effectiveDepthMax(selectedFrame),
    );
  }

  Widget _buildToolbar(
    BuildContext context,
    FrameReceiverService receiver,
    String defaultStreamUrl,
    String defaultApiBaseUrl,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colorScheme.surface,
      child: Row(
        children: [
          Icon(Icons.live_tv, size: 20, color: colorScheme.secondary),
          const SizedBox(width: 8),
          const Text(
            'Live Viewer',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 24),

          // Connection controls
          if (!receiver.connected && !receiver.connecting) ...[
            FilledButton.icon(
              icon: const Icon(Icons.power, size: 16),
              label: const Text('Connect'),
              onPressed: () => receiver.connect(defaultStreamUrl),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.link, size: 16),
              label: const Text('Change URL'),
              onPressed: () => _showConnectDialog(
                context,
                receiver,
                defaultStreamUrl,
                defaultApiBaseUrl,
              ),
            ),
          ] else if (receiver.connecting) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            const Text('Connecting...', style: TextStyle(fontSize: 13)),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.green),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 8, color: Colors.green),
                  SizedBox(width: 6),
                  Text(
                    'Connected',
                    style: TextStyle(fontSize: 12, color: Colors.green),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.power_off, size: 16),
              label: const Text('Disconnect'),
              onPressed: () => receiver.disconnect(),
            ),
          ],

          // Error message
          if (receiver.errorMessage != null)
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 14, color: Colors.red),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      receiver.errorMessage!,
                      style: const TextStyle(fontSize: 11, color: Colors.red),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          const Spacer(),
          if (receiver.connected && receiver.isWebSocket) ...[
            Tooltip(
              message: _splitView ? 'Single view' : 'Split view',
              child: IconButton(
                icon: Icon(
                  _splitView
                      ? Icons.fullscreen_outlined
                      : Icons.splitscreen_outlined,
                ),
                onPressed: () => setState(() => _splitView = !_splitView),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Container(
            height: 38,
            width: 226,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F6F5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colorScheme.primary),
            ),
            child: Image.asset('assets/logo.png', fit: BoxFit.contain),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(
    BuildContext context,
    FrameReceiverService receiver,
    String defaultStreamUrl,
  ) {
    final connected = receiver.connected;
    final inferenceMs = receiver.isWebSocket ? receiver.inferenceMs : null;
    final wallClockText = receiver.isWebSocket ? receiver.wallClockText : null;
    final selectedFrame = receiver.selectedFrame;
    final selectedSize = selectedFrame?.size;
    final resolutionText = selectedSize == null
        ? 'N/A'
        : '${selectedSize.width.toInt()} x ${selectedSize.height.toInt()}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          _StatusChip(
            label: 'Status',
            value: receiver.connected
                ? 'Connected'
                : receiver.connecting
                ? 'Connecting'
                : 'Disconnected',
            valueWidth: 82,
            color: receiver.connected ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 16),
          _StatusChip(
            label: 'FPS',
            value: !connected
                ? '-'
                : receiver.isWebSocket
                ? receiver.fps.toStringAsFixed(1)
                : 'N/A (RTSP)',
            valueWidth: 34,
            color: !connected
                ? Colors.grey
                : receiver.isWebSocket
                ? receiver.fps > 20
                      ? Colors.green
                      : receiver.fps > 10
                      ? Colors.orange
                      : Colors.red
                : Colors.grey,
          ),
          const SizedBox(width: 16),
          _StatusChip(
            label: 'Frames',
            value: !connected
                ? '-'
                : receiver.isWebSocket
                ? '${receiver.frameCount}'
                : 'N/A (RTSP)',
            valueWidth: 72,
            color: connected && receiver.isWebSocket
                ? Colors.cyan
                : Colors.grey,
          ),
          const SizedBox(width: 16),
          _StatusChip(
            label: 'Inference',
            value: !connected
                ? '-'
                : receiver.isWebSocket
                ? inferenceMs == null
                      ? 'N/A'
                      : '${inferenceMs.toStringAsFixed(1)} ms'
                : 'N/A (RTSP)',
            valueWidth: 54,
            color: !connected || inferenceMs == null
                ? Colors.grey
                : inferenceMs <= 33.0
                ? Colors.green
                : inferenceMs <= 100.0
                ? Colors.orange
                : Colors.red,
          ),
          const SizedBox(width: 16),
          _StatusChip(
            label: 'Wall',
            value: !connected
                ? '-'
                : receiver.isWebSocket
                ? wallClockText ?? 'N/A'
                : 'N/A (RTSP)',
            valueWidth: 132,
            color: !connected || wallClockText == null
                ? Colors.grey
                : Colors.lightBlueAccent,
          ),
          const SizedBox(width: 16),
          _StatusChip(
            label: 'Transport',
            value: receiver.isWebSocket
                ? 'WebSocket'
                : receiver.isRtsp
                ? 'RTSP'
                : 'Idle',
            valueWidth: 72,
            color: receiver.connected ? Colors.blueAccent : Colors.grey,
          ),
          const SizedBox(width: 16),
          _StatusChip(
            label: 'Stream',
            value: !connected ? '-' : selectedFrame?.label ?? 'N/A',
            valueWidth: 74,
            color: connected && selectedFrame != null
                ? Colors.lightBlueAccent
                : Colors.grey,
          ),
          const SizedBox(width: 16),
          _StatusChip(
            label: 'Resolution',
            value: !connected ? '-' : resolutionText,
            valueWidth: 82,
            color: connected && selectedSize != null
                ? Colors.cyan
                : Colors.grey,
          ),
          const Spacer(),
          SizedBox(
            width: 230,
            child: Text(
              receiver.connectedUri?.toString() ?? defaultStreamUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  void _showConnectDialog(
    BuildContext context,
    FrameReceiverService receiver,
    String defaultStreamUrl,
    String defaultApiBaseUrl,
  ) {
    final streamController = TextEditingController(text: defaultStreamUrl);
    final apiController = TextEditingController(text: defaultApiBaseUrl);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Connect'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: streamController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Stream URL',
                hintText:
                    'rtsp://192.168.0.10:8554/live  또는  ws://192.168.0.10:8080/',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: apiController,
              decoration: const InputDecoration(
                labelText: 'API Base URL',
                hintText: 'http://192.168.0.10:8090',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final sp = context.read<SettingsProvider>();
              final streamUrl = streamController.text.trim();
              await sp.updateConnectionUrls(
                streamPath: streamUrl,
                detectorBaseUrl: apiController.text.trim(),
              );
              receiver.connect(streamUrl);
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }
}

class _SplitStreamPanel extends StatelessWidget {
  final ViewerStreamFrame stream;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  const _SplitStreamPanel({
    required this.stream,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = stream.size;
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(
            color: selected ? colorScheme.primary : const Color(0xFF30474B),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              color: selected
                  ? const Color(0xFF183C42)
                  : const Color(0xFF101B1D),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      stream.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: selected ? colorScheme.primary : Colors.white,
                      ),
                    ),
                  ),
                  Text(
                    stream.isPointCloud
                        ? '${stream.pointCount} pts'
                        : size == null
                        ? '-'
                        : '${size.width.toInt()} x ${size.height.toInt()}',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _StreamSelector extends StatelessWidget {
  final FrameReceiverService receiver;
  final double pointSize;
  final bool showAxis;
  final double axisScale;
  final PointCloudPalette palette;
  final double yaw;
  final double pitch;
  final double zoom;
  final double depthMin;
  final double depthMax;
  final bool viewportLocked;
  final ValueChanged<double> onPointSizeChanged;
  final ValueChanged<bool> onShowAxisChanged;
  final ValueChanged<double> onAxisScaleChanged;
  final ValueChanged<PointCloudPalette> onPaletteChanged;
  final ValueChanged<double> onYawChanged;
  final ValueChanged<double> onPitchChanged;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onResetCamera;
  final ValueChanged<RangeValues> onDepthRangeChanged;
  final VoidCallback onLockView;
  final VoidCallback onUnlockView;
  final VoidCallback onResetView;

  const _StreamSelector({
    required this.receiver,
    required this.pointSize,
    required this.showAxis,
    required this.axisScale,
    required this.palette,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.depthMin,
    required this.depthMax,
    required this.viewportLocked,
    required this.onPointSizeChanged,
    required this.onShowAxisChanged,
    required this.onAxisScaleChanged,
    required this.onPaletteChanged,
    required this.onYawChanged,
    required this.onPitchChanged,
    required this.onZoomChanged,
    required this.onResetCamera,
    required this.onDepthRangeChanged,
    required this.onLockView,
    required this.onUnlockView,
    required this.onResetView,
  });

  @override
  Widget build(BuildContext context) {
    final streams = receiver.streams.values.toList()
      ..sort((a, b) => a.payloadIndex.compareTo(b.payloadIndex));
    final selected = receiver.selectedFrame;
    final pointCloud = selected?.pointCloud;
    final hasCubeEyeStream = streams.any(_isCubeEyeStream);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.view_sidebar_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(width: 8),
              const Text(
                'Streams',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                for (var i = 0; i < streams.length; i++) ...[
                  _StreamTile(
                    stream: streams[i],
                    selected: streams[i].key == receiver.selectedStreamKey,
                    onTap: () => receiver.selectStream(streams[i].key),
                  ),
                  if (i != streams.length - 1) const SizedBox(height: 10),
                ],
                if (hasCubeEyeStream) ...[
                  const Divider(height: 24),
                  const _CubeEyeControls(),
                ],
                if (selected?.isPointCloud == true && pointCloud != null) ...[
                  const Divider(height: 24),
                  _PointCloudOptions(
                    pointSize: pointSize,
                    showAxis: showAxis,
                    axisScale: axisScale,
                    palette: palette,
                    yaw: yaw,
                    pitch: pitch,
                    zoom: zoom,
                    depthMin: depthMin,
                    depthMax: depthMax,
                    dataMinDepth: pointCloud.minZ,
                    dataMaxDepth: pointCloud.maxZ,
                    viewportLocked: viewportLocked,
                    onPointSizeChanged: onPointSizeChanged,
                    onShowAxisChanged: onShowAxisChanged,
                    onAxisScaleChanged: onAxisScaleChanged,
                    onPaletteChanged: onPaletteChanged,
                    onYawChanged: onYawChanged,
                    onPitchChanged: onPitchChanged,
                    onZoomChanged: onZoomChanged,
                    onResetCamera: onResetCamera,
                    onDepthRangeChanged: onDepthRangeChanged,
                    onLockView: onLockView,
                    onUnlockView: onUnlockView,
                    onResetView: onResetView,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isCubeEyeStream(ViewerStreamFrame stream) {
    final kind = stream.kind.toLowerCase();
    final name = stream.name.toLowerCase();
    return kind == 'depth' ||
        kind == 'amplitude' ||
        kind == 'rgb' ||
        kind == 'pointcloud' ||
        name.contains('cubeeye');
  }
}

class _StreamTile extends StatelessWidget {
  final ViewerStreamFrame stream;
  final bool selected;
  final VoidCallback onTap;

  const _StreamTile({
    required this.stream,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = stream.size;
    final isPointCloud = stream.isPointCloud;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF183C42) : const Color(0xFF101B1D),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? colorScheme.primary : const Color(0xFF30474B),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(5),
                ),
                child: Container(
                  color: Colors.black,
                  child: isPointCloud
                      ? const Center(
                          child: Icon(
                            Icons.scatter_plot,
                            color: Color(0xFF73D4DC),
                            size: 34,
                          ),
                        )
                      : Image.memory(
                          stream.jpegBytes,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.low,
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      stream.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: selected ? colorScheme.primary : Colors.white,
                      ),
                    ),
                  ),
                  Text(
                    isPointCloud
                        ? '${stream.pointCount} pts'
                        : size == null
                        ? '-'
                        : '${size.width.toInt()} x ${size.height.toInt()}',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CubeEyeControls extends StatefulWidget {
  const _CubeEyeControls();

  @override
  State<_CubeEyeControls> createState() => _CubeEyeControlsState();
}

class _CubeEyeControlsState extends State<_CubeEyeControls> {
  final RemoteCubeEyeApiService _api = RemoteCubeEyeApiService();
  final TextEditingController _depthMinController = TextEditingController();
  final TextEditingController _depthMaxController = TextEditingController();
  final Map<String, TextEditingController> _propertyControllers = {};
  CubeEyeProperties? _properties;
  String? _error;
  bool _loading = false;
  bool _loadedOnce = false;
  bool _initializedFromSettings = false;

  static const _boolProperties = <_CubeEyePropertySpec>[
    _CubeEyePropertySpec('amplitude_time_filter', 'Amplitude time filter'),
    _CubeEyePropertySpec('depth_average_median_filter', 'Depth median filter'),
    _CubeEyePropertySpec('depth_time_filter', 'Depth time filter'),
    _CubeEyePropertySpec('flying_pixel_remove_filter', 'Flying pixel filter'),
    _CubeEyePropertySpec('noise_filter1', 'Noise filter 1'),
    _CubeEyePropertySpec('noise_filter2', 'Noise filter 2'),
    _CubeEyePropertySpec('noise_filter3', 'Noise filter 3'),
  ];

  static const _numericProperties = <_CubeEyePropertySpec>[
    _CubeEyePropertySpec('amplitude_threshold_min', 'Amplitude threshold min'),
    _CubeEyePropertySpec('amplitude_threshold_max', 'Amplitude threshold max'),
    _CubeEyePropertySpec(
      'amplitude_time_spatial_threshold',
      'Amplitude spatial threshold',
      isFloat: true,
    ),
    _CubeEyePropertySpec(
      'amplitude_time_temporal_threshold',
      'Amplitude temporal threshold',
      isFloat: true,
    ),
    _CubeEyePropertySpec('depth_average_median_max_n', 'Depth median frames'),
    _CubeEyePropertySpec('depth_offset', 'Depth offset'),
    _CubeEyePropertySpec(
      'depth_time_spatial_threshold',
      'Depth spatial threshold',
      isFloat: true,
    ),
    _CubeEyePropertySpec(
      'depth_time_temporal_threshold',
      'Depth temporal threshold',
      isFloat: true,
    ),
    _CubeEyePropertySpec(
      'flying_pixel_remove_threshold',
      'Flying pixel threshold',
    ),
    _CubeEyePropertySpec('integration_time', 'Integration time'),
    _CubeEyePropertySpec('motion_blur_frequency', 'Motion blur frequency'),
    _CubeEyePropertySpec('motion_blur_threshold', 'Motion blur threshold'),
    _CubeEyePropertySpec('motion_blur_threshold2', 'Motion blur threshold 2'),
    _CubeEyePropertySpec('scattering_threshold', 'Scattering threshold'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_loadedOnce) {
        _load();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initializedFromSettings) {
      return;
    }
    _initializedFromSettings = true;
    final settings = context.read<SettingsProvider>().settings;
    _apply(
      CubeEyeProperties(
        framerate: settings.cubeEyeFramerate,
        autoExposure: settings.cubeEyeAutoExposure,
        illumination: settings.cubeEyeIllumination,
        depthRangeMin: settings.cubeEyeDepthRangeMin,
        depthRangeMax: settings.cubeEyeDepthRangeMax,
        values: {
          'framerate': settings.cubeEyeFramerate,
          'auto_exposure': settings.cubeEyeAutoExposure,
          'illumination': settings.cubeEyeIllumination,
          'depth_range_min': settings.cubeEyeDepthRangeMin,
          'depth_range_max': settings.cubeEyeDepthRangeMax,
        },
      ),
      persist: false,
    );
  }

  @override
  void dispose() {
    _depthMinController.dispose();
    _depthMaxController.dispose();
    for (final controller in _propertyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final properties = _properties;
    final controlsEnabled = properties != null && !_loading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'CubeEye',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _loading ? null : _load,
              icon: _loading
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 16),
              label: const Text('Load'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_error != null)
          Text(
            _error!,
            style: const TextStyle(fontSize: 11, color: Colors.redAccent),
          ),
        const SizedBox(height: 8),
        const Text('Framerate', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 6),
        SegmentedButton<int>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(value: 7, label: Text('7')),
            ButtonSegment(value: 15, label: Text('15')),
            ButtonSegment(value: 30, label: Text('30')),
          ],
          selected: {properties?.framerate ?? 15},
          onSelectionChanged: controlsEnabled
              ? (selection) => _setProperty('framerate', selection.first)
              : null,
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Auto exposure', style: TextStyle(fontSize: 12)),
          value: properties?.autoExposure ?? false,
          onChanged: controlsEnabled
              ? (value) => _setProperty('auto_exposure', value)
              : null,
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Illumination', style: TextStyle(fontSize: 12)),
          value: properties?.illumination ?? false,
          onChanged: controlsEnabled
              ? (value) => _setProperty('illumination', value)
              : null,
        ),
        const Text('Depth range', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _depthMinController,
                enabled: controlsEnabled,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Min',
                  isDense: true,
                ),
                onSubmitted: (value) =>
                    _setIntProperty('depth_range_min', value),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _depthMaxController,
                enabled: controlsEnabled,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Max',
                  isDense: true,
                ),
                onSubmitted: (value) =>
                    _setIntProperty('depth_range_max', value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Divider(height: 18),
        const Text('Image quality', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 6),
        ..._boolProperties
            .where((spec) => properties?.values.containsKey(spec.key) ?? false)
            .map(
              (spec) => SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(spec.label, style: const TextStyle(fontSize: 12)),
                value: (properties?.values[spec.key] as bool?) ?? false,
                onChanged: controlsEnabled
                    ? (value) => _setProperty(spec.key, value)
                    : null,
              ),
            ),
        ..._numericProperties
            .where((spec) => properties?.values.containsKey(spec.key) ?? false)
            .map(
              (spec) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: _controllerFor(spec.key),
                  enabled: controlsEnabled,
                  keyboardType: TextInputType.numberWithOptions(
                    signed: true,
                    decimal: spec.isFloat,
                  ),
                  decoration: InputDecoration(
                    labelText: spec.label,
                    isDense: true,
                  ),
                  onSubmitted: (value) => spec.isFloat
                      ? _setDoubleProperty(spec.key, value)
                      : _setIntProperty(spec.key, value),
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _load() async {
    _loadedOnce = true;
    await _run(() async {
      final settings = context.read<SettingsProvider>().settings;
      await _apply(await _api.fetchProperties(settings));
    });
  }

  Future<void> _setProperty(String key, Object value) async {
    await _run(() async {
      final settings = context.read<SettingsProvider>().settings;
      await _apply(await _api.setProperty(settings, key, value));
    });
  }

  Future<void> _setIntProperty(String key, String value) async {
    final parsed = int.tryParse(value.trim());
    if (parsed == null) {
      setState(() => _error = 'Invalid integer');
      return;
    }
    await _setProperty(key, parsed);
  }

  Future<void> _setDoubleProperty(String key, String value) async {
    final parsed = double.tryParse(value.trim());
    if (parsed == null) {
      setState(() => _error = 'Invalid number');
      return;
    }
    await _setProperty(key, parsed);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _apply(
    CubeEyeProperties properties, {
    bool persist = true,
  }) async {
    setState(() {
      _properties = properties;
      _depthMinController.text = properties.depthRangeMin.toString();
      _depthMaxController.text = properties.depthRangeMax.toString();
      for (final spec in _numericProperties) {
        if (properties.values.containsKey(spec.key)) {
          _controllerFor(spec.key).text = properties.values[spec.key]
              .toString();
        }
      }
    });
    if (!persist) {
      return;
    }
    await context.read<SettingsProvider>().updateCubeEyeSettings(
      framerate: properties.framerate,
      autoExposure: properties.autoExposure,
      illumination: properties.illumination,
      depthRangeMin: properties.depthRangeMin,
      depthRangeMax: properties.depthRangeMax,
    );
  }

  TextEditingController _controllerFor(String key) {
    return _propertyControllers.putIfAbsent(key, () => TextEditingController());
  }
}

class _CubeEyePropertySpec {
  final String key;
  final String label;
  final bool isFloat;

  const _CubeEyePropertySpec(this.key, this.label, {this.isFloat = false});
}

class _PointCloudOptions extends StatelessWidget {
  final double pointSize;
  final bool showAxis;
  final double axisScale;
  final PointCloudPalette palette;
  final double yaw;
  final double pitch;
  final double zoom;
  final double depthMin;
  final double depthMax;
  final double dataMinDepth;
  final double dataMaxDepth;
  final bool viewportLocked;
  final ValueChanged<double> onPointSizeChanged;
  final ValueChanged<bool> onShowAxisChanged;
  final ValueChanged<double> onAxisScaleChanged;
  final ValueChanged<PointCloudPalette> onPaletteChanged;
  final ValueChanged<double> onYawChanged;
  final ValueChanged<double> onPitchChanged;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onResetCamera;
  final ValueChanged<RangeValues> onDepthRangeChanged;
  final VoidCallback onLockView;
  final VoidCallback onUnlockView;
  final VoidCallback onResetView;

  const _PointCloudOptions({
    required this.pointSize,
    required this.showAxis,
    required this.axisScale,
    required this.palette,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.depthMin,
    required this.depthMax,
    required this.dataMinDepth,
    required this.dataMaxDepth,
    required this.viewportLocked,
    required this.onPointSizeChanged,
    required this.onShowAxisChanged,
    required this.onAxisScaleChanged,
    required this.onPaletteChanged,
    required this.onYawChanged,
    required this.onPitchChanged,
    required this.onZoomChanged,
    required this.onResetCamera,
    required this.onDepthRangeChanged,
    required this.onLockView,
    required this.onUnlockView,
    required this.onResetView,
  });

  @override
  Widget build(BuildContext context) {
    final rangeStart = dataMinDepth == dataMaxDepth
        ? dataMinDepth - 1.0
        : dataMinDepth;
    final rangeEnd = dataMinDepth == dataMaxDepth
        ? dataMaxDepth + 1.0
        : dataMaxDepth;
    final safeDepthMin = depthMin.clamp(rangeStart, rangeEnd).toDouble();
    final safeDepthMax = depthMax.clamp(rangeStart, rangeEnd).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'PointCloud 3D',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: viewportLocked ? onUnlockView : onLockView,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    viewportLocked ? 'Unlock' : 'Lock View',
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Reset View',
              onPressed: onResetView,
              icon: const Icon(Icons.center_focus_strong, size: 18),
            ),
            IconButton(
              tooltip: 'Reset Camera',
              onPressed: onResetCamera,
              icon: const Icon(Icons.threed_rotation, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SegmentedButton<PointCloudPalette>(
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
          ),
          segments: const [
            ButtonSegment(
              value: PointCloudPalette.depth,
              label: Text('Depth', maxLines: 1, softWrap: false),
            ),
            ButtonSegment(
              value: PointCloudPalette.x,
              label: Text('X', maxLines: 1, softWrap: false),
            ),
            ButtonSegment(
              value: PointCloudPalette.y,
              label: Text('Y', maxLines: 1, softWrap: false),
            ),
            ButtonSegment(
              value: PointCloudPalette.grayscale,
              label: Text('Gray', maxLines: 1, softWrap: false),
            ),
          ],
          selected: {palette},
          onSelectionChanged: (selection) => onPaletteChanged(selection.first),
        ),
        const SizedBox(height: 8),
        _OptionLabel(
          value:
              'Yaw ${(yaw * 180 / 3.141592653589793).toStringAsFixed(0)} deg',
        ),
        Slider(
          value: yaw,
          min: -3.141592653589793,
          max: 3.141592653589793,
          onChanged: onYawChanged,
        ),
        _OptionLabel(
          value:
              'Pitch ${(pitch * 180 / 3.141592653589793).toStringAsFixed(0)} deg',
        ),
        Slider(
          value: pitch,
          min: -3.141592653589793,
          max: 3.141592653589793,
          onChanged: onPitchChanged,
        ),
        _OptionLabel(value: 'Zoom ${zoom.toStringAsFixed(1)}x'),
        Slider(value: zoom, min: 0.2, max: 8.0, onChanged: onZoomChanged),
        _OptionLabel(value: 'Point size ${pointSize.toStringAsFixed(1)}'),
        Slider(
          value: pointSize,
          min: 0.5,
          max: 6.0,
          onChanged: onPointSizeChanged,
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Axis', style: TextStyle(fontSize: 12)),
          value: showAxis,
          onChanged: onShowAxisChanged,
        ),
        _OptionLabel(value: 'Axis scale ${axisScale.toStringAsFixed(1)} m'),
        Slider(
          value: axisScale.clamp(0.0, 3.0).toDouble(),
          min: 0,
          max: 3,
          onChanged: onAxisScaleChanged,
        ),
        _OptionLabel(
          value:
              'Depth ${safeDepthMin.toStringAsFixed(1)} - ${safeDepthMax.toStringAsFixed(1)}',
        ),
        RangeSlider(
          values: RangeValues(safeDepthMin, safeDepthMax),
          min: rangeStart,
          max: rangeEnd,
          onChanged: onDepthRangeChanged,
        ),
      ],
    );
  }
}

class _OptionLabel extends StatelessWidget {
  final String value;

  const _OptionLabel({required this.value});

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      style: const TextStyle(fontSize: 11, color: Colors.grey),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final double? valueWidth;

  const _StatusChip({
    required this.label,
    required this.value,
    required this.color,
    this.valueWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        SizedBox(
          width: valueWidth,
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: valueWidth == null ? TextAlign.start : TextAlign.right,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }
}
