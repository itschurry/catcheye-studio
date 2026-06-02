import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../services/frame_receiver_service.dart';
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
            color: selected ? colorScheme.primary : const Color(0xFF4A4A4A),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              color: selected
                  ? const Color(0xFF4A4A4A)
                  : const Color(0xFF252525),
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
        border: Border.all(color: const Color(0xFF4A4A4A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            color: const Color(0xFF252525),
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
  final RemoteDeviceKind? remoteDeviceKind;
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
    required this.remoteDeviceKind,
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
    final pickControlsEnabled = remoteDeviceKind == RemoteDeviceKind.pick;
    final rgbCameraStreams = streams.where(_isRgbCameraStream).toList();
    final depthStreams = streams.where(_isDepthOrPointCloudStream).toList();
    final otherStreams = streams
        .where((stream) => !rgbCameraStreams.contains(stream))
        .where((stream) => !depthStreams.contains(stream))
        .toList();

    return Padding(
      padding: const EdgeInsets.all(16),
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
                if (pickControlsEnabled) ...[
                  _SplitViewControls(
                    streams: streams,
                    splitView: splitView,
                    leftKey: splitLeftStreamKey,
                    rightKey: splitRightStreamKey,
                    onSplitViewChanged: onSplitViewChanged,
                    onSplitSelectionChanged: onSplitSelectionChanged,
                  ),
                  const SizedBox(height: 14),
                ],
                _StreamGroupCard(
                  title: 'RGB Camera',
                  icon: Icons.videocam_outlined,
                  streams: rgbCameraStreams,
                  selectedStreamKey: receiver.selectedStreamKey,
                  onSelectStream: receiver.selectStream,
                ),
                if (depthStreams.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _StreamGroupCard(
                    title: 'Depth / 3D',
                    icon: Icons.sensors,
                    streams: depthStreams,
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
                if (pickControlsEnabled &&
                    selected?.isPointCloud == true &&
                    pointCloud != null) ...[
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

  bool _isDepthOrPointCloudStream(ViewerStreamFrame stream) {
    final values = _streamIdentityValues(stream);
    return values.any(
      (value) => value.contains('depth') || value.contains('pointcloud'),
    );
  }

  bool _isRgbCameraStream(ViewerStreamFrame stream) {
    final values = _streamIdentityValues(stream);
    return values.any(
      (value) =>
          value == 'rgb' ||
          value == 'color' ||
          value == 'camera' ||
          value.contains('rgb_camera') ||
          value.contains('projected_depth'),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF4A4A4A)),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF4A4A4A)),
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
          color: selected ? const Color(0xFF4A4A4A) : const Color(0xFF1F1F1F),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? colorScheme.primary : const Color(0xFF4A4A4A),
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

  static const double _angleMin = -math.pi;
  static const double _angleMax = math.pi;

  double _wrapAngle(double value) {
    final wrapped = (value + math.pi) % (math.pi * 2);
    return wrapped < 0 ? wrapped + math.pi : wrapped - math.pi;
  }

  double _unwrapSliderAngle(double current, double nextWrapped) {
    final currentWrapped = _wrapAngle(current);
    var delta = nextWrapped - currentWrapped;
    if (delta > math.pi) delta -= math.pi * 2;
    if (delta < -math.pi) delta += math.pi * 2;
    return current + delta;
  }

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
    final yawSliderValue = _wrapAngle(yaw);
    final pitchSliderValue = _wrapAngle(pitch);

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
          value: yawSliderValue,
          min: _angleMin,
          max: _angleMax,
          onChanged: (value) => onYawChanged(_unwrapSliderAngle(yaw, value)),
        ),
        _OptionLabel(
          value:
              'Pitch ${(pitch * 180 / 3.141592653589793).toStringAsFixed(0)} deg',
        ),
        Slider(
          value: pitchSliderValue,
          min: _angleMin,
          max: _angleMax,
          onChanged: (value) =>
              onPitchChanged(_unwrapSliderAngle(pitch, value)),
        ),
        _OptionLabel(value: 'Zoom ${zoom.toStringAsFixed(1)}x'),
        Slider(value: zoom, min: 0.2, max: 8.0, onChanged: onZoomChanged),
        _OptionLabel(value: 'Point size ${pointSize.toStringAsFixed(1)}'),
        Slider(
          value: pointSize,
          min: 0.5,
          max: 12.0,
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
