import 'dart:async';

import 'package:flutter/material.dart';
import '../widgets/zoomable_viewport.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/frame_receiver_service.dart';
import '../services/remote_cubeeye_api_service.dart';
import '../widgets/live_viewer.dart';

class CameraPropertiesScreen extends StatefulWidget {
  const CameraPropertiesScreen({super.key});

  @override
  State<CameraPropertiesScreen> createState() => _CameraPropertiesScreenState();
}

class _CameraPropertiesScreenState extends State<CameraPropertiesScreen> {
  final FrameReceiverService _receiver = FrameReceiverService();
  final RemoteCubeEyeApiService _api = RemoteCubeEyeApiService();
  Map<String, Object> _values = const {};
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _started = false;

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
    _api.close();
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
              _CameraPropertiesToolbar(
                loading: _loading,
                saving: _saving,
                receiver: receiver,
                streamUrl: settings.streamUri.toString(),
                onReload: _load,
              ),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _buildPreview(receiver, camera)),
                    SizedBox(width: 420, child: _buildPanel()),
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
          : ZoomableViewport(
              key: ValueKey(camera.key),
              child: Image.memory(
                camera.jpegBytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
              ),
            ),
    );
  }

  Widget _buildPanel() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF1F1F1F),
        border: Border(left: BorderSide(color: Color(0xFF4A4A4A))),
      ),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _SectionTitle('노출'),
                const SizedBox(height: 8),
                _control(_property('ae-enable')),
                _control(_property('ae-metering-mode')),
                _control(_property('ae-flicker-period')),
                _control(_property('exposure-time-mode')),
                _control(_property('exposure-time')),
                _control(_property('exposure-value')),
                const SizedBox(height: 18),
                const _SectionTitle('게인 / 화이트밸런스'),
                const SizedBox(height: 8),
                _control(_property('analogue-gain-mode')),
                _control(_property('analogue-gain')),
                _control(_property('awb-enable')),
                _control(_property('awb-mode')),
                const SizedBox(height: 18),
                const _SectionTitle('초점'),
                const SizedBox(height: 8),
                _control(_property('af-mode')),
                _control(_property('lens-position')),
                const SizedBox(height: 18),
                const _SectionTitle('영상 조정'),
                const SizedBox(height: 8),
                _control(_property('brightness')),
                _control(_property('contrast')),
                _control(_property('saturation')),
                _control(_property('sharpness')),
                _control(_property('gamma')),
                if (_error != null) ...[
                  const SizedBox(height: 14),
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
    );
  }

  _CameraPropertySpec _property(String key) {
    return _properties.firstWhere((property) => property.key == key);
  }

  Widget _control(_CameraPropertySpec spec) {
    if (!_values.containsKey(spec.key)) {
      return const SizedBox.shrink();
    }
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
              DropdownMenuItem(
                value: option,
                child: Text(_propertyOptionLabel(option)),
              ),
          ],
          onChanged: _saving || _enumValue(spec) == null
              ? null
              : (value) {
                  if (value != null) unawaited(_set(spec, value));
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

class _CameraPropertiesToolbar extends StatelessWidget {
  const _CameraPropertiesToolbar({
    required this.loading,
    required this.saving,
    required this.receiver,
    required this.streamUrl,
    required this.onReload,
  });

  final bool loading;
  final bool saving;
  final FrameReceiverService receiver;
  final String streamUrl;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          Icon(
            Icons.settings_input_component_outlined,
            size: 20,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(width: 10),
          const Text(
            '카메라 설정',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 12),
          Text(
            receiver.connected
                ? '연결됨'
                : receiver.connecting
                ? '연결 중'
                : '연결 끊김',
            style: TextStyle(
              fontSize: 12,
              color: receiver.connected
                  ? Colors.green
                  : const Color(0xFFA3A3A3),
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: receiver.connecting
                ? null
                : () {
                    if (receiver.connected) {
                      unawaited(receiver.disconnect());
                    } else {
                      unawaited(receiver.connect(streamUrl));
                    }
                  },
            icon: Icon(
              receiver.connected ? Icons.power_off : Icons.power,
              size: 16,
            ),
            label: Text(receiver.connected ? '연결 해제' : '연결'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: loading || saving ? null : onReload,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('다시 불러오기'),
          ),
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
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
    );
  }
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
  _CameraPropertySpec.bool('ae-enable', '자동 노출'),
  _CameraPropertySpec.enumValue('ae-metering-mode', '노출 측광 방식', [
    'centre-weighted',
    'spot',
    'matrix',
  ]),
  _CameraPropertySpec.integer(
    'ae-flicker-period',
    '깜빡임 주기 (µs)',
    0,
    20000,
    200,
  ),
  _CameraPropertySpec.enumValue('exposure-time-mode', '노출 모드', [
    'auto',
    'manual',
  ]),
  _CameraPropertySpec.integer('exposure-time', '노출 시간 (µs)', 0, 100000, 1000),
  _CameraPropertySpec.number('exposure-value', '노출 보정값', -4, 4, 160),
  _CameraPropertySpec.enumValue('analogue-gain-mode', '게인 모드', [
    'auto',
    'manual',
  ]),
  _CameraPropertySpec.number('analogue-gain', '아날로그 게인', 1, 16, 150),
  _CameraPropertySpec.bool('awb-enable', '자동 화이트밸런스'),
  _CameraPropertySpec.enumValue('awb-mode', '화이트밸런스 모드', [
    'auto',
    'incandescent',
    'tungsten',
    'fluorescent',
    'indoor',
    'daylight',
    'cloudy',
  ]),
  _CameraPropertySpec.enumValue('af-mode', '자동 초점 모드', [
    'manual',
    'auto',
    'continuous',
  ]),
  _CameraPropertySpec.number('lens-position', '렌즈 위치', 0, 12, 120),
  _CameraPropertySpec.number('brightness', '밝기', -1, 1, 200),
  _CameraPropertySpec.number('contrast', '대비', 0, 4, 200),
  _CameraPropertySpec.number('saturation', '채도', 0, 4, 200),
  _CameraPropertySpec.number('sharpness', '선명도', 0, 8, 160),
  _CameraPropertySpec.number('gamma', '감마', 0.1, 4, 195),
];

String _propertyOptionLabel(String value) => switch (value) {
  'centre-weighted' => '중앙 중점',
  'spot' => '스폿',
  'matrix' => '다분할',
  'auto' => '자동',
  'manual' => '수동',
  'incandescent' => '백열등',
  'tungsten' => '텅스텐등',
  'fluorescent' => '형광등',
  'indoor' => '실내',
  'daylight' => '주광',
  'cloudy' => '흐림',
  'continuous' => '연속',
  _ => value,
};
