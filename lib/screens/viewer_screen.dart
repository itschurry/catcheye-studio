import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../providers/settings_provider.dart';
import '../services/frame_receiver_service.dart';
import '../widgets/live_viewer.dart';
import '../widgets/point_cloud_viewer.dart';
import '../widgets/stream_selector.dart';

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
  String? _splitLeftStreamKey;
  String? _splitRightStreamKey;

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
          child: StreamSelector(
            receiver: receiver,
            splitView: _splitView,
            splitLeftStreamKey: _splitLeftStreamKey,
            splitRightStreamKey: _splitRightStreamKey,
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
            onSplitViewChanged: (enabled) {
              setState(() {
                _splitView = enabled;
                if (enabled) {
                  _assignInitialSplitStreams(receiver);
                }
              });
            },
            onSplitSelectionChanged: (selection) {
              setState(() {
                _splitLeftStreamKey = selection.leftKey;
                _splitRightStreamKey = selection.rightKey;
              });
            },
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
    final leftStream = _streamByKey(streams, _splitLeftStreamKey);
    final rightStream = _streamByKey(streams, _splitRightStreamKey);

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: _buildSplitPanel(
              receiver: receiver,
              stream: leftStream,
              missingLabel: 'Left',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildSplitPanel(
              receiver: receiver,
              stream: rightStream,
              missingLabel: 'Right',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSplitPanel({
    required FrameReceiverService receiver,
    required ViewerStreamFrame? stream,
    required String missingLabel,
  }) {
    if (stream == null) {
      return MissingSplitPanel(label: missingLabel);
    }
    return SplitStreamPanel(
      stream: stream,
      selected: stream.key == receiver.selectedStreamKey,
      onTap: () => receiver.selectStream(stream.key),
      child: _buildStreamContent(receiver, stream),
    );
  }

  ViewerStreamFrame? _streamByKey(
    List<ViewerStreamFrame> streams,
    String? key,
  ) {
    if (key == null) return null;
    for (final stream in streams) {
      if (stream.key == key) return stream;
    }
    return null;
  }

  void _assignInitialSplitStreams(FrameReceiverService receiver) {
    final streams = receiver.streams.values.toList()
      ..sort((a, b) => a.payloadIndex.compareTo(b.payloadIndex));
    if (streams.isEmpty) return;
    _splitLeftStreamKey ??= receiver.selectedStreamKey ?? streams.first.key;
    _splitRightStreamKey ??= streams.length > 1
        ? streams
              .firstWhere(
                (stream) => stream.key != _splitLeftStreamKey,
                orElse: () => streams.first,
              )
              .key
        : streams.first.key;
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
        selectedFrame.isJpeg) {
      return _buildStreamContent(receiver, selectedFrame);
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
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              stream.jpegBytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
            ),
            if (stream.kind != 'camera' &&
                receiver.detectionPositions.isNotEmpty)
              CustomPaint(
                painter: _DepthDetectionPainter(
                  imageSize: stream.size,
                  detections: receiver.detectionPositions,
                ),
              ),
          ],
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
                onPressed: () => setState(() {
                  _splitView = !_splitView;
                  if (_splitView) {
                    _assignInitialSplitStreams(receiver);
                  }
                }),
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

class _DepthDetectionPainter extends CustomPainter {
  final Size? imageSize;
  final List<DetectionPosition> detections;

  const _DepthDetectionPainter({
    required this.imageSize,
    required this.detections,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final imageSize = this.imageSize;
    if (imageSize == null || imageSize.width <= 0 || imageSize.height <= 0) {
      return;
    }

    final scale =
        (size.width / imageSize.width) < (size.height / imageSize.height)
        ? size.width / imageSize.width
        : size.height / imageSize.height;
    final drawnSize = Size(imageSize.width * scale, imageSize.height * scale);
    final origin = Offset(
      (size.width - drawnSize.width) * 0.5,
      (size.height - drawnSize.height) * 0.5,
    );

    final markerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFFFFEA00);
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0x55FFEA00);

    for (final detection in detections) {
      final x = detection.pointcloudX.toDouble();
      final y = detection.pointcloudY.toDouble();
      if (x < 0 || y < 0 || x >= imageSize.width || y >= imageSize.height) {
        continue;
      }
      final marker = origin + Offset(x * scale, y * scale);
      const markerSize = 9.0;
      canvas.drawCircle(marker, markerSize, fillPaint);
      canvas.drawCircle(marker, markerSize, markerPaint);
      canvas.drawLine(
        Offset(marker.dx - markerSize - 4, marker.dy),
        Offset(marker.dx + markerSize + 4, marker.dy),
        markerPaint,
      );
      canvas.drawLine(
        Offset(marker.dx, marker.dy - markerSize - 4),
        Offset(marker.dx, marker.dy + markerSize + 4),
        markerPaint,
      );
      _drawLabel(canvas, marker, detection);
    }
  }

  void _drawLabel(Canvas canvas, Offset marker, DetectionPosition detection) {
    final text =
        '${detection.className} '
        'x:${detection.x.toStringAsFixed(1)} '
        'y:${detection.y.toStringAsFixed(1)} '
        'z:${detection.z.toStringAsFixed(1)}';
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Color(0xFFFFEA00),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, marker + const Offset(12, -18));
  }

  @override
  bool shouldRepaint(covariant _DepthDetectionPainter oldDelegate) {
    return oldDelegate.imageSize != imageSize ||
        oldDelegate.detections != detections;
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
