import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/remote_pick_api_service.dart';

class CameraDepthCalibrationScreen extends StatefulWidget {
  const CameraDepthCalibrationScreen({super.key});

  @override
  State<CameraDepthCalibrationScreen> createState() =>
      _CameraDepthCalibrationScreenState();
}

class _CameraDepthCalibrationScreenState
    extends State<CameraDepthCalibrationScreen> {
  final RemotePickApiService _api = RemotePickApiService();
  CameraIntrinsics? _intrinsics;
  CameraExtrinsics? _extrinsics;
  String? _error;
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_intrinsics == null && !_loading) {
      unawaited(_load());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Toolbar(onReload: _loading ? null : _load),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_loading) const LinearProgressIndicator(minHeight: 2),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                const SizedBox(height: 16),
              ],
              _IntrinsicsSection(intrinsics: _intrinsics),
              const SizedBox(height: 20),
              _ExtrinsicsSection(extrinsics: _extrinsics),
            ],
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
      final intrinsics = await _api.fetchCameraIntrinsics(settings);
      final extrinsics = await _api.fetchCameraExtrinsics(settings);
      if (!mounted) return;
      setState(() {
        _intrinsics = intrinsics;
        _extrinsics = extrinsics;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.onReload});

  final VoidCallback? onReload;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          const Icon(Icons.threed_rotation, size: 18),
          const SizedBox(width: 10),
          const Text(
            'Camera Geometry',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Reload',
            onPressed: onReload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

class _IntrinsicsSection extends StatelessWidget {
  const _IntrinsicsSection({required this.intrinsics});

  final CameraIntrinsics? intrinsics;

  @override
  Widget build(BuildContext context) {
    final value = intrinsics;
    return _Section(
      title: 'Intrinsics',
      children: [
        _Field(label: 'camera_path', value: value?.cameraPath ?? '-'),
        _Field(
          label: 'resolution',
          value: '${value?.width ?? 0} x ${value?.height ?? 0}',
        ),
        _Field(label: 'fx', value: _fixed(value?.fx)),
        _Field(label: 'fy', value: _fixed(value?.fy)),
        _Field(label: 'cx', value: _fixed(value?.cx)),
        _Field(label: 'cy', value: _fixed(value?.cy)),
        _Field(label: 'distortion', value: value?.distortionModel ?? '-'),
      ],
    );
  }
}

class _ExtrinsicsSection extends StatelessWidget {
  const _ExtrinsicsSection({required this.extrinsics});

  final CameraExtrinsics? extrinsics;

  @override
  Widget build(BuildContext context) {
    final value = extrinsics;
    final matrix = value?.robotFromCameraOptical ?? const [];
    return _Section(
      title: 'Extrinsics',
      children: [
        _Field(label: 'camera_path', value: value?.cameraPath ?? '-'),
        _Field(label: 'robot_base_path', value: value?.robotBasePath ?? '-'),
        const SizedBox(height: 14),
        const _SubTitle('Camera position from robot base'),
        _CameraPosition(matrix: matrix),
        const SizedBox(height: 14),
        const _SubTitle('Rotation 3x3'),
        _Matrix(matrix: _rotationRows(matrix), labels: const ['x', 'y', 'z']),
        const SizedBox(height: 14),
        const _SubTitle('Transform 4x4'),
        _Matrix(
          matrix: matrix,
          labels: const ['row 0', 'row 1', 'row 2', 'row 3'],
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF3A3A3A)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SubTitle extends StatelessWidget {
  const _SubTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class _CameraPosition extends StatelessWidget {
  const _CameraPosition({required this.matrix});

  final List<List<double>> matrix;

  @override
  Widget build(BuildContext context) {
    if (matrix.length < 3 || matrix.any((row) => row.length < 4)) {
      return const Text('camera position: -');
    }
    final position = _CameraPositionValues(
      x: matrix[0][3],
      y: matrix[1][3],
      z: matrix[2][3],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          '카메라는 로봇 base 기준으로 x=${_meter(position.x)}, '
          'y=${_meter(position.y)}, z=${_meter(position.z)} 위치에 있음',
        ),
        const SizedBox(height: 10),
        _AxisOffset(axis: 'X', value: position.x),
        _AxisOffset(axis: 'Y', value: position.y),
        _AxisOffset(axis: 'Z', value: position.z),
      ],
    );
  }
}

class _CameraPositionValues {
  const _CameraPositionValues({
    required this.x,
    required this.y,
    required this.z,
  });

  final double x;
  final double y;
  final double z;
}

class _AxisOffset extends StatelessWidget {
  const _AxisOffset({required this.axis, required this.value});

  final String axis;
  final double value;

  @override
  Widget build(BuildContext context) {
    final direction = value < 0 ? '-$axis' : '+$axis';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: SelectableText(
              '$axis = ${_meter(value)}',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              '로봇 기준 $direction 방향으로 ${_centimeter(value)}',
            ),
          ),
        ],
      ),
    );
  }
}

String _meter(double value) => '${value.toStringAsFixed(5)} m';

String _centimeter(double value) =>
    '${(value.abs() * 100).toStringAsFixed(1)} cm';

class _Matrix extends StatelessWidget {
  const _Matrix({required this.matrix, required this.labels});

  final List<List<double>> matrix;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    if (matrix.isEmpty) {
      return const Text('matrix: -');
    }
    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: {
        0: const FixedColumnWidth(58),
        for (var i = 0; i < matrix.first.length; i++)
          i + 1: const FlexColumnWidth(),
      },
      children: [
        for (var rowIndex = 0; rowIndex < matrix.length; rowIndex++)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                child: Text(
                  rowIndex < labels.length ? labels[rowIndex] : 'row $rowIndex',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
              for (final value in matrix[rowIndex])
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 6,
                  ),
                  child: SelectableText(
                    value.toStringAsFixed(6),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

List<List<double>> _rotationRows(List<List<double>> matrix) {
  if (matrix.length < 3 || matrix.any((row) => row.length < 3)) {
    return const [];
  }
  return [
    [matrix[0][0], matrix[0][1], matrix[0][2]],
    [matrix[1][0], matrix[1][1], matrix[1][2]],
    [matrix[2][0], matrix[2][1], matrix[2][2]],
  ];
}

String _fixed(double? value) => value == null ? '-' : value.toStringAsFixed(6);
