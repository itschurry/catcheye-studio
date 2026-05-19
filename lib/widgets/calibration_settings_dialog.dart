import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/remote_cubeeye_api_service.dart';

Future<void> showRgbCubeEyeRtDialog(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'RGB to CubeEye R/T',
    barrierColor: Colors.black.withValues(alpha: 0.15),
    pageBuilder: (context, _, _) => const _RgbCubeEyeRtDialog(),
  );
}

Future<void> showRgbUndistortionDialog(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'RGB Undistortion',
    barrierColor: Colors.black.withValues(alpha: 0.15),
    pageBuilder: (context, _, _) => const _RgbUndistortionDialog(),
  );
}

Future<void> showRgbIntrinsicCalibrationDialog(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'RGB Intrinsic Calibration',
    barrierColor: Colors.black.withValues(alpha: 0.15),
    pageBuilder: (context, _, _) => const _RgbIntrinsicCalibrationDialog(),
  );
}

class _RgbCubeEyeRtDialog extends StatefulWidget {
  const _RgbCubeEyeRtDialog();

  @override
  State<_RgbCubeEyeRtDialog> createState() => _RgbCubeEyeRtDialogState();
}

class _RgbCubeEyeRtDialogState extends State<_RgbCubeEyeRtDialog> {
  final RemoteCubeEyeApiService _api = RemoteCubeEyeApiService();
  RgbCubeEyeOffset? _offset;
  Offset _position = const Offset(96, 76);
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _loaded = false;

