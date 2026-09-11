import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/app_settings.dart';
import '../services/remote_production_api_service.dart';

class CalibrationUpload {
  const CalibrationUpload(this.name, this.content);
  final String name, content;
}

class _Camera {
  _Camera(Map<String, dynamic> json)
    : serial = json['serial'] as String,
      ip = json['ip'] as String,
      model = json['model'] as String,
      discovered = json['discovered'] as bool,
      settings = Map.of(productionObject(json['settings'])),
      hardware = json['hardware_id'] as int?,
      enabled = json['undistortion_enabled'] as bool,
      calibrationName = json['calibration_name'] as String,
      error = json['last_error'] as String? {
    if (serial.isEmpty || (hardware != null && hardware! < 0)) {
      throw const FormatException('카메라 식별 정보가 올바르지 않습니다');
    }
  }
  final String serial, ip, model, calibrationName;
  final String? error;
  final bool discovered;
  int? hardware;
  bool enabled;
  final Map<String, dynamic> settings;
  bool clearCalibration = false;
  CalibrationUpload? upload;
}

class CameraSetupPanel extends StatefulWidget {
  const CameraSetupPanel({
    super.key,
    required this.settings,
    required this.canSave,
    required this.onPreview,
    this.api,
    this.pickCalibration,
  });
  final AppSettings settings;
  final bool Function() canSave;
  final Future<void> Function(String cameraId) onPreview;
  final RemoteProductionApiService? api;
  final Future<CalibrationUpload?> Function()? pickCalibration;
  @override
  State<CameraSetupPanel> createState() => _CameraSetupPanelState();
}

