import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/frame_receiver_service.dart';
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
  double _axisScale = 100.0;
  double? _depthMin;
  double? _depthMax;
  String? _lastPointCloudKey;
  bool _viewportLocked = false;
  PointCloudViewport? _lockedViewport;
  String? _lockedViewportStreamKey;

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
    final viewer = _buildMainViewer(receiver, selectedFrame);

    if (!receiver.connected ||
        receiver.isRtsp ||
        (!receiver.hasMultiStream && selectedFrame?.isPointCloud != true)) {
      return viewer;
    }

    return Row(
      children: [
        Expanded(child: viewer),
        Container(
          width: 220,
          decoration: const BoxDecoration(
            color: Color(0xFF0B1416),
            border: Border(left: BorderSide(color: Color(0xFF30474B))),
          ),
          child: _StreamSelector(
            receiver: receiver,
            pointSize: _pointSize,
            showAxis: _showAxis,
            axisScale: _axisScale,
            depthMin: _effectiveDepthMin(selectedFrame),
            depthMax: _effectiveDepthMax(selectedFrame),
            viewportLocked: _isViewportLocked(selectedFrame),
            onPointSizeChanged: (value) => setState(() => _pointSize = value),
            onShowAxisChanged: (value) => setState(() => _showAxis = value),
            onAxisScaleChanged: (value) => setState(() => _axisScale = value),
            onDepthRangeChanged: (values) => setState(() {
              _depthMin = values.start;
              _depthMax = values.end;
            }),
            onLockView: () => _lockViewport(selectedFrame),
            onUnlockView: _unlockViewport,
            onResetView: () => _resetViewport(selectedFrame),
          ),
        ),
      ],
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
        minDepth: _effectiveDepthMin(selectedFrame),
        maxDepth: _effectiveDepthMax(selectedFrame),
        viewport: _activeViewport(selectedFrame),
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

  void _syncDepthRange(ViewerStreamFrame? selectedFrame) {
    if (selectedFrame?.isPointCloud != true ||
        selectedFrame?.pointCloud == null) {
      _lastPointCloudKey = null;
      return;
    }
    final key = selectedFrame!.key;
    if (_lastPointCloudKey == key) return;
    _lastPointCloudKey = key;
    _depthMin = selectedFrame.pointCloud!.minZ;
    _depthMax = selectedFrame.pointCloud!.maxZ;
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
          Text(
            receiver.connectedUri?.toString() ?? defaultStreamUrl,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
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
                hintText: 'http://192.168.0.10:8080',
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

class _StreamSelector extends StatelessWidget {
  final FrameReceiverService receiver;
  final double pointSize;
  final bool showAxis;
  final double axisScale;
  final double depthMin;
  final double depthMax;
  final bool viewportLocked;
  final ValueChanged<double> onPointSizeChanged;
  final ValueChanged<bool> onShowAxisChanged;
  final ValueChanged<double> onAxisScaleChanged;
  final ValueChanged<RangeValues> onDepthRangeChanged;
  final VoidCallback onLockView;
  final VoidCallback onUnlockView;
  final VoidCallback onResetView;

  const _StreamSelector({
    required this.receiver,
    required this.pointSize,
    required this.showAxis,
    required this.axisScale,
    required this.depthMin,
    required this.depthMax,
    required this.viewportLocked,
    required this.onPointSizeChanged,
    required this.onShowAxisChanged,
    required this.onAxisScaleChanged,
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
            child: ListView.separated(
              itemCount: streams.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final stream = streams[index];
                final selected = stream.key == receiver.selectedStreamKey;
                return _StreamTile(
                  stream: stream,
                  selected: selected,
                  onTap: () => receiver.selectStream(stream.key),
                );
              },
            ),
          ),
          if (selected?.isPointCloud == true && pointCloud != null) ...[
            const Divider(height: 24),
            _PointCloudOptions(
              pointSize: pointSize,
              showAxis: showAxis,
              axisScale: axisScale,
              depthMin: depthMin,
              depthMax: depthMax,
              dataMinDepth: pointCloud.minZ,
              dataMaxDepth: pointCloud.maxZ,
              viewportLocked: viewportLocked,
              onPointSizeChanged: onPointSizeChanged,
              onShowAxisChanged: onShowAxisChanged,
              onAxisScaleChanged: onAxisScaleChanged,
              onDepthRangeChanged: onDepthRangeChanged,
              onLockView: onLockView,
              onUnlockView: onUnlockView,
              onResetView: onResetView,
            ),
          ],
        ],
      ),
    );
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

class _PointCloudOptions extends StatelessWidget {
  final double pointSize;
  final bool showAxis;
  final double axisScale;
  final double depthMin;
  final double depthMax;
  final double dataMinDepth;
  final double dataMaxDepth;
  final bool viewportLocked;
  final ValueChanged<double> onPointSizeChanged;
  final ValueChanged<bool> onShowAxisChanged;
  final ValueChanged<double> onAxisScaleChanged;
  final ValueChanged<RangeValues> onDepthRangeChanged;
  final VoidCallback onLockView;
  final VoidCallback onUnlockView;
  final VoidCallback onResetView;

  const _PointCloudOptions({
    required this.pointSize,
    required this.showAxis,
    required this.axisScale,
    required this.depthMin,
    required this.depthMax,
    required this.dataMinDepth,
    required this.dataMaxDepth,
    required this.viewportLocked,
    required this.onPointSizeChanged,
    required this.onShowAxisChanged,
    required this.onAxisScaleChanged,
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
          'PointCloud',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: viewportLocked ? onUnlockView : onLockView,
                child: Text(viewportLocked ? 'Unlock' : 'Lock View'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Reset View',
              onPressed: onResetView,
              icon: const Icon(Icons.center_focus_strong, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 8),
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
        _OptionLabel(value: 'Axis scale ${axisScale.toStringAsFixed(0)}'),
        Slider(
          value: axisScale,
          min: 10,
          max: 1000,
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
            textAlign: valueWidth == null ? TextAlign.start : TextAlign.right,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
