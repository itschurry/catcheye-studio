import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/frame_receiver_service.dart';
import '../services/remote_cubeeye_api_service.dart';
import '../widgets/live_viewer.dart';

class CameraCalibrationScreen extends StatefulWidget {
  const CameraCalibrationScreen({super.key});

  @override
  State<CameraCalibrationScreen> createState() =>
      _CameraCalibrationScreenState();
}

class _CameraCalibrationScreenState extends State<CameraCalibrationScreen> {
  final FrameReceiverService _receiver = FrameReceiverService();
  final RemoteCubeEyeApiService _api = RemoteCubeEyeApiService();
  RgbIntrinsicCalibration? _calibration;
  RgbIntrinsic? _intrinsic;
  String? _error;
  bool _started = false;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final settings = context.read<SettingsProvider>().settings;
    unawaited(_receiver.connect(settings.streamUri.toString()));
    unawaited(_load());
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
          final camera = _cameraFrame(receiver);
          return Column(
            children: [
              _CalibrationToolbar(
                title: 'Camera Calibration',
                subtitle: 'RGB intrinsic / A4 checkerboard',
                receiver: receiver,
                streamUrl: settings.streamUri.toString(),
              ),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _buildPreview(receiver, camera)),
                    SizedBox(width: 380, child: _buildPanel()),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  ViewerStreamFrame? _cameraFrame(FrameReceiverService receiver) {
    final streams = receiver.streams.values.toList()
      ..sort((a, b) => a.payloadIndex.compareTo(b.payloadIndex));
    for (final stream in streams) {
      final key = '${stream.kind} ${stream.name}'.toLowerCase();
      if (stream.isJpeg && (key.contains('camera') || key.contains('rgb'))) {
        return stream;
      }
    }
    for (final stream in streams) {
      if (stream.isJpeg) return stream;
    }
    return receiver.selectedFrame?.isJpeg == true
        ? receiver.selectedFrame
        : null;
  }

  Widget _buildPreview(
    FrameReceiverService receiver,
    ViewerStreamFrame? camera,
  ) {
    return Container(
      color: Colors.black,
      child: camera == null
          ? LiveViewer(
              controller: receiver.videoController,
              connected: receiver.connected,
              isRtsp: receiver.isRtsp,
              frameData: receiver.currentFrame,
            )
          : Image.memory(
              camera.jpegBytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            ),
    );
  }

  Widget _buildPanel() {
    final calibration = _calibration;
    final intrinsic = _intrinsic;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF1F1F1F),
        border: Border(left: BorderSide(color: Color(0xFF4A4A4A))),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionTitle('RGB Intrinsic'),
          const SizedBox(height: 8),
          _MetricRow(label: 'Board', value: 'A4 / 9x6 / 20 mm'),
          _MetricRow(
            label: 'Captures',
            value: '${calibration?.captureCount ?? 0}',
          ),
          _MetricRow(
            label: 'RMS',
            value: calibration?.rmsError?.toStringAsFixed(4) ?? '-',
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            value: intrinsic?.undistortEnabled ?? false,
            onChanged: _busy || intrinsic == null ? null : _setIntrinsicApplied,
            title: const Text('Apply Intrinsic'),
            subtitle: Text(
              intrinsic == null
                  ? 'Not loaded'
                  : (intrinsic.undistortEnabled ? 'Enabled' : 'Disabled'),
            ),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricBox(label: 'fx', value: calibration?.values['fx']),
              _MetricBox(label: 'fy', value: calibration?.values['fy']),
              _MetricBox(label: 'cx', value: calibration?.values['cx']),
              _MetricBox(label: 'cy', value: calibration?.values['cy']),
              _MetricBox(label: 'k1', value: calibration?.values['dist_k1']),
              _MetricBox(label: 'k2', value: calibration?.values['dist_k2']),
              _MetricBox(label: 'p1', value: calibration?.values['dist_p1']),
              _MetricBox(label: 'p2', value: calibration?.values['dist_p2']),
              _MetricBox(label: 'k3', value: calibration?.values['dist_k3']),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _capture,
            icon: const Icon(Icons.add_a_photo_outlined, size: 16),
            label: const Text('Capture'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _solve,
            icon: const Icon(Icons.save_outlined, size: 16),
            label: const Text('Solve + Save'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _reset,
            icon: const Icon(Icons.restart_alt, size: 16),
            label: const Text('Reset Captures'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _load,
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

  Future<void> _load() async {
    await _run(() async {
      final settings = context.read<SettingsProvider>().settings;
      _calibration = await _api.fetchRgbIntrinsicCalibration(settings);
      _intrinsic = await _api.fetchRgbIntrinsic(settings);
    });
  }

  Future<void> _capture() async {
    await _run(() async {
      final settings = context.read<SettingsProvider>().settings;
      _calibration = await _api.captureRgbIntrinsicCalibration(settings);
    });
  }

  Future<void> _solve() async {
    await _run(() async {
      final settings = context.read<SettingsProvider>().settings;
      _calibration = await _api.solveRgbIntrinsicCalibration(settings);
      _intrinsic = await _api.fetchRgbIntrinsic(settings);
    });
  }

  Future<void> _reset() async {
    await _run(() async {
      final settings = context.read<SettingsProvider>().settings;
      _calibration = await _api.resetRgbIntrinsicCalibration(settings);
    });
  }

  Future<void> _setIntrinsicApplied(bool enabled) async {
    final intrinsic = _intrinsic;
    if (intrinsic == null) return;
    await _run(() async {
      final settings = context.read<SettingsProvider>().settings;
      _intrinsic = await _api.setRgbIntrinsic(
        settings,
        intrinsic.copyWith(undistortEnabled: enabled),
      );
      _calibration = await _api.fetchRgbIntrinsicCalibration(settings);
    });
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

class _CalibrationToolbar extends StatelessWidget {
  const _CalibrationToolbar({
    required this.title,
    required this.subtitle,
    required this.receiver,
    required this.streamUrl,
  });

  final String title;
  final String subtitle;
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
          Icon(Icons.grid_on, color: colorScheme.secondary, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 12),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
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

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _MetricBox extends StatelessWidget {
  const _MetricBox({required this.label, required this.value});

  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF303030),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF4A4A4A)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
              const SizedBox(height: 2),
              Text(
                value == null ? '-' : value!.toStringAsFixed(4),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
