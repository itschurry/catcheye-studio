import '../controllers/station_controller.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../widgets/status_label.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../models/station_viewer_layout.dart';
import '../providers/settings_provider.dart';
import '../providers/reference_credential_provider.dart';
import '../services/frame_receiver_service.dart';
import '../services/remote_capture_api_service.dart';
import '../services/remote_device_info_service.dart';
import '../services/remote_recording_api_service.dart';
import '../services/reference_credential_store.dart';
import '../widgets/live_viewer.dart';
import '../widgets/zoomable_viewport.dart';
import '../widgets/point_cloud_viewer.dart';
import '../widgets/stream_selector.dart';
import '../widgets/station_capture_actions.dart';
import 'production_screen.dart';
import '../widgets/station_undistortion_control.dart';

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
  final _recordingApi = RemoteRecordingApiService();
  final RemoteCaptureApiService _captureApi = RemoteCaptureApiService();
  late final StationController _station;
  int _connectionGeneration = 0;
  int _handledReconnectToken = 0;
  late final AnimationController _roiAlertBlinkController;
  late final Animation<double> _roiAlertOpacity;

  @override
  void initState() {
    super.initState();
    _station = StationController(
      api: _captureApi,
      selectCameras: (ids) =>
          context.read<FrameReceiverService>().setExpectedCameraIds(ids),
      persistLayout: (layout, slots) => context
          .read<SettingsProvider>()
          .updateStationViewerLayout(layout: layout, cameraSlots: slots),
    )..addListener(_onStationChanged);
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

  void _onStationChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _station.dispose();
    _captureApi.close();
    _recordingApi.close();
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
    _station.restoreLayout(settings);
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

            if (_station.active) ...[
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
    if (_station.active) {
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
                const Text('영상', style: TextStyle(fontWeight: FontWeight.bold)),
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
                          ? '${stream.pointCount}개 점'
                          : stream.size == null
                          ? '크기 알 수 없음'
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
                  child: const Text('고급 설정'),
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
              missingLabel: '왼쪽',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildSplitPanel(
              receiver: receiver,
              stream: rightStream,
              missingLabel: '오른쪽',
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
            '지원하지 않는 영상 인코딩: ${selectedFrame.encoding.name}',
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
          if (!_station.active &&
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
        child: ZoomableViewport(key: ValueKey(stream.key), child: imageStack),
      );
    }
    if (stream.isProjectedDepth && stream.projectedDepth != null) {
      final camera = receiver.streams['camera'];
      if (camera == null || !camera.isJpeg) {
        return Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: const Text(
            '카메라 영상 대기 중',
            style: TextStyle(color: Colors.grey),
          ),
        );
      }
      final imageSize = camera.size ?? stream.size;
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: ZoomableViewport(
          key: ValueKey(stream.key),
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
        ),
      );
    }
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Text(
        '지원하지 않는 영상 인코딩: ${stream.encoding.name}',
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
    final captureControlsEnabled = remoteDeviceKind == RemoteDeviceKind.capture;
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
            '실시간 영상',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 24),

          // Connection controls
          if (!receiver.connected && !receiver.connecting) ...[
            FilledButton.icon(
              icon: const Icon(Icons.power, size: 16),
              label: const Text('연결'),
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
              label: const Text('연결 주소 변경'),
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
            const Text('연결 중...', style: TextStyle(fontSize: 13)),
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
                    '연결됨',
                    style: TextStyle(fontSize: 12, color: Colors.green),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.power_off, size: 16),
              label: const Text('연결 해제'),
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
          if (remoteDeviceKind == RemoteDeviceKind.inspection) ...[
            Tooltip(
              message: '관리 인증 설정',
              child: IconButton.outlined(
                icon: const Icon(Icons.admin_panel_settings_outlined, size: 20),
                onPressed: _showManagementCredentialsDialog,
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (showRoiAlertOff) ...[
            _buildRoiAlertOffBadge(),
            const SizedBox(width: 8),
          ],
          if (captureControlsEnabled && receiver.connected) ...[
            FilledButton.icon(
              icon: const Icon(Icons.camera_alt_outlined, size: 16),
              label: const Text('촬영'),
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
              message: _splitView ? '단일 화면' : '분할 화면',
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
              label: const Text('영상 목록'),
              onPressed: () => _showPhoneStreamSheet(receiver),
            ),
            const SizedBox(width: 8),
            if (receiver.streams.length > 1)
              OutlinedButton.icon(
                icon: const Icon(Icons.tune_outlined, size: 16),
                label: const Text('고급 설정'),
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
    final captureControlsEnabled = remoteDeviceKind == RemoteDeviceKind.capture;
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
              '뷰어',
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
                      message: '연결',
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
                      message: '연결 주소 변경',
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
                    const Text('연결 중...', style: TextStyle(fontSize: 13)),
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
                      message: '연결 해제',
                      child: IconButton.outlined(
                        icon: const Icon(Icons.power_off, size: 20),
                        onPressed: () => _disconnect(receiver),
                      ),
                    ),
                  ],
                  if (splitViewEnabled && receiver.connected) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: '영상 목록',
                      child: IconButton.outlined(
                        icon: const Icon(Icons.layers_outlined, size: 20),
                        onPressed: () => _showPhoneStreamSheet(receiver),
                      ),
                    ),
                    if (receiver.streams.length > 1) ...[
                      const SizedBox(width: 4),
                      Tooltip(
                        message: '고급 설정',
                        child: IconButton.outlined(
                          icon: const Icon(Icons.tune_outlined, size: 20),
                          onPressed: () => _showPhoneAdvancedSheet(receiver),
                        ),
                      ),
                    ],
                  ],
                  if (remoteDeviceKind == RemoteDeviceKind.inspection) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: '관리 인증 설정',
                      child: IconButton.outlined(
                        icon: const Icon(
                          Icons.admin_panel_settings_outlined,
                          size: 20,
                        ),
                        onPressed: _showManagementCredentialsDialog,
                      ),
                    ),
                  ],
                  if (captureControlsEnabled && receiver.connected) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: '촬영',
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
                      message: 'ROI 경고 꺼짐',
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
            'ROI 경고 꺼짐',
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
        message: '녹화',
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
          message: '저장',
          child: IconButton.outlined(
            icon: const Icon(Icons.save, size: 20),
            onPressed: busy
                ? null
                : () => _runRecordingAction(
                    (api) => api.save(settings),
                    successMessage: (next) => next.savedPath.isEmpty
                        ? '녹화 저장 완료'
                        : '녹화 저장 완료: ${next.savedPath}',
                  ),
          ),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: state == RemoteRecordingState.paused ? '재개' : '일시 중지',
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
          message: '취소',
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
        label: const Text('녹화'),
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
          label: const Text('저장'),
          onPressed: busy
              ? null
              : () => _runRecordingAction(
                  (api) => api.save(settings),
                  successMessage: (next) => next.savedPath.isEmpty
                      ? '녹화 저장 완료'
                      : '녹화 저장 완료: ${next.savedPath}',
                ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          icon: Icon(isPaused ? Icons.play_arrow : Icons.pause, size: 16),
          label: Text(isPaused ? '재개' : '일시 중지'),
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
          label: const Text('취소'),
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
        ? '정보 없음'
        : '${selectedSize.width.toInt()} x ${selectedSize.height.toInt()}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _StatusChip(
              label: '상태',
              value: receiver.connected
                  ? '연결됨'
                  : receiver.connecting
                  ? '연결 중'
                  : '연결 끊김',
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
                  : '정보 없음 (RTSP)',
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
              label: '프레임 수',
              value: !connected
                  ? '-'
                  : receiver.isWebSocket
                  ? '${receiver.frameCount}'
                  : '정보 없음 (RTSP)',
              valueWidth: 72,
              color: connected && receiver.isWebSocket
                  ? Colors.cyan
                  : Colors.grey,
            ),
            const SizedBox(width: 14),
            _StatusChip(
              label: '추론 시간',
              value: !connected
                  ? '-'
                  : receiver.isWebSocket
                  ? inferenceMs == null
                        ? '정보 없음'
                        : '${inferenceMs.toStringAsFixed(1)} ms'
                  : '정보 없음 (RTSP)',
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
              label: '전체 처리 시간',
              value: !connected
                  ? '-'
                  : receiver.isWebSocket
                  ? wallClockText ?? '정보 없음'
                  : '정보 없음 (RTSP)',
              valueWidth: 132,
              color: !connected || wallClockText == null
                  ? Colors.grey
                  : Colors.lightBlueAccent,
            ),
            const SizedBox(width: 14),
            _StatusChip(
              label: '전송 방식',
              value: receiver.isWebSocket
                  ? 'WebSocket'
                  : receiver.isRtsp
                  ? 'RTSP'
                  : '대기',
              valueWidth: 72,
              color: receiver.connected ? Colors.blueAccent : Colors.grey,
            ),
            const SizedBox(width: 14),
            _StatusChip(
              label: '영상',
              value: !connected ? '-' : selectedFrame?.label ?? '정보 없음',
              valueWidth: 74,
              color: connected && selectedFrame != null
                  ? Colors.lightBlueAccent
                  : Colors.grey,
            ),
            const SizedBox(width: 14),
            _StatusChip(
              label: '해상도',
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
      _station.layout.slotCount,
      (index) => index < _station.slots.length ? _station.slots[index] : '',
    );
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          for (var row = 0; row < _station.layout.rows; row++) ...[
            if (row > 0) const SizedBox(height: 8),
            Expanded(
              child: Row(
                children: [
                  for (
                    var column = 0;
                    column < _station.layout.columns;
                    column++
                  ) ...[
                    if (column > 0) const SizedBox(width: 8),
                    Expanded(
                      child: _buildStationCameraTile(
                        receiver,
                        slots[row * _station.layout.columns + column],
                        row * _station.layout.columns + column,
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
    final cameraStatus = _station.status?.cameras[cameraId];
    final isFresh =
        frame != null &&
        DateTime.now().difference(frame.receivedAt) <=
            const Duration(seconds: 3);
    String? waitingMessage;
    if (cameraId.isEmpty) {
      waitingMessage = '${slotIndex + 1}번 화면의 카메라를 선택해 주세요';
    } else if (!receiver.connected) {
      waitingMessage = '연결 끊김';
    } else if (_station.sourceBusy) {
      waitingMessage = '카메라 선택 적용 중...';
    } else if (frame == null || !isFresh) {
      waitingMessage = cameraStatus?.lastError.isNotEmpty == true
          ? cameraStatus!.lastError
          : '새 영상 대기 중: $cameraId';
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
                  cameraId.isEmpty ? '화면 ${slotIndex + 1}' : cameraId,
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
    final status = _station.status;
    final source = _station.source;
    final cameraIds = <String>{
      ...?source?.cameras,
      ...?status?.cameras.keys,
      ...?source?.cameraIds,
    }.where((cameraId) => cameraId.isNotEmpty).toList(growable: false)..sort();
    final selectedCycleId =
        _station.cycles.containsKey(_station.selectedCycleId)
        ? _station.selectedCycleId
        : _station.cycles.isEmpty
        ? null
        : _station.cycles.keys.last;
    final selectedResult = selectedCycleId == null
        ? null
        : _station.cycles[selectedCycleId];
    final queueText = status == null
        ? '대기열: 조회 중'
        : '대기열: ${status.pendingCount}/${status.maxPendingCaptures}'
              '${status.busy ? ' + 검사 중' : ''}';

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
                Text(
                  status == null ? '검사 장비' : '검사 장비: ${status.setId}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                SegmentedButton<StationViewerLayout>(
                  segments: [
                    for (final layout in StationViewerLayout.values)
                      ButtonSegment(value: layout, label: Text(layout.label)),
                  ],
                  selected: {_station.layout},
                  showSelectedIcon: false,
                  onSelectionChanged:
                      _station.sourceBusy ||
                          _station.undistortionBusy ||
                          source == null
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
                for (var slot = 0; slot < _station.layout.slotCount; slot++)
                  SizedBox(
                    width: 190,
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          key: ValueKey(
                            'station-camera-${_station.layout.name}-$slot-${_stationCameraForSlot(slot)}',
                          ),
                          initialValue: _stationCameraForSlot(slot),
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: '카메라 ${slot + 1}',
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('비어 있음'),
                            ),
                            for (final cameraId in cameraIds)
                              DropdownMenuItem(
                                value: cameraId,
                                child: Text(
                                  cameraId,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged:
                              _station.sourceBusy ||
                                  _station.undistortionBusy ||
                                  source == null
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
                        if (_stationCameraForSlot(slot).isNotEmpty)
                          StationUndistortionControl(
                            key: ValueKey(
                              'undistortion-${_station.session}-${settings.detectorBaseUrl}-${_stationCameraForSlot(slot)}',
                            ),
                            api: _captureApi,
                            settings: settings,
                            cameraId: _stationCameraForSlot(slot),
                            observedEnabled: status
                                ?.cameras[_stationCameraForSlot(slot)]
                                ?.undistortionEnabled,
                            blocked:
                                !receiver.connected ||
                                status == null ||
                                !status.ready ||
                                status.busy ||
                                status.pendingCount > 0 ||
                                _captureActionInFlight ||
                                _station.sourceBusy ||
                                _station.undistortionBusy,
                            onApplyingChanged: (value) => setState(
                              () => _station.undistortionBusy = value,
                            ),
                          ),
                      ],
                    ),
                  ),
                Text(queueText, style: const TextStyle(fontSize: 12)),
                if (status != null)
                  Text(
                    '촬영: ${status.captureCount}',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                if (status?.activeCycleId.isNotEmpty == true)
                  Text(
                    '검사 중: ${_shortCycleId(status!.activeCycleId)}',
                    style: const TextStyle(
                      color: Colors.lightBlueAccent,
                      fontSize: 12,
                    ),
                  ),
                if (status?.ready == false)
                  const Text(
                    '장비 준비 안 됨',
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                  ),
                if (status != null)
                  Text(
                    '카메라 연결: ${status.cameras.values.where((camera) => camera.open).length}/${status.cameras.length}',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('제품 레시피 · 생산 검사 · PLC 진단'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ProductionScreen(),
                ),
              ),
            ),
          ),
          const Text('개별 수동 촬영 · 생산 검사는 레시피 화면에서 시작'),
          StationCaptureActions(
            status: status,
            connected: receiver.connected,
            inFlight: _captureActionInFlight || _station.undistortionBusy,
            onCapture: (target) =>
                _requestCapture(settings, stationTarget: target),
          ),
          if (_station.cycles.isNotEmpty) ...[
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
                        labelText: '촬영별 검사 결과',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final cycleId
                            in _station.cycles.keys.toList().reversed)
                          DropdownMenuItem(
                            value: cycleId,
                            child: Text(
                              _shortCycleId(cycleId),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _station.selectedCycleId = value),
                    ),
                  ),
                  if (selectedResult != null) ...[
                    const SizedBox(width: 10),
                    _stationResultChip(
                      statusLabel(selectedResult.presentationStatus),
                      _stationStatusColor(selectedResult.presentationStatus),
                    ),
                    if (selectedResult.group.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text('검사 그룹 ${selectedResult.group}'),
                    ],
                    for (final inspection
                        in selectedResult.inspections.values) ...[
                      const SizedBox(width: 8),
                      _stationResultChip(
                        '${inspection.inspectionId}: ${statusLabel(inspection.status)}'
                        '${inspection.reason.isEmpty ? '' : ' (${inspection.reason})'}',
                        _stationStatusColor(inspection.status),
                      ),
                    ],
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.data_object, size: 16),
                      label: const Text('상세 보기'),
                      onPressed: () =>
                          _showStationResultDetails(selectedResult),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (_station.error != null ||
              status?.lastError.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(
              _station.error ?? status!.lastError,
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
          ],
        ],
      ),
    );
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

  Future<void> _showManagementCredentialsDialog() async {
    final settings = context.read<SettingsProvider>().settings;
    final credentials = context.read<ReferenceCredentialProvider>();
    String? existing;
    try {
      existing = await credentials.readToken(settings);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('인증 정보 저장소를 사용할 수 없습니다: $error')),
        );
      }
      return;
    }
    if (!mounted) return;
    final controller = TextEditingController();
    var hidden = true;
    var enteredToken = '';
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('관리 인증 설정'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  existing == null
                      ? '이 API 서버의 토큰이 저장되어 있지 않습니다.'
                      : '이 API 서버의 토큰이 저장되어 있습니다.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  obscureText: hidden,
                  enableSuggestions: false,
                  autocorrect: false,
                  onChanged: (value) =>
                      setDialogState(() => enteredToken = value.trim()),
                  decoration: InputDecoration(
                    labelText: '관리 토큰',
                    hintText: existing == null
                        ? '장비 관리 토큰을 붙여 넣어 주세요'
                        : '비워 두면 기존 토큰을 유지합니다',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: hidden ? '토큰 표시' : '토큰 숨기기',
                      onPressed: () => setDialogState(() => hidden = !hidden),
                      icon: Icon(
                        hidden
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '운영체제 인증 정보 저장소에 보관합니다. 원격 관리에는 보안 터널이나 TLS 프록시를 사용해 주세요.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, 'clear'),
                child: const Text('토큰 삭제'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: existing != null || isValidReferenceToken(enteredToken)
                  ? () => Navigator.pop(dialogContext, 'save')
                  : null,
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
    try {
      if (action == 'clear') {
        await credentials.clearToken(settings);
      } else if (action == 'save' && controller.text.trim().isNotEmpty) {
        await credentials.saveToken(settings, controller.text);
      }
      if (mounted && action != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'clear'
                  ? '관리 토큰 삭제 완료.'
                  : controller.text.trim().isEmpty
                  ? '기존 관리 토큰을 유지했습니다.'
                  : '관리 토큰 저장 완료.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('인증 정보 변경 실패: $error')));
      }
    } finally {
      controller.dispose();
    }
  }

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
        title: Text('검사 ${_shortCycleId(result.cycleId)}'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(details),
              style: const TextStyle(fontFamily: 'NotoSansKR', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('닫기'),
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
        title: const Text('연결'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: streamController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '영상 URL',
                hintText:
                    'rtsp://192.168.0.10:8554/live  또는  ws://192.168.0.10:8080/',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: 'NotoSansKR', fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: apiController,
              decoration: const InputDecoration(
                labelText: 'API 기본 URL',
                hintText: 'http://192.168.0.10:8090',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: 'NotoSansKR', fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
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
            child: const Text('연결'),
          ),
        ],
      ),
    );
  }

  Future<void> _initializeStation(
    AppSettings settings,
    FrameReceiverService receiver,
  ) => _station.initialize(settings);
  void _leaveStationMode(FrameReceiverService receiver) => _station.leave();
  String _stationCameraForSlot(int slot) => _station.cameraForSlot(slot);
  Future<void> _changeStationViewerLayout(
    AppSettings settings,
    FrameReceiverService receiver,
    StationViewerLayout layout,
    List<String> cameras,
  ) => _station.changeLayout(layout, cameras);
  Future<void> _changeStationCameraSlot(
    AppSettings settings,
    FrameReceiverService receiver,
    int slot,
    String cameraId,
  ) => _station.changeCamera(slot, cameraId);

  Future<void> _disconnect(FrameReceiverService receiver) async {
    _connectionGeneration++;
    _recordingActionInFlight = false;
    _station.suspend();
    _captureActionInFlight = false;
    await receiver.disconnect();
    if (mounted) setState(() {});
  }

  Future<void> _connect({
    required BuildContext context,
    required FrameReceiverService receiver,
    required String streamPath,
    required String? apiBaseUrl,
  }) async {
    final connection = ++_connectionGeneration;
    _station.suspend();
    _captureActionInFlight = _recordingActionInFlight = false;
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
      if (!mounted || connection != _connectionGeneration) return;
      await settingsProvider.updateConnectionUrls(
        streamPath: streamPath,
        detectorBaseUrl: targetApiBaseUrl,
        remoteDeviceKind: deviceInfo.kind,
        personRoiAlertDisabled: deviceInfo.personRoiAlertDisabled,
      );
      if (!mounted || connection != _connectionGeneration) return;
      if (deviceInfo.isInspectionStation) {
        await _initializeStation(settingsProvider.settings, receiver);
      } else {
        _leaveStationMode(receiver);
      }
      if (!mounted || connection != _connectionGeneration) return;
      if (deviceInfo.kind == RemoteDeviceKind.hss ||
          deviceInfo.kind == RemoteDeviceKind.capture) {
        final recordingStatus = await _recordingApi.fetchStatus(
          settingsProvider.settings,
        );
        if (context.mounted && connection == _connectionGeneration) {
          setState(() => _recordingStatus = recordingStatus);
        }
      } else if (context.mounted && connection == _connectionGeneration) {
        setState(() => _recordingStatus = null);
      }
      if (context.mounted && connection == _connectionGeneration) {
        unawaited(receiver.connect(streamPath));
      }
    } catch (e) {
      if (context.mounted && connection == _connectionGeneration) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('장비 정보 조회 실패: $e')));
      }
    }
  }

  Future<void> _runRecordingAction(
    Future<RemoteRecordingStatus> Function(RemoteRecordingApiService api)
    action, {
    String Function(RemoteRecordingStatus status)? successMessage,
  }) async {
    final connection = _connectionGeneration;
    setState(() => _recordingActionInFlight = true);
    try {
      final next = await action(_recordingApi);
      if (!mounted || connection != _connectionGeneration) return;
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
      if (!mounted || connection != _connectionGeneration) return;
      setState(() => _recordingActionInFlight = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('녹화 API 오류: $e')));
    }
  }

  Future<void> _requestCapture(
    AppSettings settings, {
    StationCaptureTarget? stationTarget,
  }) async {
    if (_captureActionInFlight) return;
    final connection = _connectionGeneration;
    setState(() => _captureActionInFlight = true);
    try {
      if (_station.active) {
        if (stationTarget == null) {
          throw StateError('장비 촬영 대상을 지정해야 합니다');
        }
        if (!await _station.capture(stationTarget)) return;
      } else {
        await _captureApi.requestCapture(settings);
      }
      if (!mounted || connection != _connectionGeneration) return;
      setState(() => _captureActionInFlight = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_station.active ? '장비가 촬영 요청을 접수했습니다' : '촬영 요청 완료'),
        ),
      );
    } catch (e) {
      if (!mounted || connection != _connectionGeneration) return;
      setState(() => _captureActionInFlight = false);
      final message = e is RemoteCaptureApiException && e.statusCode == 409
          ? '촬영 대기열이 가득 찼습니다 (409)'
          : e is RemoteCaptureApiException && e.statusCode == 503
          ? '장비가 준비되지 않았습니다 (503)'
          : '촬영 API 오류: $e';
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
                  'ROI 경고 꺼짐',
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
          fontFamily: 'NotoSansKR',
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
              fontFamily: 'NotoSansKR',
            ),
          ),
        ),
      ],
    );
  }
}
