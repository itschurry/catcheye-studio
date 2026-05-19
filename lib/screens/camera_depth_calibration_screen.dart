import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/frame_receiver_service.dart';
import '../services/remote_cubeeye_api_service.dart';
import '../widgets/live_viewer.dart';

class CameraDepthCalibrationScreen extends StatefulWidget {
  const CameraDepthCalibrationScreen({super.key});

  @override
  State<CameraDepthCalibrationScreen> createState() =>
      _CameraDepthCalibrationScreenState();
}

class _CameraDepthCalibrationScreenState
    extends State<CameraDepthCalibrationScreen> {
  final FrameReceiverService _receiver = FrameReceiverService();
  final RemoteCubeEyeApiService _api = RemoteCubeEyeApiService();
  RgbCubeEyeExtrinsic? _extrinsic;
  String? _selectedStreamKey;
  String? _error;
  bool _started = false;
  bool _busy = false;

  static const _rtKeys = <String>[
    'tx_m',
    'ty_m',
    'tz_m',
    'roll_deg',
    'pitch_deg',
    'yaw_deg',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final settings = context.read<SettingsProvider>().settings;
    unawaited(_receiver.connect(settings.streamUri.toString()));
    unawaited(_loadOffset());
  }

  @override
  void dispose() {
    _receiver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<FrameReceiverService>.value(
      value: _receiver,
      child: Consumer2<FrameReceiverService, SettingsProvider>(
        builder: (context, receiver, settingsProvider, _) {
          final settings = settingsProvider.settings;
          final streams = receiver.streams.values.toList()
            ..sort((a, b) => a.payloadIndex.compareTo(b.payloadIndex));
          final selected =
              _selectedStream(streams) ?? _preferredStream(streams);
          return Column(
            children: [
              _DepthCalibrationToolbar(
                receiver: receiver,
                streamUrl: settings.streamUri.toString(),
              ),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _buildPreview(receiver, selected)),
                    SizedBox(width: 390, child: _buildPanel(streams)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  ViewerStreamFrame? _selectedStream(List<ViewerStreamFrame> streams) {
    final key = _selectedStreamKey;
    if (key == null) return null;
    for (final stream in streams) {
      if (stream.key == key) return stream;
    }
    return null;
  }

  ViewerStreamFrame? _preferredStream(List<ViewerStreamFrame> streams) {
    for (final stream in streams) {
      if (stream.isProjectedDepth) return stream;
    }
    for (final stream in streams) {
      if (stream.kind == 'depth' && stream.isJpeg) return stream;
    }
    for (final stream in streams) {
      if (stream.kind == 'camera' && stream.isJpeg) return stream;
    }
    return streams.isEmpty ? null : streams.first;
  }

  Widget _buildPreview(
    FrameReceiverService receiver,
    ViewerStreamFrame? selected,
  ) {
    if (selected == null) {
      return LiveViewer(
        controller: receiver.videoController,
        connected: receiver.connected,
        isRtsp: receiver.isRtsp,
        frameData: receiver.currentFrame,
      );
    }
    if (selected.isProjectedDepth && selected.projectedDepth != null) {
      final camera = receiver.streams['camera'];
      if (camera != null && camera.isJpeg) {
        return _ProjectedDepthPreview(camera: camera, projected: selected);
      }
    }
    if (selected.isJpeg) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Image.memory(
          selected.jpegBytes,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        ),
      );
    }
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Text(
        'Unsupported stream: ${selected.encoding.name}',
        style: const TextStyle(color: Colors.grey),
      ),
    );
  }

  Widget _buildPanel(List<ViewerStreamFrame> streams) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF1F1F1F),
        border: Border(left: BorderSide(color: Color(0xFF4A4A4A))),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionTitle('Streams'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final stream in streams)
                ChoiceChip(
                  label: Text(stream.label),
                  selected:
                      (_selectedStreamKey ?? _preferredStream(streams)?.key) ==
                      stream.key,
                  onSelected: (_) =>
                      setState(() => _selectedStreamKey = stream.key),
                ),
            ],
          ),
          const SizedBox(height: 20),
          const _SectionTitle('CubeEye to RGB R/T'),
          const SizedBox(height: 8),
          for (final key in _rtKeys) _rtSlider(key),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('CubeEye distortion correction'),
            subtitle: const Text('SDK distortion coefficient로 depth pixel 보정'),
            value: _extrinsic?.cubeEyeDistortionCorrectionEnabled ?? false,
            onChanged: _busy || _extrinsic == null
                ? null
                : (value) {
                    setState(() {
                      _extrinsic = _extrinsic!.copyWith(
                        cubeEyeDistortionCorrectionEnabled: value,
                      );
                    });
                    unawaited(_save());
                  },
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.check, size: 16),
            label: Text(_busy ? 'Saving' : 'Apply'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _resetRt,
            icon: const Icon(Icons.restart_alt, size: 16),
            label: const Text('Reset R/T'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _loadOffset,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Reload'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(fontSize: 12, color: Colors.redAccent),
            ),
          ],
        ],
      ),
    );
  }

  Widget _rtSlider(String key) {
    final extrinsic = _extrinsic;
    final isRotation = key.endsWith('_deg');
    final min = isRotation ? -180.0 : -2.0;
    final max = isRotation ? 180.0 : 2.0;
    final divisions = isRotation ? 3600 : 4000;
    final value = (extrinsic?.values[key] ?? 0.0).clamp(min, max).toDouble();
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(key, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: Slider(
            min: min,
            max: max,
            divisions: divisions,
            value: value,
            label: value.toStringAsFixed(3),
            onChanged: _busy || extrinsic == null
                ? null
                : (next) {
                    setState(() {
                      _extrinsic = extrinsic.copyWith(
                        values: {...extrinsic.values, key: next},
                      );
                    });
                  },
            onChangeEnd: _busy || extrinsic == null ? null : (_) => _save(),
          ),
        ),
        SizedBox(
          width: 62,
          child: Text(
            value.toStringAsFixed(3),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Future<void> _loadOffset() async {
    await _run(() async {
      final settings = context.read<SettingsProvider>().settings;
      _extrinsic = await _api.fetchRgbCubeEyeExtrinsic(settings);
    });
  }

  Future<void> _save() async {
    final current = _extrinsic;
    if (current == null) return;
    await _run(() async {
      final values = <String, double>{...current.values};
      for (final key in _rtKeys) {
        values[key] = values[key] ?? 0.0;
      }
      final settings = context.read<SettingsProvider>().settings;
      _extrinsic = await _api.setRgbCubeEyeExtrinsic(
        settings,
        current.copyWith(values: values),
      );
    });
  }

  void _resetRt() {
    final current = _extrinsic;
    if (current == null) return;
    final values = <String, double>{...current.values};
    for (final key in _rtKeys) {
      values[key] = 0.0;
    }
    setState(() => _extrinsic = current.copyWith(values: values));
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}

class _ProjectedDepthPreview extends StatelessWidget {
  const _ProjectedDepthPreview({required this.camera, required this.projected});

  final ViewerStreamFrame camera;
  final ViewerStreamFrame projected;

  @override
  Widget build(BuildContext context) {
    final imageSize = camera.size ?? projected.size;
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            camera.jpegBytes,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          ),
          ColoredBox(color: Colors.black.withValues(alpha: 0.18)),
          CustomPaint(
            painter: _ProjectedDepthPainter(
              data: projected.projectedDepth!,
              imageSize: imageSize,
              pointSize: 2.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectedDepthPainter extends CustomPainter {
  const _ProjectedDepthPainter({
    required this.data,
    required this.imageSize,
    required this.pointSize,
  });

  final ProjectedDepthData data;
  final Size? imageSize;
  final double pointSize;

  @override
  void paint(Canvas canvas, Size size) {
    final sourceSize = imageSize;
    if (sourceSize == null || sourceSize.width <= 0 || sourceSize.height <= 0) {
      return;
    }
    final fitted = applyBoxFit(BoxFit.contain, sourceSize, size);
    final output = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    final sx = output.width / sourceSize.width;
    final sy = output.height / sourceSize.height;
    final paint = Paint()
      ..color = const Color(0xFFFF7A2F)
      ..style = PaintingStyle.fill;
    for (var i = 0; i < data.pointCount; i++) {
      final x = output.left + data.xAt(i) * sx;
      final y = output.top + data.yAt(i) * sy;
      canvas.drawCircle(Offset(x, y), pointSize, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ProjectedDepthPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.pointSize != pointSize;
  }
}

class _DepthCalibrationToolbar extends StatelessWidget {
  const _DepthCalibrationToolbar({
    required this.receiver,
    required this.streamUrl,
  });

  final FrameReceiverService receiver;
  final String streamUrl;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colorScheme.surface,
      child: Row(
        children: [
          Icon(Icons.threed_rotation, color: colorScheme.secondary, size: 20),
          const SizedBox(width: 8),
          const Text(
            'Camera-Depth Calibration',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 12),
          const Text(
            'CubeEye-RGB extrinsic / A3 board',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const Spacer(),
          if (receiver.connecting) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            const Text('Connecting', style: TextStyle(fontSize: 12)),
          ] else if (receiver.connected) ...[
            const Icon(Icons.circle, size: 8, color: Colors.green),
            const SizedBox(width: 8),
            Text(
              receiver.connectedUri?.toString() ?? streamUrl,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: receiver.disconnect,
              icon: const Icon(Icons.power_off, size: 16),
              label: const Text('Disconnect'),
            ),
          ] else ...[
            if (receiver.errorMessage != null)
              SizedBox(
                width: 360,
                child: Text(
                  receiver.errorMessage!,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.redAccent),
                ),
              ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: () => receiver.connect(streamUrl),
              icon: const Icon(Icons.power, size: 16),
              label: const Text('Connect'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
    );
  }
}