  static const _keys = <String>[
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
    if (_loaded) return;
    _loaded = true;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return _DraggablePanel(
      title: 'RGB to CubeEye R/T',
      icon: Icons.threed_rotation,
      position: _position,
      width: 520,
      height: 430,
      onMove: (delta) => setState(() => _position += delta),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _slider('X m', 'tx_m', -2.0, 2.0, 4000),
                _slider('Y m', 'ty_m', -2.0, 2.0, 4000),
                _slider('Z m', 'tz_m', -2.0, 2.0, 4000),
                _slider('Roll', 'roll_deg', -180.0, 180.0, 3600),
                _slider('Pitch', 'pitch_deg', -180.0, 180.0, 3600),
                _slider('Yaw', 'yaw_deg', -180.0, 180.0, 3600),
                const Spacer(),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _reset,
                      icon: const Icon(Icons.restart_alt, size: 16),
                      label: const Text('Reset'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.check, size: 16),
                      label: Text(_saving ? 'Saving' : 'Apply'),
                    ),
                  ],
                ),
                if (_error != null) _errorText(_error!),
              ],
            ),
    );
  }

  Widget _slider(
    String label,
    String key,
    double min,
    double max,
    int divisions,
  ) {
    final value = (_offset?.values[key] ?? 0.0).clamp(min, max).toDouble();
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: Slider(
            min: min,
            max: max,
            divisions: divisions,
            value: value,
            label: value.toStringAsFixed(3),
            onChanged: _saving || _offset == null
                ? null
                : (next) {
                    final current = _offset!;
                    setState(() {
                      _offset = current.copyWith(
                        values: {...current.values, key: next},
                      );
                    });
                  },
            onChangeEnd: _saving || _offset == null ? null : (_) => _save(),
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = context.read<SettingsProvider>().settings;
      final loaded = await _api.fetchRgbCubeEyeOffset(settings);
      if (!mounted) return;
      setState(() => _offset = loaded);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final current = _offset;
    if (current == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final values = <String, double>{...current.values};
      for (final key in _keys) {
        values[key] = values[key] ?? 0.0;
      }
      final settings = context.read<SettingsProvider>().settings;
      final saved = await _api.setRgbCubeEyeOffset(
        settings,
        current.copyWith(values: values),
      );
      if (mounted) setState(() => _offset = saved);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _reset() {
    final current = _offset;
    if (current == null) return;
    final values = <String, double>{...current.values};
    for (final key in _keys) {
      values[key] = 0.0;
    }
    setState(() => _offset = current.copyWith(values: values));
  }
}

class _RgbUndistortionDialog extends StatefulWidget {
  const _RgbUndistortionDialog();

  @override
  State<_RgbUndistortionDialog> createState() => _RgbUndistortionDialogState();
}

class _RgbUndistortionDialogState extends State<_RgbUndistortionDialog> {
  final RemoteCubeEyeApiService _api = RemoteCubeEyeApiService();
  final Map<String, TextEditingController> _controllers = {};
  RgbCubeEyeOffset? _offset;
  Offset _position = const Offset(128, 96);
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _loaded = false;

  static const _keys = <String>[
    'rgb_width',
    'rgb_height',
    'rgb_fx',
    'rgb_fy',
    'rgb_cx',
    'rgb_cy',
    'rgb_dist_k1',
    'rgb_dist_k2',
    'rgb_dist_p1',
    'rgb_dist_p2',
    'rgb_dist_k3',
  ];

  static const _defaults = <String, double>{
    'rgb_width': 2304.0,
    'rgb_height': 1296.0,
    'rgb_fx': 1220.0,
    'rgb_fy': 1220.0,
    'rgb_cx': 1152.0,
    'rgb_cy': 648.0,
    'rgb_dist_k1': -0.28,
    'rgb_dist_k2': 0.08,
    'rgb_dist_p1': 0.0,
    'rgb_dist_p2': 0.0,
    'rgb_dist_k3': -0.01,
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _load();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DraggablePanel(
      title: 'RGB Undistortion',
      icon: Icons.photo_camera_back_outlined,
      position: _position,
      width: 540,
      height: 500,
      onMove: (delta) => setState(() => _position += delta),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable RGB undistortion'),
                    value: _offset?.rgbUndistortEnabled ?? false,
                    onChanged: _saving || _offset == null
                        ? null
                        : (value) async {
                            setState(() {
                              _offset = _offset!.copyWith(
                                rgbUndistortEnabled: value,
                              );
                            });
                            await _save();
                          },
                  ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final key in _keys)
                        SizedBox(width: 156, child: _numberField(key)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _reset,
                        icon: const Icon(Icons.restart_alt, size: 16),
                        label: const Text('Reset'),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.check, size: 16),
                        label: Text(_saving ? 'Saving' : 'Apply'),
                      ),
                    ],
                  ),
                  if (_error != null) _errorText(_error!),
                ],
              ),
            ),
    );
  }

  Widget _numberField(String key) {
    return TextField(
      controller: _controller(key),
      enabled: !_saving,
      keyboardType: const TextInputType.numberWithOptions(
        signed: true,
        decimal: true,
      ),
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        labelText: key,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
      ),
      onSubmitted: (_) => _save(),
    );
  }

  TextEditingController _controller(String key) {
    return _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: _value(key).toString()),
    );
  }

  double _value(String key) => _offset?.values[key] ?? _defaults[key] ?? 0.0;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = context.read<SettingsProvider>().settings;
      final loaded = await _api.fetchRgbCubeEyeOffset(settings);
      if (!mounted) return;
      setState(() {
        _offset = loaded.copyWith(values: {..._defaults, ...loaded.values});
        _syncControllers();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final current = _offset;
    if (current == null) return;
    final values = <String, double>{...current.values};
    for (final key in _keys) {
      final parsed = double.tryParse(_controller(key).text.trim());
      if (parsed == null) {
        setState(() => _error = 'Invalid number: $key');
        return;
      }
      values[key] = parsed;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final settings = context.read<SettingsProvider>().settings;
      final saved = await _api.setRgbCubeEyeOffset(
        settings,
        current.copyWith(values: values),
      );
      if (!mounted) return;
      setState(() {
        _offset = saved.copyWith(values: {..._defaults, ...saved.values});
        _syncControllers();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _reset() {
    final current = _offset;
    if (current == null) return;
    setState(() {
      _offset = current.copyWith(values: {...current.values, ..._defaults});
      _syncControllers();
    });
  }

  void _syncControllers() {
    for (final key in _keys) {
      _controller(key).text = _value(key).toString();
    }
  }
}

class _RgbIntrinsicCalibrationDialog extends StatefulWidget {
  const _RgbIntrinsicCalibrationDialog();

  @override
  State<_RgbIntrinsicCalibrationDialog> createState() =>
      _RgbIntrinsicCalibrationDialogState();
}

class _RgbIntrinsicCalibrationDialogState
    extends State<_RgbIntrinsicCalibrationDialog> {
  final RemoteCubeEyeApiService _api = RemoteCubeEyeApiService();
  RgbIntrinsicCalibration? _calibration;
  Offset _position = const Offset(160, 116);
  String? _error;
  bool _loading = true;
  bool _busy = false;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final calibration = _calibration;
    return _DraggablePanel(
      title: 'RGB Intrinsic Calibration',
      icon: Icons.grid_on,
      position: _position,
      width: 520,
      height: 420,
      onMove: (delta) => setState(() => _position += delta),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _metricRow('Board', 'A4 9x6 / 20 mm'),
                _metricRow(
                  'Captures',
                  (calibration?.captureCount ?? 0).toString(),
                ),
                _metricRow(
                  'RMS',
                  calibration?.rmsError?.toStringAsFixed(4) ?? '-',
                ),
                const Divider(height: 24),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _metricBox('fx', calibration?.values['rgb_fx']),
                    _metricBox('fy', calibration?.values['rgb_fy']),
                    _metricBox('cx', calibration?.values['rgb_cx']),
                    _metricBox('cy', calibration?.values['rgb_cy']),
                    _metricBox('k1', calibration?.values['rgb_dist_k1']),
                    _metricBox('k2', calibration?.values['rgb_dist_k2']),
                    _metricBox('p1', calibration?.values['rgb_dist_p1']),
                    _metricBox('p2', calibration?.values['rgb_dist_p2']),
                    _metricBox('k3', calibration?.values['rgb_dist_k3']),
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _reset,
                      icon: const Icon(Icons.restart_alt, size: 16),
                      label: const Text('Reset'),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _capture,
                      icon: const Icon(Icons.add_a_photo_outlined, size: 16),
                      label: const Text('Capture'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _busy ? null : _solve,
                      icon: const Icon(Icons.save_outlined, size: 16),
                      label: Text(_busy ? 'Working' : 'Solve + Save'),
                    ),
                  ],
                ),
                if (_error != null) _errorText(_error!),
              ],
            ),
    );
  }

  Widget _metricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _metricBox(String label, double? value) {
    return SizedBox(
      width: 92,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF102225),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF30474B)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 10)),
              const SizedBox(height: 2),
              Text(
                value == null ? '-' : value.toStringAsFixed(4),
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = context.read<SettingsProvider>().settings;
      final loaded = await _api.fetchRgbIntrinsicCalibration(settings);
      if (mounted) setState(() => _calibration = loaded);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
    });
  }

  Future<void> _reset() async {
    await _run(() async {
      final settings = context.read<SettingsProvider>().settings;
      _calibration = await _api.resetRgbIntrinsicCalibration(settings);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _DraggablePanel extends StatelessWidget {
  const _DraggablePanel({
    required this.title,
    required this.icon,
    required this.position,
    required this.width,
    required this.height,
    required this.onMove,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Offset position;
  final double width;
  final double height;
  final ValueChanged<Offset> onMove;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;
    final left = position.dx
        .clamp(16.0, math.max(16.0, media.width - width))
        .toDouble();
    final top = position.dy
        .clamp(16.0, math.max(16.0, media.height - height))
        .toDouble();
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            child: SizedBox(
              width: width,
              height: math.min(height, math.max(320.0, media.height - 80.0)),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1416),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF5BD9E8)),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 22,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (details) => onMove(details.delta),
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: const BoxDecoration(
                          color: Color(0xFF102225),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(8),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              icon,
                              size: 18,
                              color: const Color(0xFF5BD9E8),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close',
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                        child: child,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _errorText(String message) {
  return Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Text(
      message,
      style: const TextStyle(fontSize: 11, color: Colors.redAccent),
    ),
  );
}
