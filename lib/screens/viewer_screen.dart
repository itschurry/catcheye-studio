import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../models/station_viewer_layout.dart';
import '../providers/settings_provider.dart';
import '../services/frame_receiver_service.dart';
import '../services/remote_capture_api_service.dart';
import '../services/remote_device_info_service.dart';
import '../services/remote_recording_api_service.dart';
import '../widgets/live_viewer.dart';
import '../widgets/point_cloud_viewer.dart';
import '../widgets/stream_selector.dart';

/// Live preview viewer screen — connects to the remote detector RTSP or WebSocket stream.

const double _streamSelectorPanelWidth = 380;

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({
    super.key,
    required this.reconnectToken,
    required this.isPhone,
    this.initialStreamUrl,
  });

  final int reconnectToken;
  final bool isPhone;
  final String? initialStreamUrl;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen>
    with SingleTickerProviderStateMixin {
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
  RemoteRecordingStatus? _recordingStatus;
  bool _recordingActionInFlight = false;
  bool _captureActionInFlight = false;
  final RemoteCaptureApiService _captureApi = RemoteCaptureApiService();
  bool _isInspectionStation = false;
  StationCaptureStatus? _stationStatus;
  StationViewerSource? _stationViewerSource;
  StationViewerLayout _stationViewerLayout = StationViewerLayout.oneByOne;
  List<String> _stationCameraSlots = const [''];
  final Map<String, StationCaptureResult> _stationCycles = {};
  String? _selectedStationCycleId;
  String _stationCaptureTarget = 'all';
  String? _stationError;
  bool _stationSourceActionInFlight = false;
  bool _stationPollInFlight = false;
  Timer? _stationPollTimer;
  int _stationSession = 0;
  String? _stationApiBaseUrl;
  int _handledReconnectToken = 0;
  late final AnimationController _roiAlertBlinkController;
  late final Animation<double> _roiAlertOpacity;

  @override
  void initState() {
    super.initState();
    _roiAlertBlinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);
    _roiAlertOpacity = Tween<double>(begin: 0.32, end: 1.0).animate(
      CurvedAnimation(
        parent: _roiAlertBlinkController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _stationPollTimer?.cancel();
    _captureApi.close();
    _roiAlertBlinkController.dispose();
    super.dispose();
  }

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
    _stationViewerLayout = settings.stationViewerLayout;
    _stationCameraSlots = resizeStationCameraSlots(
      _stationViewerLayout,
      settings.stationViewerCameraSlots,
    );
    _connectAfterTabReturn();
  }

  @override
  void didUpdateWidget(covariant ViewerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _connectAfterTabReturn();
  }

  void _connectAfterTabReturn() {
    if (widget.reconnectToken == 0 ||
        _handledReconnectToken == widget.reconnectToken) {
      return;
    }
    _handledReconnectToken = widget.reconnectToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final receiver = context.read<FrameReceiverService>();
      if (receiver.connected || receiver.connecting) return;
      final settings = context.read<SettingsProvider>().settings;
      unawaited(
        _connect(
          context: context,
          receiver: receiver,
          streamPath: widget.initialStreamUrl ?? settings.streamUri.toString(),
          apiBaseUrl: widget.initialStreamUrl == null
              ? settings.detectorBaseUrl
              : null,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<FrameReceiverService, SettingsProvider>(
      builder: (context, receiver, settingsProvider, _) {
        final settings = settingsProvider.settings;
        final remoteDeviceKind = settings.remoteDeviceKind;
        final showRoiAlertOff =
            remoteDeviceKind == RemoteDeviceKind.hss &&
            receiver.connected &&
            settings.personRoiAlertDisabled;
        return Column(
          children: [
            // Toolbar
            _buildToolbar(
              context,
              receiver,
              settings.streamUri.toString(),
              settings.detectorBaseUrl,
              remoteDeviceKind,
              settings,
              isPhone: widget.isPhone,
            ),
            const Divider(height: 1),

            if (_isInspectionStation) ...[
              _buildStationPanel(settings, receiver),
              const Divider(height: 1),
            ],

            // Frame viewer
            Expanded(
              child: _buildViewerArea(
                receiver,
                remoteDeviceKind,
                showRoiAlertOff: showRoiAlertOff,
              ),
            ),

            // Status bar
            _buildStatusBar(context, receiver, settings.streamUri.toString()),
          ],
        );
      },
    );
  }

  Widget _buildViewerArea(
    FrameReceiverService receiver,
    RemoteDeviceKind? remoteDeviceKind, {
    required bool showRoiAlertOff,
  }) {
    if (_isInspectionStation) {
      return _buildStationViewerGrid(receiver);
    }
    final selectedFrame = receiver.selectedFrame;
    final splitViewEnabled =
        remoteDeviceKind == RemoteDeviceKind.pick && !widget.isPhone;
    if (splitViewEnabled && _splitView && receiver.connected) {
      _ensureSplitStreams(receiver);
    }
    var viewer =
        splitViewEnabled &&
            _splitView &&
            receiver.connected &&
            receiver.isWebSocket
        ? _buildSplitViewer(receiver)
        : _buildMainViewer(receiver, selectedFrame);
    final selectorPanelEnabled = remoteDeviceKind == RemoteDeviceKind.pick;
    final sidePanelVisible =
        selectorPanelEnabled && !widget.isPhone && !receiver.isRtsp;

    if (!receiver.connected || !sidePanelVisible) {
      return _buildViewerWithRoiAlertOverlay(
        viewer,
        showRoiAlertOff: showRoiAlertOff,
      );
    }

    return Row(
      children: [
        Expanded(
          child: _buildViewerWithRoiAlertOverlay(
            viewer,
            showRoiAlertOff: showRoiAlertOff,
          ),
        ),
        Container(
          width: _streamSelectorPanelWidth,
          decoration: const BoxDecoration(
            color: Color(0xFF1F1F1F),
            border: Border(left: BorderSide(color: Color(0xFF4A4A4A))),
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
            remoteDeviceKind: remoteDeviceKind,
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

  Widget _buildViewerWithRoiAlertOverlay(
    Widget viewer, {
    required bool showRoiAlertOff,
  }) {
    if (!showRoiAlertOff) {
      return viewer;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        viewer,
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _roiAlertOpacity,
            builder: (context, _) {
              return Opacity(
                opacity: _roiAlertOpacity.value,
                child: const _RoiAlertOffOverlay(),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showPhoneStreamSheet(FrameReceiverService receiver) {
    if (!receiver.connected || receiver.isRtsp) {
      return;
    }
    final streams = receiver.streams.values.toList()
      ..sort((a, b) => a.payloadIndex.compareTo(b.payloadIndex));

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Stream',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                for (final stream in streams)
                  ListTile(
                    dense: true,
                    title: Text(
                      stream.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      stream.isPointCloud
                          ? '${stream.pointCount} pts'
                          : stream.size == null
                          ? 'unknown size'
                          : '${stream.size!.width.toInt()} x ${stream.size!.height.toInt()}',
                    ),
                    selected: stream.key == receiver.selectedStreamKey,
                    onTap: () {
                      receiver.selectStream(stream.key);
                      Navigator.pop(sheetContext);
                    },
                  ),
                const Divider(height: 16),
                FilledButton.tonal(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _showPhoneAdvancedSheet(receiver);
                  },
                  child: const Text('Advanced controls'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPhoneAdvancedSheet(FrameReceiverService receiver) {
    final settings = context.read<SettingsProvider>().settings;
    final selectedFrame = receiver.selectedFrame;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.75,
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
              remoteDeviceKind: settings.remoteDeviceKind,
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
                if (sheetContext.mounted) {
                  Navigator.pop(sheetContext);
                }
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
        );
      },
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
    _splitLeftStreamKey = null;
    _splitRightStreamKey = null;
    _ensureSplitStreams(receiver);
  }

  void _ensureSplitStreams(FrameReceiverService receiver) {
    final streams = receiver.streams.values.toList()
      ..sort((a, b) => a.payloadIndex.compareTo(b.payloadIndex));
    if (streams.isEmpty) return;

    final leftIsValid = _streamByKey(streams, _splitLeftStreamKey) != null;
    if (!leftIsValid) {
      _splitLeftStreamKey =
          _firstStreamKeyWhere(streams, _isColorImageStream) ??
          receiver.selectedStreamKey ??
          streams.first.key;
    }

    final rightIsValid = _streamByKey(streams, _splitRightStreamKey) != null;
    if (!rightIsValid || _splitRightStreamKey == _splitLeftStreamKey) {
      _splitRightStreamKey = _firstStreamKeyWhere(
        streams,
        (stream) =>
            stream.key != _splitLeftStreamKey && _isDepthImageStream(stream),
      );
    }
  }

  String? _firstStreamKeyWhere(
    List<ViewerStreamFrame> streams,
    bool Function(ViewerStreamFrame stream) test,
  ) {
    for (final stream in streams) {
      if (test(stream)) return stream.key;
    }
    return null;
  }

  bool _isColorImageStream(ViewerStreamFrame stream) {
    if (!stream.isJpeg) return false;
    final values = _streamIdentityValues(stream);
    return values.any(
      (value) =>
          value == 'camera' ||
          value == 'color' ||
          value == 'rgb' ||
          value == 'rgb_camera' ||
          value.contains('color') ||
          value.contains('rgb'),
    );
  }

  bool _isDepthImageStream(ViewerStreamFrame stream) {
    if (!stream.isJpeg) return false;
    final values = _streamIdentityValues(stream);
    return values.any((value) => value == 'depth' || value.contains('depth'));
  }

  List<String> _streamIdentityValues(ViewerStreamFrame stream) {
    return [
      stream.key.toLowerCase(),
      stream.name.toLowerCase(),
      stream.kind.toLowerCase(),
      stream.label.toLowerCase(),
    ];
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
        selectedFrame.isProjectedDepth) {
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
      final isDepthStream = stream.kind == 'depth';
      final settings = context.read<SettingsProvider>().settings;
      final image = Image.memory(
        stream.jpegBytes,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
      );
      final imageStack = Stack(
        fit: StackFit.expand,
        children: [
          image,
          if (isDepthStream)
            CustomPaint(
              painter: _DepthLegendPainter(
                imageSize: stream.size,
                minDepth: settings.cubeEyeDepthRangeMin.toDouble(),
                maxDepth: settings.cubeEyeDepthRangeMax.toDouble(),
                showColorbar: true,
                showAxis: false,
                axisScale: _axisScale,
                yaw: _viewYaw,
                pitch: _viewPitch,
              ),
            ),
          if (!_isInspectionStation &&
              stream.kind != 'camera' &&
              receiver.detectionPositions.isNotEmpty)
            CustomPaint(
              painter: _DepthDetectionPainter(
                imageSize: stream.size,
                detections: receiver.detectionPositions,
              ),
            ),
        ],
      );
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: imageStack,
      );
    }
    if (stream.isProjectedDepth && stream.projectedDepth != null) {
      final camera = receiver.streams['camera'];
      if (camera == null || !camera.isJpeg) {
        return Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: const Text(
            'Waiting for camera stream',
            style: TextStyle(color: Colors.grey),
          ),
        );
      }
      final imageSize = camera.size ?? stream.size;
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              camera.jpegBytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
            ),
            ColoredBox(color: Colors.black.withValues(alpha: 0.22)),
            CustomPaint(
              painter: _ProjectedDepthPainter(
                data: stream.projectedDepth!,
                imageSize: imageSize,
                pointSize: _pointSize,
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
    RemoteDeviceKind? remoteDeviceKind,
    AppSettings settings, {
    bool isPhone = false,
  }) {
    if (isPhone) {
      return _buildPhoneToolbar(
        context,
        receiver,
        defaultStreamUrl,
        defaultApiBaseUrl,
        remoteDeviceKind,
        settings,
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final splitViewEnabled = remoteDeviceKind == RemoteDeviceKind.pick;
    final captureControlsEnabled =
        remoteDeviceKind == RemoteDeviceKind.capture ||
        remoteDeviceKind == RemoteDeviceKind.inspection;
    final recordingControlsEnabled =
        remoteDeviceKind == RemoteDeviceKind.hss ||
        remoteDeviceKind == RemoteDeviceKind.capture;
    final showRoiAlertOff =
        remoteDeviceKind == RemoteDeviceKind.hss &&
        receiver.connected &&
        settings.personRoiAlertDisabled;

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
              onPressed: () => _connect(
                context: context,
                receiver: receiver,
                streamPath: defaultStreamUrl,
                apiBaseUrl: defaultApiBaseUrl,
              ),
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
              onPressed: () => _disconnect(receiver),
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
          if (showRoiAlertOff) ...[
            _buildRoiAlertOffBadge(),
            const SizedBox(width: 8),
          ],
          if (captureControlsEnabled && receiver.connected) ...[
            FilledButton.icon(
              icon: const Icon(Icons.camera_alt_outlined, size: 16),
              label: const Text('Capture'),
              onPressed: _captureActionInFlight
                  ? null
                  : () => _requestCapture(settings),
            ),
            const SizedBox(width: 8),
          ],
          if (splitViewEnabled &&
              !isPhone &&
              receiver.connected &&
              receiver.isWebSocket) ...[
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
          if (splitViewEnabled && isPhone && receiver.connected) ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.layers_outlined, size: 16),
              label: const Text('Streams'),
              onPressed: () => _showPhoneStreamSheet(receiver),
            ),
            const SizedBox(width: 8),
            if (receiver.streams.length > 1)
              OutlinedButton.icon(
                icon: const Icon(Icons.tune_outlined, size: 16),
                label: const Text('Advanced'),
                onPressed: () => _showPhoneAdvancedSheet(receiver),
              ),
            const SizedBox(width: 8),
          ],
          if (recordingControlsEnabled && receiver.connected) ...[
            _buildRecordingControls(settings),
            const SizedBox(width: 8),
          ],
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildPhoneToolbar(
    BuildContext context,
    FrameReceiverService receiver,
    String defaultStreamUrl,
    String defaultApiBaseUrl,
    RemoteDeviceKind? remoteDeviceKind,
    AppSettings settings,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final splitViewEnabled = remoteDeviceKind == RemoteDeviceKind.pick;
    final captureControlsEnabled =
        remoteDeviceKind == RemoteDeviceKind.capture ||
        remoteDeviceKind == RemoteDeviceKind.inspection;
    final recordingControlsEnabled =
        remoteDeviceKind == RemoteDeviceKind.hss ||
        remoteDeviceKind == RemoteDeviceKind.capture;
    final showRoiAlertOff =
        remoteDeviceKind == RemoteDeviceKind.hss &&
        receiver.connected &&
        settings.personRoiAlertDisabled;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: colorScheme.surface,
      child: Row(
        children: [
          Icon(Icons.live_tv, size: 22, color: colorScheme.secondary),
          const SizedBox(width: 8),
          const Flexible(
            child: Text(
              'Viewer',
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
                  if (!receiver.connected && !receiver.connecting) ...[
                    Tooltip(
                      message: 'Connect',
                      child: IconButton.filled(
                        icon: const Icon(Icons.power, size: 20),
                        onPressed: () => _connect(
                          context: context,
                          receiver: receiver,
                          streamPath: defaultStreamUrl,
                          apiBaseUrl: defaultApiBaseUrl,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Change URL',
                      child: IconButton.outlined(
                        icon: const Icon(Icons.link, size: 20),
                        onPressed: () => _showConnectDialog(
                          context,
                          receiver,
                          defaultStreamUrl,
                          defaultApiBaseUrl,
                        ),
                      ),
                    ),
                  ] else if (receiver.connecting) ...[
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    const Text('Connecting...', style: TextStyle(fontSize: 13)),
                  ] else ...[
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Disconnect',
                      child: IconButton.outlined(
                        icon: const Icon(Icons.power_off, size: 20),
                        onPressed: () => _disconnect(receiver),
                      ),
                    ),
                  ],
                  if (splitViewEnabled && receiver.connected) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Streams',
                      child: IconButton.outlined(
                        icon: const Icon(Icons.layers_outlined, size: 20),
                        onPressed: () => _showPhoneStreamSheet(receiver),
                      ),
                    ),
                    if (receiver.streams.length > 1) ...[
                      const SizedBox(width: 4),
                      Tooltip(
                        message: 'Advanced controls',
                        child: IconButton.outlined(
                          icon: const Icon(Icons.tune_outlined, size: 20),
                          onPressed: () => _showPhoneAdvancedSheet(receiver),
                        ),
                      ),
                    ],
                  ],
                  if (captureControlsEnabled && receiver.connected) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Capture',
                      child: IconButton.outlined(
                        icon: const Icon(Icons.camera_alt_outlined, size: 20),
                        onPressed: _captureActionInFlight
                            ? null
                            : () => _requestCapture(settings),
                      ),
                    ),
                  ],
                  if (recordingControlsEnabled && receiver.connected) ...[
                    const SizedBox(width: 4),
                    _buildPhoneRecordingControls(settings),
                  ],
                  if (showRoiAlertOff) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'ROI Alert Off',
                      child: IconButton.outlined(
                        icon: const Icon(
                          Icons.warning_amber_outlined,
                          size: 20,
                        ),
                        color: Colors.amberAccent,
                        onPressed: null,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (receiver.errorMessage != null) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: receiver.errorMessage!,
              child: const Icon(
                Icons.error_outline,
                size: 18,
                color: Colors.red,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRoiAlertOffBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.amberAccent),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.warning_amber_outlined,
            size: 16,
            color: Colors.amberAccent,
          ),
          SizedBox(width: 6),
          Text(
            'ROI Alert Off',
            style: TextStyle(fontSize: 12, color: Colors.amberAccent),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneRecordingControls(AppSettings settings) {
    final status = _recordingStatus;
    final state = status?.state ?? RemoteRecordingState.idle;
    final busy = _recordingActionInFlight;

    if (state == RemoteRecordingState.idle) {
      return Tooltip(
        message: 'Record',
        child: IconButton.outlined(
          icon: const Icon(Icons.fiber_manual_record, size: 20),
          color: Colors.redAccent,
          onPressed: busy
              ? null
              : () => _runRecordingAction((api) => api.start(settings)),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Save',
          child: IconButton.outlined(
            icon: const Icon(Icons.save, size: 20),
            onPressed: busy
                ? null
                : () => _runRecordingAction(
                    (api) => api.save(settings),
                    successMessage: (next) => next.savedPath.isEmpty
                        ? 'Recording saved'
                        : 'Recording saved: ${next.savedPath}',
                  ),
          ),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: state == RemoteRecordingState.paused ? 'Resume' : 'Pause',
          child: IconButton.outlined(
            icon: Icon(
              state == RemoteRecordingState.paused
                  ? Icons.play_arrow
                  : Icons.pause,
              size: 20,
            ),
            onPressed: busy
                ? null
                : () => _runRecordingAction(
                    (api) => state == RemoteRecordingState.paused
                        ? api.resume(settings)
                        : api.pause(settings),
                  ),
          ),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: 'Cancel',
          child: IconButton.outlined(
            icon: const Icon(Icons.close, size: 20),
            onPressed: busy
                ? null
                : () => _runRecordingAction((api) => api.cancel(settings)),
          ),
        ),
      ],
    );
  }

  Widget _buildRecordingControls(AppSettings settings) {
    final status = _recordingStatus;
    final state = status?.state ?? RemoteRecordingState.idle;
    final busy = _recordingActionInFlight;

    if (state == RemoteRecordingState.idle) {
      return FilledButton.icon(
        icon: const Icon(Icons.fiber_manual_record, size: 16),
        label: const Text('Record'),
        onPressed: busy
            ? null
            : () => _runRecordingAction((api) => api.start(settings)),
      );
    }

    final isPaused = state == RemoteRecordingState.paused;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.save, size: 16),
          label: const Text('Save'),
          onPressed: busy
              ? null
              : () => _runRecordingAction(
                  (api) => api.save(settings),
                  successMessage: (next) => next.savedPath.isEmpty
                      ? 'Recording saved'
                      : 'Recording saved: ${next.savedPath}',
                ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          icon: Icon(isPaused ? Icons.play_arrow : Icons.pause, size: 16),
          label: Text(isPaused ? 'Resume' : 'Pause'),
          onPressed: busy
              ? null
              : () => _runRecordingAction(
                  (api) =>
                      isPaused ? api.resume(settings) : api.pause(settings),
                ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.close, size: 16),
          label: const Text('Cancel'),
          onPressed: busy
              ? null
              : () => _runRecordingAction((api) => api.cancel(settings)),
        ),
      ],
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
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
            const SizedBox(width: 14),
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
            const SizedBox(width: 14),
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
            const SizedBox(width: 14),
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
            const SizedBox(width: 14),
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
            const SizedBox(width: 14),
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
            const SizedBox(width: 14),
            _StatusChip(
              label: 'Stream',
              value: !connected ? '-' : selectedFrame?.label ?? 'N/A',
              valueWidth: 74,
              color: connected && selectedFrame != null
                  ? Colors.lightBlueAccent
                  : Colors.grey,
            ),
            const SizedBox(width: 14),
            _StatusChip(
              label: 'Resolution',
              value: !connected ? '-' : resolutionText,
              valueWidth: 82,
              color: connected && selectedSize != null
                  ? Colors.cyan
                  : Colors.grey,
            ),
            const SizedBox(width: 18),
            SizedBox(
              width: 180,
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
      ),
    );
  }

  Widget _buildStationViewerGrid(FrameReceiverService receiver) {
    final slots = List<String>.generate(
      _stationViewerLayout.slotCount,
      (index) =>
          index < _stationCameraSlots.length ? _stationCameraSlots[index] : '',
    );
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          for (var row = 0; row < _stationViewerLayout.rows; row++) ...[
            if (row > 0) const SizedBox(height: 8),
            Expanded(
              child: Row(
                children: [
                  for (
                    var column = 0;
                    column < _stationViewerLayout.columns;
                    column++
                  ) ...[
                    if (column > 0) const SizedBox(width: 8),
                    Expanded(
                      child: _buildStationCameraTile(
                        receiver,
                        slots[row * _stationViewerLayout.columns + column],
                        row * _stationViewerLayout.columns + column,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStationCameraTile(
    FrameReceiverService receiver,
    String cameraId,
    int slotIndex,
  ) {
    final frame = cameraId.isEmpty ? null : receiver.streams[cameraId];
    final cameraStatus = _stationStatus?.cameras[cameraId];
    final isFresh =
        frame != null &&
        DateTime.now().difference(frame.receivedAt) <=
            const Duration(seconds: 3);
    String? waitingMessage;
    if (cameraId.isEmpty) {
      waitingMessage = 'Select a camera for slot ${slotIndex + 1}';
    } else if (!receiver.connected) {
      waitingMessage = 'Disconnected';
    } else if (_stationSourceActionInFlight) {
      waitingMessage = 'Updating multi-stream selection...';
    } else if (frame == null || !isFresh) {
      waitingMessage = cameraStatus?.lastError.isNotEmpty == true
          ? cameraStatus!.lastError
          : 'Waiting for a fresh preview: $cameraId';
    }

    final selected = frame != null && frame.key == receiver.selectedStreamKey;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: frame == null ? null : () => receiver.selectStream(frame.key),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.secondary
                : const Color(0xFF4A4A4A),
            width: selected ? 2 : 1,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (frame != null && frame.isJpeg)
              _buildStreamContent(receiver, frame),
            if (waitingMessage != null) ...[
              ColoredBox(color: Colors.black.withValues(alpha: 0.52)),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    waitingMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ],
            Align(
              alignment: Alignment.topLeft,
              child: Container(
                margin: const EdgeInsets.all(8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xCC202020),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  cameraId.isEmpty ? 'Slot ${slotIndex + 1}' : cameraId,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStationPanel(
    AppSettings settings,
    FrameReceiverService receiver,
  ) {
    final status = _stationStatus;
    final source = _stationViewerSource;
    final cameraIds = <String>{
      ...?source?.cameras,
      ...?status?.cameras.keys,
      ...?source?.cameraIds,
    }.where((cameraId) => cameraId.isNotEmpty).toList(growable: false)..sort();
    final targetItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'all', child: Text('All inspections')),
      for (final group in status?.groups.keys ?? const <String>[])
        DropdownMenuItem(value: 'group:$group', child: Text('Group: $group')),
      for (final inspectionId in _stationInspectionIds(status))
        DropdownMenuItem(
          value: 'inspection:$inspectionId',
          child: Text('Inspection: $inspectionId'),
        ),
    ];
    final targetValues = targetItems.map((item) => item.value).toSet();
    final selectedTarget = targetValues.contains(_stationCaptureTarget)
        ? _stationCaptureTarget
        : 'all';
    final selectedCycleId = _stationCycles.containsKey(_selectedStationCycleId)
        ? _selectedStationCycleId
        : _stationCycles.isEmpty
        ? null
        : _stationCycles.keys.last;
    final selectedResult = selectedCycleId == null
        ? null
        : _stationCycles[selectedCycleId];
    final queueText = status == null
        ? 'Queue: loading'
        : 'Queue: ${status.pendingCount}/${status.maxPendingCaptures}'
              '${status.busy ? ' + active' : ''}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFF202020),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Wrap(
              spacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Inspection Station',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SegmentedButton<StationViewerLayout>(
                  segments: [
                    for (final layout in StationViewerLayout.values)
                      ButtonSegment(value: layout, label: Text(layout.label)),
                  ],
                  selected: {_stationViewerLayout},
                  showSelectedIcon: false,
                  onSelectionChanged:
                      _stationSourceActionInFlight || source == null
                      ? null
                      : (selection) => unawaited(
                          _changeStationViewerLayout(
                            settings,
                            receiver,
                            selection.first,
                            cameraIds,
                          ),
                        ),
                ),
                for (
                  var slot = 0;
                  slot < _stationViewerLayout.slotCount;
                  slot++
                )
                  SizedBox(
                    width: 190,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(
                        'station-camera-${_stationViewerLayout.name}-$slot-${_stationCameraForSlot(slot)}',
                      ),
                      initialValue: _stationCameraForSlot(slot),
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Camera ${slot + 1}',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('Empty')),
                        for (final cameraId in cameraIds)
                          DropdownMenuItem(
                            value: cameraId,
                            child: Text(
                              cameraId,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _stationSourceActionInFlight || source == null
                          ? null
                          : (cameraId) {
                              if (cameraId != null) {
                                unawaited(
                                  _changeStationCameraSlot(
                                    settings,
                                    receiver,
                                    slot,
                                    cameraId,
                                  ),
                                );
                              }
                            },
                    ),
                  ),
                SizedBox(
                  width: 230,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('station-target-$selectedTarget'),
                    initialValue: selectedTarget,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Capture target',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: targetItems,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _stationCaptureTarget = value);
                      }
                    },
                  ),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.camera_alt_outlined, size: 16),
                  label: const Text('Capture'),
                  onPressed:
                      !receiver.connected ||
                          _captureActionInFlight ||
                          status?.ready == false
                      ? null
                      : () => _requestCapture(settings),
                ),
                Text(queueText, style: const TextStyle(fontSize: 12)),
                if (status != null)
                  Text(
                    'Captured: ${status.captureCount}',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                if (status?.activeCycleId.isNotEmpty == true)
                  Text(
                    'Active: ${_shortCycleId(status!.activeCycleId)}',
                    style: const TextStyle(
                      color: Colors.lightBlueAccent,
                      fontSize: 12,
                    ),
                  ),
                if (status?.ready == false)
                  const Text(
                    'Station not ready',
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                  ),
                if (status != null)
                  Text(
                    'Cameras: ${status.cameras.values.where((camera) => camera.open).length}/${status.cameras.length} open',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (_stationCycles.isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  SizedBox(
                    width: 210,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('station-cycle-$selectedCycleId'),
                      initialValue: selectedCycleId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Correlated cycle result',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final cycleId
                            in _stationCycles.keys.toList().reversed)
                          DropdownMenuItem(
                            value: cycleId,
                            child: Text(
                              _shortCycleId(cycleId),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _selectedStationCycleId = value),
                    ),
                  ),
                  if (selectedResult != null) ...[
                    const SizedBox(width: 10),
                    _stationResultChip(
                      selectedResult.presentationStatus,
                      _stationStatusColor(selectedResult.presentationStatus),
                    ),
                    if (selectedResult.group.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text('Group ${selectedResult.group}'),
                    ],
                    for (final inspection
                        in selectedResult.inspections.values) ...[
                      const SizedBox(width: 8),
                      _stationResultChip(
                        '${inspection.inspectionId}: ${inspection.status}'
                        '${inspection.reason.isEmpty ? '' : ' (${inspection.reason})'}',
                        _stationStatusColor(inspection.status),
                      ),
                    ],
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.data_object, size: 16),
                      label: const Text('Details'),
                      onPressed: () =>
                          _showStationResultDetails(selectedResult),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (_stationError != null ||
              status?.lastError.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(
              _stationError ?? status!.lastError,
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  List<String> _stationInspectionIds(StationCaptureStatus? status) {
    final ids = <String>{};
    for (final group in status?.groups.values ?? const <List<String>>[]) {
      ids.addAll(group);
    }
    final result = ids.toList(growable: false)..sort();
    return result;
  }

  Widget _stationResultChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 12)),
    );
  }

  Color _stationStatusColor(String status) {
    return switch (status) {
      'OK' || 'PRESENT' || 'COMPLETED' => Colors.greenAccent,
      'NG' || 'ABSENT' => Colors.redAccent,
      'RECHECK' => Colors.orangeAccent,
      'EQUIPMENT_ERROR' => Colors.deepOrangeAccent,
      'CANCELLED' || 'EXPIRED' => Colors.grey,
      _ => Colors.lightBlueAccent,
    };
  }

  String _shortCycleId(String cycleId) =>
      cycleId.length <= 18 ? cycleId : '${cycleId.substring(0, 18)}…';

  void _showStationResultDetails(StationCaptureResult result) {
    final details = result.rawJson.isEmpty
        ? {
            'cycle_id': result.cycleId,
            'state': result.state.name.toUpperCase(),
            'error': result.error,
          }
        : result.rawJson;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Cycle ${_shortCycleId(result.cycleId)}'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(details),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
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
              final streamUrl = streamController.text.trim();
              await _connect(
                context: context,
                receiver: receiver,
                streamPath: streamUrl,
                apiBaseUrl: apiController.text.trim(),
              );
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  Future<void> _initializeStation(
    AppSettings settings,
    FrameReceiverService receiver,
  ) async {
    final session = ++_stationSession;
    _stationPollTimer?.cancel();
    final sameDevice = _stationApiBaseUrl == settings.detectorBaseUrl;
    if (!sameDevice) {
      _stationCycles.clear();
      _selectedStationCycleId = null;
      _stationCaptureTarget = 'all';
    }
    _stationApiBaseUrl = settings.detectorBaseUrl;
    _isInspectionStation = true;
    _stationError = null;

    StationCaptureStatus? nextStatus;
    StationViewerSource? nextSource;
    final errors = <String>[];
    await Future.wait<void>([
      () async {
        try {
          nextStatus = await _captureApi.fetchStationStatus(settings);
        } catch (error) {
          errors.add('Status: $error');
        }
      }(),
      () async {
        try {
          nextSource = await _captureApi.fetchViewerSource(settings);
        } catch (error) {
          errors.add('Preview source: $error');
        }
      }(),
    ]);
    if (!mounted || session != _stationSession) return;
    nextStatus ??= sameDevice ? _stationStatus : null;
    nextSource ??= sameDevice ? _stationViewerSource : null;
    final sourceCameraIds = nextSource?.cameraIds ?? const <String>[];
    final nextLayout = _stationViewerLayout.accommodate(sourceCameraIds.length);
    final nextSlots = reconcileStationCameraSlots(
      layout: nextLayout,
      preferredSlots: _stationCameraSlots,
      activeCameraIds: sourceCameraIds,
    );
    receiver.setExpectedCameraIds(nextSource?.cameraIds ?? const []);
    setState(() {
      _stationStatus = nextStatus;
      _stationViewerSource = nextSource;
      _stationViewerLayout = nextLayout;
      _stationCameraSlots = nextSlots;
      _stationError = errors.isEmpty ? null : errors.join(' · ');
    });
    _persistStationViewerLayout(nextLayout, nextSlots);
    _startStationPolling(settings, session);
  }

  void _leaveStationMode(FrameReceiverService receiver) {
    _stationSession++;
    _stationPollTimer?.cancel();
    receiver.setExpectedCameraIds(null);
    if (!mounted) return;
    setState(() {
      _isInspectionStation = false;
      _stationStatus = null;
      _stationViewerSource = null;
      _stationCycles.clear();
      _selectedStationCycleId = null;
      _stationError = null;
      _stationApiBaseUrl = null;
    });
  }

  void _startStationPolling(AppSettings settings, int session) {
    _stationPollTimer?.cancel();
    unawaited(_pollStation(settings, session));
    _stationPollTimer = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => unawaited(_pollStation(settings, session)),
    );
  }

  Future<void> _pollStation(AppSettings settings, int session) async {
    if (_stationPollInFlight ||
        !mounted ||
        !_isInspectionStation ||
        session != _stationSession) {
      return;
    }
    _stationPollInFlight = true;
    StationCaptureStatus? nextStatus;
    String? nextError;
    final nextResults = <String, StationCaptureResult>{};
    try {
      try {
        nextStatus = await _captureApi.fetchStationStatus(settings);
      } catch (error) {
        nextError = 'Station status failed: $error';
      }

      final pendingCycles = _stationCycles.values
          .where((result) => !result.state.isFinal)
          .toList(growable: false);
      for (final pending in pendingCycles) {
        try {
          nextResults[pending.cycleId] = await _captureApi.fetchStationResult(
            settings,
            pending.cycleId,
          );
        } on RemoteCaptureApiException catch (error) {
          if (error.statusCode == 404) {
            nextResults[pending.cycleId] = StationCaptureResult.expired(
              pending.cycleId,
            );
          } else {
            nextError ??= 'Result polling failed: $error';
          }
        } catch (error) {
          nextError ??= 'Result polling failed: $error';
        }
      }
    } finally {
      _stationPollInFlight = false;
    }
    if (!mounted || session != _stationSession || !_isInspectionStation) {
      return;
    }
    setState(() {
      if (nextStatus != null) _stationStatus = nextStatus;
      _stationCycles.addAll(nextResults);
      _stationError = nextError;
      _trimStationHistory();
    });
  }

  void _trimStationHistory() {
    while (_stationCycles.length > 32) {
      String? removable;
      for (final entry in _stationCycles.entries) {
        if (entry.value.state.isFinal && entry.key != _selectedStationCycleId) {
          removable = entry.key;
          break;
        }
      }
      if (removable == null) return;
      _stationCycles.remove(removable);
    }
  }

  String _stationCameraForSlot(int slot) {
    return slot < _stationCameraSlots.length ? _stationCameraSlots[slot] : '';
  }

  List<String> _cameraSlotsFor(
    StationViewerLayout layout,
    Iterable<String> cameraIds,
  ) => resizeStationCameraSlots(layout, cameraIds);

  Future<void> _changeStationViewerLayout(
    AppSettings settings,
    FrameReceiverService receiver,
    StationViewerLayout layout,
    List<String> availableCameras,
  ) async {
    final slots = _cameraSlotsFor(layout, _stationCameraSlots);
    final selected = slots.where((cameraId) => cameraId.isNotEmpty).toSet();
    for (var index = 0; index < slots.length; index++) {
      if (slots[index].isNotEmpty) continue;
      for (final cameraId in availableCameras) {
        if (selected.add(cameraId)) {
          slots[index] = cameraId;
          break;
        }
      }
    }
    await _setStationViewerSources(settings, receiver, layout, slots);
  }

  Future<void> _changeStationCameraSlot(
    AppSettings settings,
    FrameReceiverService receiver,
    int slot,
    String cameraId,
  ) async {
    final slots = _cameraSlotsFor(_stationViewerLayout, _stationCameraSlots);
    final existingSlot = cameraId.isEmpty ? -1 : slots.indexOf(cameraId);
    if (existingSlot >= 0 && existingSlot != slot) {
      slots[existingSlot] = slots[slot];
    }
    slots[slot] = cameraId;
    await _setStationViewerSources(
      settings,
      receiver,
      _stationViewerLayout,
      slots,
    );
  }

  Future<void> _setStationViewerSources(
    AppSettings settings,
    FrameReceiverService receiver,
    StationViewerLayout layout,
    List<String> slots,
  ) async {
    if (_stationSourceActionInFlight) return;
    final previousSource = _stationViewerSource;
    final selectedCameraIds = slots
        .where((cameraId) => cameraId.isNotEmpty)
        .toList(growable: false);
    receiver.setExpectedCameraIds(selectedCameraIds);
    setState(() {
      _stationSourceActionInFlight = true;
      _selectedStationCycleId = null;
      _stationError = null;
      _stationViewerSource = StationViewerSource(
        cameraIds: selectedCameraIds,
        cameras: previousSource?.cameras ?? const [],
      );
      _stationViewerLayout = layout;
      _stationCameraSlots = List.unmodifiable(slots);
    });
    try {
      final source = await _captureApi.setViewerSources(
        settings,
        selectedCameraIds,
      );
      if (!mounted || !_isInspectionStation) return;
      final confirmedLayout = layout.accommodate(source.cameraIds.length);
      final confirmedSlots = reconcileStationCameraSlots(
        layout: confirmedLayout,
        preferredSlots: slots,
        activeCameraIds: source.cameraIds,
      );
      receiver.setExpectedCameraIds(source.cameraIds);
      setState(() {
        _stationViewerSource = source;
        _stationViewerLayout = confirmedLayout;
        _stationCameraSlots = confirmedSlots;
        _stationSourceActionInFlight = false;
      });
      _persistStationViewerLayout(confirmedLayout, confirmedSlots);
    } catch (error) {
      if (!mounted || !_isInspectionStation) return;
      StationViewerSource? actual;
      try {
        actual = await _captureApi.fetchViewerSource(settings);
      } catch (_) {
        actual = previousSource;
      }
      final actualCameraIds = actual?.cameraIds ?? const <String>[];
      final actualLayout = layout.accommodate(actualCameraIds.length);
      final actualSlots = actual == null
          ? List<String>.unmodifiable(slots)
          : reconcileStationCameraSlots(
              layout: actualLayout,
              preferredSlots: slots,
              activeCameraIds: actualCameraIds,
            );
      receiver.setExpectedCameraIds(actual?.cameraIds ?? const []);
      setState(() {
        _stationViewerSource = actual;
        _stationViewerLayout = actualLayout;
        _stationCameraSlots = actualSlots;
        _stationSourceActionInFlight = false;
        _stationError = 'Multi-stream selection failed: $error';
      });
      _persistStationViewerLayout(actualLayout, actualSlots);
    }
  }

  void _persistStationViewerLayout(
    StationViewerLayout layout,
    List<String> cameraSlots,
  ) {
    unawaited(
      context.read<SettingsProvider>().updateStationViewerLayout(
        layout: layout,
        cameraSlots: cameraSlots,
      ),
    );
  }

  Future<void> _requestStationCapture(AppSettings settings) async {
    StationCaptureSelector selector;
    if (_stationCaptureTarget.startsWith('group:')) {
      selector = StationCaptureSelector.group(
        _stationCaptureTarget.substring('group:'.length),
      );
    } else if (_stationCaptureTarget.startsWith('inspection:')) {
      selector = StationCaptureSelector.inspection(
        _stationCaptureTarget.substring('inspection:'.length),
      );
    } else {
      selector = const StationCaptureSelector.all();
    }

    final accepted = await _captureApi.requestStationCapture(
      settings,
      selector: selector,
    );
    if (!accepted.accepted || accepted.cycleId.isEmpty) {
      throw StateError(
        accepted.error.isEmpty ? 'Station rejected capture' : accepted.error,
      );
    }
    if (!mounted) return;
    setState(() {
      _stationCycles[accepted.cycleId] = StationCaptureResult.pending(
        accepted.cycleId,
      );
      _selectedStationCycleId = accepted.cycleId;
      _stationError = accepted.error.isEmpty ? null : accepted.error;
      _trimStationHistory();
    });
    unawaited(_pollStation(settings, _stationSession));
  }

  Future<void> _disconnect(FrameReceiverService receiver) async {
    _stationSession++;
    _stationPollTimer?.cancel();
    await receiver.disconnect();
    if (mounted) setState(() {});
  }

  Future<void> _connect({
    required BuildContext context,
    required FrameReceiverService receiver,
    required String streamPath,
    required String? apiBaseUrl,
  }) async {
    final settingsProvider = context.read<SettingsProvider>();
    try {
      final targetApiBaseUrl =
          apiBaseUrl ??
          settingsProvider.settings.apiBaseUrlForStream(streamPath);
      final connectionSettings = AppSettings(
        detectorBaseUrl: targetApiBaseUrl,
        streamPath: streamPath,
        apiBasePath: settingsProvider.settings.apiBasePath,
      );
      final deviceInfoService = RemoteDeviceInfoService();
      late final RemoteDeviceInfo deviceInfo;
      try {
        deviceInfo = await deviceInfoService.fetchInfo(connectionSettings);
      } finally {
        deviceInfoService.close();
      }
      await settingsProvider.updateConnectionUrls(
        streamPath: streamPath,
        detectorBaseUrl: targetApiBaseUrl,
        remoteDeviceKind: deviceInfo.kind,
        personRoiAlertDisabled: deviceInfo.personRoiAlertDisabled,
      );
      if (deviceInfo.isInspectionStation) {
        await _initializeStation(settingsProvider.settings, receiver);
      } else {
        _leaveStationMode(receiver);
      }
      if (deviceInfo.kind == RemoteDeviceKind.hss ||
          deviceInfo.kind == RemoteDeviceKind.capture) {
        final recordingStatus = await RemoteRecordingApiService().fetchStatus(
          settingsProvider.settings,
        );
        if (context.mounted) {
          setState(() => _recordingStatus = recordingStatus);
        }
      } else if (context.mounted) {
        setState(() => _recordingStatus = null);
      }
      if (context.mounted) {
        unawaited(receiver.connect(streamPath));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Device info load failed: $e')));
      }
    }
  }

  Future<void> _runRecordingAction(
    Future<RemoteRecordingStatus> Function(RemoteRecordingApiService api)
    action, {
    String Function(RemoteRecordingStatus status)? successMessage,
  }) async {
    setState(() => _recordingActionInFlight = true);
    try {
      final next = await action(RemoteRecordingApiService());
      if (!mounted) return;
      setState(() {
        _recordingStatus = next;
        _recordingActionInFlight = false;
      });
      if (next.error.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error)));
      } else if (successMessage != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage(next))));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _recordingActionInFlight = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Recording API failed: $e')));
    }
  }

  Future<void> _requestCapture(AppSettings settings) async {
    setState(() => _captureActionInFlight = true);
    try {
      if (_isInspectionStation) {
        await _requestStationCapture(settings);
      } else {
        await _captureApi.requestCapture(settings);
      }
      if (!mounted) return;
      setState(() => _captureActionInFlight = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isInspectionStation
                ? 'Station capture accepted'
                : 'Capture requested',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _captureActionInFlight = false);
      final message = e is RemoteCaptureApiException && e.statusCode == 409
          ? 'Capture queue is full (409)'
          : e is RemoteCaptureApiException && e.statusCode == 503
          ? 'Station is not ready (503)'
          : 'Capture API failed: $e';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class _RoiAlertOffOverlay extends StatelessWidget {
  const _RoiAlertOffOverlay();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.08),
            border: Border.all(color: Colors.amberAccent, width: 3),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.only(top: 28),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.amberAccent, width: 2),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_outlined,
                  size: 28,
                  color: Colors.amberAccent,
                ),
                SizedBox(width: 10),
                Text(
                  'ROI Alert Off',
                  style: TextStyle(
                    color: Colors.amberAccent,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProjectedDepthPainter extends CustomPainter {
  final ProjectedDepthData data;
  final Size? imageSize;
  final double pointSize;

  const _ProjectedDepthPainter({
    required this.data,
    required this.imageSize,
    required this.pointSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sourceSize = imageSize;
    if (sourceSize == null ||
        sourceSize.width <= 0 ||
        sourceSize.height <= 0 ||
        data.pointCount <= 0) {
      return;
    }

    final scale = math.min(
      size.width / sourceSize.width,
      size.height / sourceSize.height,
    );
    final drawSize = Size(sourceSize.width * scale, sourceSize.height * scale);
    final offset = Offset(
      (size.width - drawSize.width) / 2,
      (size.height - drawSize.height) / 2,
    );
    final radius = math.max(1.4, pointSize * 0.9);
    final haloPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.black.withValues(alpha: 0.88);
    final paint = Paint()..style = PaintingStyle.fill;
    final range = math.max(0.001, data.maxDepth - data.minDepth);

    for (var i = 0; i < data.pointCount; i++) {
      final x = data.xAt(i);
      final y = data.yAt(i);
      final depth = data.depthAt(i);
      final normalized = ((depth - data.minDepth) / range).clamp(0.0, 1.0);
      final hue = 300.0 - (250.0 * normalized);
      paint.color = HSLColor.fromAHSL(1.0, hue, 1.0, 0.55).toColor();
      final point = Offset(offset.dx + (x * scale), offset.dy + (y * scale));
      canvas.drawCircle(point, radius + 0.9, haloPaint);
      canvas.drawCircle(point, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ProjectedDepthPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.pointSize != pointSize;
  }
}

class _DepthLegendPainter extends CustomPainter {
  final Size? imageSize;
  final double minDepth;
  final double maxDepth;
  final bool showColorbar;
  final bool showAxis;
  final double axisScale;
  final double yaw;
  final double pitch;

  const _DepthLegendPainter({
    required this.imageSize,
    required this.minDepth,
    required this.maxDepth,
    required this.showColorbar,
    required this.showAxis,
    required this.axisScale,
    required this.yaw,
    required this.pitch,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final imageRect = _imageRect(size);
    if (showColorbar) {
      _drawColorbar(canvas, size, imageRect);
    }
    if (showAxis) {
      _drawAxis(canvas, size, imageRect);
    }
  }

  Rect? _imageRect(Size size) {
    final imageSize = this.imageSize;
    if (imageSize == null || imageSize.width <= 0 || imageSize.height <= 0) {
      return null;
    }
    final scale =
        (size.width / imageSize.width) < (size.height / imageSize.height)
        ? size.width / imageSize.width
        : size.height / imageSize.height;
    final drawnSize = Size(imageSize.width * scale, imageSize.height * scale);
    return Offset(
          (size.width - drawnSize.width) * 0.5,
          (size.height - drawnSize.height) * 0.5,
        ) &
        drawnSize;
  }

  void _drawColorbar(Canvas canvas, Size size, Rect? imageRect) {
    const barWidth = 14.0;
    const barHeight = 140.0;
    const padding = 16.0;
    final rightEdge = imageRect?.right ?? size.width;
    final topEdge = imageRect?.top ?? 0.0;
    final rect = Rect.fromLTWH(
      math.min(rightEdge - padding - barWidth, size.width - padding - barWidth),
      topEdge + padding,
      barWidth,
      math.min(barHeight, math.max(size.height - topEdge - padding * 2, 48.0)),
    );
    const gradient = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [Color(0xFF4FC3F7), Color(0xFF69F0AE), Color(0xFFFF7043)],
      stops: [0.0, 0.5, 1.0],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white54,
    );
    _drawColorbarText(canvas, Offset(rect.left - 58, rect.top - 2), maxDepth);
    _drawColorbarText(
      canvas,
      Offset(rect.left - 58, rect.bottom - 12),
      minDepth,
    );
  }

  void _drawColorbarText(Canvas canvas, Offset offset, double value) {
    final painter = TextPainter(
      text: TextSpan(
        text: value.toStringAsFixed(0),
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 10,
          fontFamily: 'monospace',
          shadows: [Shadow(color: Colors.black, blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 54);
    painter.paint(canvas, offset);
  }

  void _drawAxis(Canvas canvas, Size size, Rect? imageRect) {
    const boxSize = 76.0;
    const padding = 16.0;
    final rect = imageRect;
    final origin = rect == null
        ? Offset(padding + 18, size.height - padding - 18)
        : Offset(
            math.max(padding + 18, rect.left - boxSize + 30),
            math.min(size.height - padding - 18, rect.bottom - 18),
          );
    final length = math.min(
      (36.0 * axisScale.clamp(0.4, 2.0)).toDouble(),
      math.max(size.width - origin.dx - 6.0, 18.0),
    );

    Offset project(double x, double y, double z) {
      final cosYaw = math.cos(yaw);
      final sinYaw = math.sin(yaw);
      final cosPitch = math.cos(pitch);
      final sinPitch = math.sin(pitch);
      final yawX = x * cosYaw + z * sinYaw;
      final yawZ = -x * sinYaw + z * cosYaw;
      final pitchY = y * cosPitch - yawZ * sinPitch;
      return origin + Offset(yawX * length, -pitchY * length);
    }

    final paint = Paint()
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    _drawAxisLine(
      canvas,
      paint,
      origin,
      project(1, 0, 0),
      'X',
      const Color(0xFFFF5252),
    );
    _drawAxisLine(
      canvas,
      paint,
      origin,
      project(0, 1, 0),
      'Y',
      const Color(0xFF69F0AE),
    );
    _drawAxisLine(
      canvas,
      paint,
      origin,
      project(0, 0, 1),
      'Z',
      const Color(0xFF40C4FF),
    );
  }

  void _drawAxisLine(
    Canvas canvas,
    Paint paint,
    Offset origin,
    Offset end,
    String label,
    Color color,
  ) {
    paint.color = color;
    canvas.drawLine(origin, end, paint);
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, end + const Offset(4, -6));
  }

  @override
  bool shouldRepaint(covariant _DepthLegendPainter oldDelegate) {
    return oldDelegate.imageSize != imageSize ||
        oldDelegate.minDepth != minDepth ||
        oldDelegate.maxDepth != maxDepth ||
        oldDelegate.showColorbar != showColorbar ||
        oldDelegate.showAxis != showAxis ||
        oldDelegate.axisScale != axisScale ||
        oldDelegate.yaw != yaw ||
        oldDelegate.pitch != pitch;
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
