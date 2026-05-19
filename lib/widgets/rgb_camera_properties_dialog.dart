import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/remote_cubeeye_api_service.dart';

Future<void> showRgbCameraPropertiesDialog(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'RGB Camera Parameters',
    barrierColor: Colors.black.withValues(alpha: 0.15),
    pageBuilder: (context, _, _) => const _RgbCameraPropertiesDialog(),
  );
}

class _CameraPropertySpec {
  const _CameraPropertySpec.bool(this.key, this.label)
    : type = _CameraPropertyType.boolean,
      min = 0,
      max = 1,
      divisions = 1,
      options = const [];

  const _CameraPropertySpec.number(
    this.key,
    this.label,
    this.min,
    this.max,
    this.divisions,
  ) : type = _CameraPropertyType.number,
      options = const [];

  const _CameraPropertySpec.integer(
    this.key,
    this.label,
    this.min,
    this.max,
    this.divisions,
  ) : type = _CameraPropertyType.integer,
      options = const [];

  const _CameraPropertySpec.enumValue(this.key, this.label, this.options)
    : type = _CameraPropertyType.enumValue,
      min = 0,
      max = 1,
      divisions = 1;

  final String key;
  final String label;
  final _CameraPropertyType type;
  final double min;
  final double max;
  final int divisions;
  final List<String> options;
}

enum _CameraPropertyType { boolean, number, integer, enumValue }

const _properties = <_CameraPropertySpec>[
  _CameraPropertySpec.bool('ae-enable', 'AE'),
  _CameraPropertySpec.enumValue('ae-metering-mode', 'AE metering', [
    'centre-weighted',
    'spot',
    'matrix',
  ]),
  _CameraPropertySpec.integer('ae-flicker-period', 'Flicker us', 0, 20000, 200),
  _CameraPropertySpec.enumValue('exposure-time-mode', 'Exposure mode', [
    'auto',
    'manual',
  ]),
  _CameraPropertySpec.integer('exposure-time', 'Exposure us', 0, 100000, 1000),
  _CameraPropertySpec.number('exposure-value', 'EV', -4, 4, 160),
  _CameraPropertySpec.enumValue('analogue-gain-mode', 'Gain mode', [
    'auto',
    'manual',
  ]),
  _CameraPropertySpec.number('analogue-gain', 'Analogue gain', 1, 16, 150),
  _CameraPropertySpec.bool('awb-enable', 'AWB'),
  _CameraPropertySpec.enumValue('awb-mode', 'AWB mode', [
    'auto',
    'incandescent',
    'tungsten',
    'fluorescent',
    'indoor',
    'daylight',
    'cloudy',
  ]),
  _CameraPropertySpec.enumValue('af-mode', 'AF mode', [
    'manual',
    'auto',
    'continuous',
  ]),
  _CameraPropertySpec.number('lens-position', 'Lens', 0, 12, 120),
  _CameraPropertySpec.number('brightness', 'Brightness', -1, 1, 200),
  _CameraPropertySpec.number('contrast', 'Contrast', 0, 4, 200),
  _CameraPropertySpec.number('saturation', 'Saturation', 0, 4, 200),
  _CameraPropertySpec.number('sharpness', 'Sharpness', 0, 8, 160),
  _CameraPropertySpec.number('gamma', 'Gamma', 0.1, 4, 195),
];

class _RgbCameraPropertiesDialog extends StatefulWidget {
  const _RgbCameraPropertiesDialog();

  @override
  State<_RgbCameraPropertiesDialog> createState() =>
      _RgbCameraPropertiesDialogState();
}

class _RgbCameraPropertiesDialogState
    extends State<_RgbCameraPropertiesDialog> {
  final RemoteCubeEyeApiService _api = RemoteCubeEyeApiService();
  Offset _position = const Offset(160, 96);
  Map<String, Object> _values = const {};
  String? _error;
  bool _loading = true;
  bool _saving = false;
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
    final media = MediaQuery.of(context).size;
    const width = 520.0;
    final height = math.min(700.0, math.max(360.0, media.height - 90.0));
    final left = _position.dx
        .clamp(16.0, math.max(16.0, media.width - width))
        .toDouble();
    final top = _position.dy
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
              height: height,
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
                      onPanUpdate: (details) =>
                          setState(() => _position += details.delta),
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
                            const Icon(
                              Icons.settings_input_component_outlined,
                              size: 18,
                              color: Color(0xFF5BD9E8),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'RGB Camera Parameters',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Reload',
                              icon: const Icon(Icons.refresh, size: 18),
                              onPressed: _saving ? null : _load,
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
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                12,
                                16,
                                16,
                              ),
                              children: [
                                for (final spec in _properties)
                                  if (_values.containsKey(spec.key))
                                    _control(spec),
                                if (_error != null) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    _error!,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                ],
                              ],
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

  Widget _control(_CameraPropertySpec spec) {
    return switch (spec.type) {
      _CameraPropertyType.boolean => SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(spec.label),
        value: _values[spec.key] == true,
        onChanged: _saving ? null : (value) => _set(spec, value),
      ),
      _CameraPropertyType.enumValue => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: DropdownButtonFormField<String>(
          initialValue: _enumValue(spec),
          isExpanded: true,
          decoration: InputDecoration(labelText: spec.label, isDense: true),
          items: [
            for (final option in spec.options)
              DropdownMenuItem(value: option, child: Text(option)),
          ],
          onChanged: _saving || _enumValue(spec) == null
              ? null
              : (value) {
                  if (value != null) _set(spec, value);
                },
        ),
      ),
      _CameraPropertyType.integer ||
      _CameraPropertyType.number => _slider(spec),
    };
  }

  Widget _slider(_CameraPropertySpec spec) {
    final raw = _values[spec.key];
    final value = (raw is num ? raw.toDouble() : spec.min)
        .clamp(spec.min, spec.max)
        .toDouble();
    return Row(
      children: [
        SizedBox(
          width: 116,
          child: Text(spec.label, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: Slider(
            min: spec.min,
            max: spec.max,
            divisions: spec.divisions,
            value: value,
            label: spec.type == _CameraPropertyType.integer
                ? value.round().toString()
                : value.toStringAsFixed(2),
            onChanged: _saving
                ? null
                : (next) {
                    setState(() {
                      _values = {
                        ..._values,
                        spec.key: spec.type == _CameraPropertyType.integer
                            ? next.round()
                            : next,
                      };
                    });
                  },
            onChangeEnd: _saving
                ? null
                : (next) => _set(
                    spec,
                    spec.type == _CameraPropertyType.integer
                        ? next.round()
                        : next,
                  ),
          ),
        ),
        SizedBox(
          width: 58,
          child: Text(
            spec.type == _CameraPropertyType.integer
                ? value.round().toString()
                : value.toStringAsFixed(2),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  String? _enumValue(_CameraPropertySpec spec) {
    final value = _values[spec.key];
    if (value is! String || !spec.options.contains(value)) return null;
    return value;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = context.read<SettingsProvider>().settings;
      final loaded = await _api.fetchRgbCameraProperties(settings);
      if (mounted) setState(() => _values = loaded.values);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _set(_CameraPropertySpec spec, Object value) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final settings = context.read<SettingsProvider>().settings;
      final loaded = await _api.setRgbCameraProperty(settings, spec.key, value);
      if (mounted) setState(() => _values = loaded.values);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