class _CameraSetupPanelState extends State<CameraSetupPanel> {
  late final _api =
      widget.api ??
      RemoteProductionApiService(timeout: const Duration(minutes: 5));
  List<_Camera> _cameras = [];
  List<Map<String, dynamic>> _hardware = [];
  List<Map<String, dynamic>> _fields = [];
  int _editorGeneration = 0;
  int? _revision;
  bool _busy = false, _dirty = false, _mustReload = false, _saved = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (widget.api == null) _api.close();
    super.dispose();
  }

  void _accept(Map<String, dynamic> response) {
    final revision = response['revision'];
    final rows = response['cameras'];
    final roles = response['hardware'];
    final descriptors = response['settings_fields'];
    if (revision is! int ||
        revision < 0 ||
        rows is! List ||
        roles is! List ||
        roles.isEmpty ||
        descriptors is! List ||
        descriptors.isEmpty) {
      throw const FormatException(
        '카메라 설정 API 응답이 올바르지 않습니다. Inspect를 함께 업데이트하세요.',
      );
    }
    final cameras = rows
        .map(productionObject)
        .where((row) => row['discovered'] == true)
        .map(_Camera.new)
        .toList();
    final hardware = roles.map(productionObject).toList();
    final ids = <int>{};
    for (final role in hardware) {
      final id = role['hardware_id'];
      if (id is! int ||
          id < 0 ||
          !ids.add(id) ||
          role['camera_id'] is! String ||
          role['label'] is! String) {
        throw const FormatException('하드웨어 카메라 매핑이 올바르지 않습니다');
      }
    }
    final fields = descriptors.map(productionObject).toList();
    final keys = <String>{};
    for (final field in fields) {
      final key = field['key'];
      if (key is! String ||
          !keys.add(key) ||
          field['label'] is! String ||
          field['nullable'] is! bool ||
          !['string', 'integer', 'number', 'boolean'].contains(field['type']) ||
          (field.containsKey('choices') &&
              (field['choices'] is! List ||
                  (field['choices'] as List).any((v) => v is! String)))) {
        throw const FormatException(
          '카메라 옵션 목록이 올바르지 않습니다. Inspect를 함께 업데이트하세요.',
        );
      }
    }
    for (final camera in cameras) {
      if ((camera.hardware != null && !ids.contains(camera.hardware)) ||
          camera.settings.keys.toSet().difference(keys).isNotEmpty ||
          keys.difference(camera.settings.keys.toSet()).isNotEmpty) {
        throw const FormatException('카메라 설정과 옵션 목록이 일치하지 않습니다');
      }
    }
    if (cameras.map((c) => c.serial).toSet().length != cameras.length) {
      throw const FormatException('카메라 시리얼이 중복되었습니다');
    }
    setState(() {
      _revision = revision;
      _cameras = cameras;
      _hardware = hardware;
      _fields = fields;
      _editorGeneration++;
      _dirty = false;
      _mustReload = false;
    });
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await _api.request(
        widget.settings,
        'GET',
        'camera-setup',
      );
      if (mounted) _accept(response);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _mustReload = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick(_Camera camera) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      CalibrationUpload? upload;
      if (widget.pickCalibration != null) {
        upload = await widget.pickCalibration!();
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['yaml', 'yml'],
          withData: true,
        );
        if (result == null) return;
        final file = result.files.single;
        if (file.size > 65536 || file.bytes == null) {
          throw const FormatException('64 KiB 이하의 보정 YAML 파일을 읽을 수 있어야 합니다');
        }
        upload = CalibrationUpload(file.name, utf8.decode(file.bytes!));
      }
      if (upload == null || !mounted) return;
      if ((!upload.name.endsWith('.yaml') && !upload.name.endsWith('.yml')) ||
          upload.content.isEmpty ||
          utf8.encode(upload.content).length > 65536) {
        throw const FormatException('64 KiB 이하의 보정 YAML 파일을 선택하세요');
      }
      setState(() {
        camera.upload = upload;
        camera.clearCalibration = false;
        _dirty = true;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!widget.canSave()) {
      setState(() => _error = '촬영 완료·PLC 연결 해제 후 적용하세요.');
      return;
    }
    final values = <String, Map<String, dynamic>>{};
    try {
      for (final camera in _cameras) {
        values[camera.serial] = _settingsValues(camera);
      }
    } catch (error) {
      setState(() => _error = '$error');
      return;
    }
    final assigned = <int>{};
    for (final camera in _cameras) {
      if (camera.hardware != null && !assigned.add(camera.hardware!)) {
        setState(() => _error = '하드웨어마다 카메라 한 대만 배정할 수 있습니다.');
        return;
      }
      if (camera.enabled &&
          camera.upload == null &&
          (camera.clearCalibration || camera.calibrationName.isEmpty)) {
        setState(() => _error = '${camera.serial}: 왜곡 보정을 사용하려면 파일을 선택하세요.');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _api.request(
        widget.settings,
        'PUT',
        'camera-setup',
        {
          'base_revision': _revision,
          'cameras': [
            for (final camera in _cameras)
              {
                'serial': camera.serial,
                'hardware_id': camera.hardware,
                'undistortion_enabled': camera.enabled,
                'settings': values[camera.serial],
                'clear_calibration': camera.clearCalibration,
                if (camera.upload != null)
                  'calibration': {
                    'file_name': camera.upload!.name,
                    'content': camera.upload!.content,
                  },
              },
          ],
        },
      );
      if (mounted) {
        _accept(result);
        setState(() => _saved = true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error\n서버 설정을 다시 불러와 적용 상태를 확인하세요.';
          _mustReload = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> _settingsValues(_Camera camera) {
    final result = <String, dynamic>{};
    for (final field in _fields) {
      final key = field['key'] as String;
      final raw = camera.settings[key];
      final text = raw?.toString().trim() ?? '';
      dynamic value = raw;
      if (text.isEmpty && field['nullable'] == true) {
        value = null;
      } else {
        switch (field['type']) {
          case 'integer':
            value = int.tryParse(text);
          case 'number':
            value = double.tryParse(text);
          case 'string':
            value = text;
          case 'boolean':
            value = raw is bool ? raw : null;
        }
        if (value == null ||
            (value is num && !value.isFinite) ||
            (field['min'] is num && value is num && value < field['min']) ||
            (field['max'] is num && value is num && value > field['max']) ||
            (field['choices'] is List &&
                !(field['choices'] as List).contains(value))) {
          throw FormatException(
            '${camera.serial}: ${field['label']} 값을 확인하세요.',
          );
        }
      }
      result[key] = value;
    }
    return result;
  }

  Widget _settingEditor(_Camera camera, Map<String, dynamic> field) {
    final key = field['key'] as String;
    final value = camera.settings[key];
    final nullable = field['nullable'] == true;
    final decoration = InputDecoration(
      labelText: '${field['label']} ($key)',
      helperText: nullable ? '비움: 장치 현재값 사용' : null,
    );
    void change(dynamic value) => setState(() {
      camera.settings[key] = value;
      _dirty = true;
    });
    if (field['type'] == 'boolean' || field['choices'] is List) {
      final choices = field['type'] == 'boolean'
          ? <dynamic>[true, false]
          : field['choices'] as List;
      return DropdownButtonFormField<String>(
        key: ValueKey('option-${camera.serial}-$key-$_editorGeneration'),
        initialValue: value?.toString() ?? '',
        isExpanded: true,
        decoration: decoration,
        items: [
          if (nullable)
            const DropdownMenuItem(value: '', child: Text('장치 현재값')),
          for (final option in choices)
            DropdownMenuItem(
              value: option.toString(),
              child: Text(
                option is bool ? (option ? '사용' : '사용 안 함') : option.toString(),
              ),
            ),
        ],
        onChanged: _busy || _mustReload
            ? null
            : (selected) => change(
                selected == ''
                    ? null
                    : field['type'] == 'boolean'
                    ? selected == 'true'
                    : selected,
              ),
      );
    }
    return TextFormField(
      key: ValueKey('option-${camera.serial}-$key-$_editorGeneration'),
      initialValue: value?.toString() ?? '',
      decoration: decoration,
      enabled: !_busy && !_mustReload,
      keyboardType: ['integer', 'number'].contains(field['type'])
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      onChanged: change,
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '현재 연결된 카메라만 표시합니다. 새 카메라는 설정 후 저장하면 등록됩니다. 연결이 빠져도 저장한 설정은 유지됩니다.',
              ),
              const SizedBox(height: 8),
              const Text(
                '파일은 Inspect에 업로드됩니다. 보정 파일은 같은 촬영 해상도·센서 ROI로 만들어야 합니다. 하드웨어를 바꿔도 보정 파일은 해당 시리얼에 유지됩니다.',
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: SelectableText(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_saved && !_dirty)
                const Text('저장·적용 완료. 영상 확인으로 현재 출력 영상을 확인하세요.'),
              if (_revision != null && _cameras.isEmpty)
                const Text('연결된 카메라가 없습니다. 연결을 확인하고 다시 검색하세요.'),
              for (final camera in _cameras)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '시리얼 ${camera.serial}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text('${camera.ip} · ${camera.model}'),
                        if (camera.error?.isNotEmpty == true)
                          Text(camera.error!),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          key: ValueKey(
                            'hardware-${camera.serial}-${camera.hardware}',
                          ),
                          initialValue: camera.hardware ?? -1,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: '담당 하드웨어',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: -1,
                              child: Text('미사용'),
                            ),
                            for (final role in _hardware)
                              DropdownMenuItem(
                                value: role['hardware_id'] as int,
                                child: Text(
                                  '${role['label']} (${role['hardware_id']})',
                                ),
                              ),
                          ],
                          onChanged: _busy || _mustReload
                              ? null
                              : (value) => setState(() {
                                  camera.hardware = value == -1 ? null : value;
                                  _dirty = true;
                                }),
                        ),
                        ExpansionTile(
                          key: ValueKey(
                            'settings-${camera.serial}-$_editorGeneration',
                          ),
                          title: const Text('촬영 설정'),
                          subtitle: const Text(
                            '해상도 · ROI · 노출 · 게인 · 프레임 속도 · 트리거',
                          ),
                          tilePadding: EdgeInsets.zero,
                          maintainState: true,
                          children: [
                            const Text(
                              '선택 항목을 비우면 장치의 현재값을 사용합니다. 지원 범위는 저장 시 카메라에서 검증합니다. 시리얼·현재 IP는 검색한 장치의 식별값입니다.',
                            ),
                            LayoutBuilder(
                              builder: (context, constraints) => Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  for (final field in _fields)
                                    SizedBox(
                                      width: constraints.maxWidth >= 640
                                          ? (constraints.maxWidth - 12) / 2
                                          : constraints.maxWidth,
                                      child: _settingEditor(camera, field),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('왜곡 보정 사용'),
                          value: camera.enabled,
                          onChanged: _busy || _mustReload
                              ? null
                              : (value) => setState(() {
                                  camera.enabled = value;
                                  _dirty = true;
                                }),
                        ),
                        Text(
                          camera.upload?.name ??
                              (camera.clearCalibration ||
                                      camera.calibrationName.isEmpty
                                  ? '보정 파일 미선택'
                                  : camera.calibrationName),
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              key: ValueKey('file-${camera.serial}'),
                              onPressed: _busy || _mustReload
                                  ? null
                                  : () => _pick(camera),
                              icon: const Icon(Icons.upload_file),
                              label: const Text('보정 파일 선택'),
                            ),
                            TextButton(
                              onPressed:
                                  _busy ||
                                      _mustReload ||
                                      (camera.upload == null &&
                                          (camera.clearCalibration ||
                                              camera.calibrationName.isEmpty))
                                  ? null
                                  : () => setState(() {
                                      camera.upload = null;
                                      camera.clearCalibration = true;
                                      camera.enabled = false;
                                      _dirty = true;
                                    }),
                              child: const Text('보정 파일 해제'),
                            ),
                            TextButton.icon(
                              onPressed:
                                  _busy ||
                                      _dirty ||
                                      _mustReload ||
                                      camera.hardware == null ||
                                      !camera.discovered
                                  ? null
                                  : () => widget.onPreview(
                                      _hardware.singleWhere(
                                            (role) =>
                                                role['hardware_id'] ==
                                                camera.hardware,
                                          )['camera_id']
                                          as String,
                                    ),
                              icon: const Icon(Icons.videocam_outlined),
                              label: const Text('영상 확인'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              const Text(
                '저장 시 카메라 연결과 프레임을 확인합니다. 촬영이 끝나고 PLC 연결을 해제한 상태에서 적용하세요. 미배정 하드웨어의 촬영 요청은 오류로 처리됩니다.',
              ),
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: _busy ? null : _load,
              child: const Text('서버 설정 다시 불러오기 · 재검색'),
            ),
            FilledButton(
              onPressed: _busy || _revision == null || _mustReload
                  ? null
                  : _save,
              child: const Text('저장 및 적용'),
            ),
          ],
        ),
      ),
    ],
  );
}
