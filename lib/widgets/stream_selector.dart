import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/frame_receiver_service.dart';
import '../services/remote_cubeeye_api_service.dart';
import 'point_cloud_viewer.dart';

class SplitStreamPanel extends StatelessWidget {
  final ViewerStreamFrame stream;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  const SplitStreamPanel({
    super.key,
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

class MissingSplitPanel extends StatelessWidget {
  final String label;

  const MissingSplitPanel({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: const Color(0xFF30474B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            color: const Color(0xFF101B1D),
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.grey,
              ),
            ),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'No stream',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SplitStreamSelection {
  final String? leftKey;
  final String? rightKey;

  const SplitStreamSelection({required this.leftKey, required this.rightKey});
}

class StreamSelector extends StatelessWidget {
  final FrameReceiverService receiver;
  final bool splitView;
  final String? splitLeftStreamKey;
  final String? splitRightStreamKey;
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
  final ValueChanged<bool> onSplitViewChanged;
  final ValueChanged<SplitStreamSelection> onSplitSelectionChanged;
  final ValueChanged<RangeValues> onDepthRangeChanged;
  final VoidCallback onLockView;
  final VoidCallback onUnlockView;
  final VoidCallback onResetView;

  const StreamSelector({
    super.key,
    required this.receiver,
    required this.splitView,
    required this.splitLeftStreamKey,
    required this.splitRightStreamKey,
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
    required this.onSplitViewChanged,
    required this.onSplitSelectionChanged,
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
    final rgbCameraStreams = streams.where(_isRgbCameraStream).toList();
    final cubeEyeStreams = streams.where(_isCubeEyeStream).toList();
    final otherStreams = streams
        .where((stream) => !rgbCameraStreams.contains(stream))
        .where((stream) => !cubeEyeStreams.contains(stream))
        .toList();

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
                _SplitViewControls(
                  streams: streams,
                  splitView: splitView,
                  leftKey: splitLeftStreamKey,
                  rightKey: splitRightStreamKey,
                  onSplitViewChanged: onSplitViewChanged,
                  onSplitSelectionChanged: onSplitSelectionChanged,
                ),
                const SizedBox(height: 14),
                _StreamGroupCard(
                  title: 'RGB Camera',
                  icon: Icons.videocam_outlined,
                  streams: rgbCameraStreams,
                  selectedStreamKey: receiver.selectedStreamKey,
                  onSelectStream: receiver.selectStream,
                ),
                if (cubeEyeStreams.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _StreamGroupCard(
                    title: 'CubeEye ToF',
                    icon: Icons.sensors,
                    streams: cubeEyeStreams,
                    selectedStreamKey: receiver.selectedStreamKey,
                    onSelectStream: receiver.selectStream,
                  ),
                ],
                if (otherStreams.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _StreamGroupCard(
                    title: 'Other Streams',
                    icon: Icons.account_tree_outlined,
                    streams: otherStreams,
                    selectedStreamKey: receiver.selectedStreamKey,
                    onSelectStream: receiver.selectStream,
                  ),
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
                if (hasCubeEyeStream) ...[
                  const Divider(height: 24),
                  const _CubeEyeControls(),
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
        kind == 'pointcloud' ||
        name.contains('cubeeye');
  }

  bool _isRgbCameraStream(ViewerStreamFrame stream) {
    final values = _streamIdentityValues(stream);
    return values.any(
      (value) =>
          value == 'rgb' ||
          value == 'color' ||
          value == 'camera' ||
          value.contains('rgb_camera'),
    );
  }

  List<String> _streamIdentityValues(ViewerStreamFrame stream) {
    return [
      stream.name.toLowerCase(),
      stream.kind.toLowerCase(),
      stream.label.toLowerCase(),
    ];
  }
}

class _SplitViewControls extends StatelessWidget {
  final List<ViewerStreamFrame> streams;
  final bool splitView;
  final String? leftKey;
  final String? rightKey;
  final ValueChanged<bool> onSplitViewChanged;
  final ValueChanged<SplitStreamSelection> onSplitSelectionChanged;

  const _SplitViewControls({
    required this.streams,
    required this.splitView,
    required this.leftKey,
    required this.rightKey,
    required this.onSplitViewChanged,
    required this.onSplitSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF101B1D),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF30474B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: _PanelHeader(
                  icon: Icons.splitscreen_outlined,
                  title: 'Split View',
                  subtitle: 'Choose panel streams',
                ),
              ),
              Switch(value: splitView, onChanged: onSplitViewChanged),
            ],
          ),
          const SizedBox(height: 10),
          _SplitStreamPicker(
            label: 'Left',
            streams: streams,
            value: leftKey,
            onChanged: splitView
                ? (value) => onSplitSelectionChanged(
                    SplitStreamSelection(leftKey: value, rightKey: rightKey),
                  )
                : null,
          ),
          const SizedBox(height: 8),
          _SplitStreamPicker(
            label: 'Right',
            streams: streams,
            value: rightKey,
            onChanged: splitView
                ? (value) => onSplitSelectionChanged(
                    SplitStreamSelection(leftKey: leftKey, rightKey: value),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _SplitStreamPicker extends StatelessWidget {
  final String label;
  final List<ViewerStreamFrame> streams;
  final String? value;
  final ValueChanged<String?>? onChanged;

  const _SplitStreamPicker({
    required this.label,
    required this.streams,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final validValue = streams.any((stream) => stream.key == value)
        ? value
        : null;
    return DropdownButtonFormField<String>(
      initialValue: validValue,
      isDense: true,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [
        for (final stream in streams)
          DropdownMenuItem(value: stream.key, child: Text(stream.label)),
      ],
      onChanged: onChanged,
    );
  }
}

class _StreamGroupCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<ViewerStreamFrame> streams;
  final String? selectedStreamKey;
  final ValueChanged<String> onSelectStream;

  const _StreamGroupCard({
    required this.title,
    required this.icon,
    required this.streams,
    required this.selectedStreamKey,
    required this.onSelectStream,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF101B1D),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF30474B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(icon: icon, title: title),
          const SizedBox(height: 10),
          if (streams.isEmpty)
            const Text(
              'No stream',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          for (var i = 0; i < streams.length; i++) ...[
            _StreamSlot(
              stream: streams[i],
              selected: streams[i].key == selectedStreamKey,
              onTap: () => onSelectStream(streams[i].key),
            ),
            if (i != streams.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _StreamSlot extends StatelessWidget {
  final ViewerStreamFrame stream;
  final bool selected;
  final VoidCallback onTap;

  const _StreamSlot({
    required this.stream,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = stream.size;
    final detail = stream.isPointCloud
        ? '${stream.pointCount} pts'
        : size == null
        ? '-'
        : '${size.width.toInt()} x ${size.height.toInt()}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF183C42) : const Color(0xFF0B1416),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? colorScheme.primary : const Color(0xFF26383B),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.circle, size: 8, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                stream.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? colorScheme.primary : Colors.white,
                ),
              ),
            ),
            Text(
              detail,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const _PanelHeader({required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: colorScheme.secondary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
            ],
          ),
        ),
      ],
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
  RgbCubeEyeOffset? _rgbCubeEyeOffset;
  double _offsetU = 0.0;
  double _offsetV = 0.4;
  String? _error;
  bool _loading = false;
  bool _loadedOnce = false;
  bool _initializedFromSettings = false;

  static const double _offsetMin = -1.0;
  static const double _offsetMax = 1.0;
  static const int _offsetDivisions = 2000;

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
              child: _PanelHeader(
                icon: Icons.api,
                title: 'CubeEye Properties API',
                subtitle: 'Remote device settings',
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
        const SizedBox(height: 10),
        if (_error != null)
          Text(
            _error!,
            style: const TextStyle(fontSize: 11, color: Colors.redAccent),
          ),
        const SizedBox(height: 8),
        const Text('Device framerate', style: TextStyle(fontSize: 12)),
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
          title: const Text(
            'Device auto exposure',
            style: TextStyle(fontSize: 12),
          ),
          value: properties?.autoExposure ?? false,
          onChanged: controlsEnabled
              ? (value) => _setProperty('auto_exposure', value)
              : null,
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Device illumination',
            style: TextStyle(fontSize: 12),
          ),
          value: properties?.illumination ?? false,
          onChanged: controlsEnabled
              ? (value) => _setProperty('illumination', value)
              : null,
        ),
        const Text('Device depth range', style: TextStyle(fontSize: 12)),
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
        const Text('CubeEye filters', style: TextStyle(fontSize: 12)),
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
        const Divider(height: 24),
        const _PanelHeader(
          icon: Icons.tune,
          title: 'Calibration Offset',
          subtitle: 'RGB to CubeEye alignment',
        ),
        const SizedBox(height: 8),
        _OffsetSlider(
          label: 'U',
          value: _offsetU,
          enabled: !_loading,
          min: _offsetMin,
          max: _offsetMax,
          divisions: _offsetDivisions,
          onChanged: (value) => setState(() => _offsetU = value),
          onChangeEnd: (_) => _setRgbCubeEyeOffset(),
        ),
        _OffsetSlider(
          label: 'V',
          value: _offsetV,
          enabled: !_loading,
          min: _offsetMin,
          max: _offsetMax,
          divisions: _offsetDivisions,
          onChanged: (value) => setState(() => _offsetV = value),
          onChangeEnd: (_) => _setRgbCubeEyeOffset(),
        ),
        if (_rgbCubeEyeOffset != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Current ${_rgbCubeEyeOffset!.u.toStringAsFixed(3)}, ${_rgbCubeEyeOffset!.v.toStringAsFixed(3)}',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
      ],
    );
  }

  Future<void> _load() async {
    _loadedOnce = true;
    await _run(() async {
      final settings = context.read<SettingsProvider>().settings;
      await _applyOffset(await _api.fetchRgbCubeEyeOffset(settings));
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

  Future<void> _setRgbCubeEyeOffset() async {
    await _run(() async {
      final settings = context.read<SettingsProvider>().settings;
      await _applyOffset(
        await _api.setRgbCubeEyeOffset(
          settings,
          RgbCubeEyeOffset(u: _offsetU, v: _offsetV),
        ),
      );
    });
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

  Future<void> _applyOffset(RgbCubeEyeOffset offset) async {
    setState(() {
      _rgbCubeEyeOffset = offset;
      _offsetU = offset.u;
      _offsetV = offset.v;
    });
  }

  TextEditingController _controllerFor(String key) {
    return _propertyControllers.putIfAbsent(key, () => TextEditingController());
  }
}

class _OffsetSlider extends StatelessWidget {
  final String label;
  final double value;
  final bool enabled;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _OffsetSlider({
    required this.label,
    required this.value,
    required this.enabled,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: value.toStringAsFixed(3),
            onChanged: enabled ? onChanged : null,
            onChangeEnd: enabled ? onChangeEnd : null,
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            value.toStringAsFixed(3),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
      ],
    );
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
        const _PanelHeader(
          icon: Icons.visibility_outlined,
          title: 'Viewer Properties',
          subtitle: 'Local display controls',
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
        const Text('Color palette', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 6),
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
              'Visible depth filter ${safeDepthMin.toStringAsFixed(1)} - ${safeDepthMax.toStringAsFixed(1)}',
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
