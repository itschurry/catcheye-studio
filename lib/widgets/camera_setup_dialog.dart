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
      hardware = json['hardware_id'] as int?,
      enabled = json['undistortion_enabled'] as bool,
      calibrationName = json['calibration_name'] as String,
      error = json['last_error'] as String? {
    if (serial.isEmpty ||
        (hardware != null && (hardware! < 0 || hardware! > 3))) {
      throw const FormatException('카메라 식별 정보가 올바르지 않습니다');
    }
  }
  final String serial, ip, model, calibrationName;
  final String? error;
  final bool discovered;
  int? hardware;
  bool enabled;
  CalibrationUpload? upload;
}

class CameraSetupDialog extends StatefulWidget {
  const CameraSetupDialog({
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
  State<CameraSetupDialog> createState() => _CameraSetupDialogState();
}

class _CameraSetupDialogState extends State<CameraSetupDialog> {
  late final _api =
      widget.api ??
      RemoteProductionApiService(timeout: const Duration(seconds: 90));
  List<_Camera> _cameras = [];
  List<Map<String, dynamic>> _hardware = [];
  int? _revision;
  bool _busy = false, _dirty = false, _mustReload = false, _saved = false;
  String? _error;
  static const _labels = ['볼트 머리', '스터드', '너트', '너트 홀'];
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
    if (revision is! int ||
        revision < 0 ||
        rows is! List ||
        roles is! List ||
        roles.length != 4) {
      throw const FormatException('카메라 설정 API 응답이 올바르지 않습니다');
    }
    final cameras = rows.map((row) => _Camera(productionObject(row))).toList();
    final hardware = roles.map(productionObject).toList();
    for (var i = 0; i < 4; i++) {
      if (hardware[i]['hardware_id'] != i ||
          hardware[i]['camera_id'] is! String) {
        throw const FormatException('하드웨어 카메라 매핑이 올바르지 않습니다');
      }
    }
    if (cameras.map((c) => c.serial).toSet().length != cameras.length) {
      throw const FormatException('카메라 시리얼이 중복되었습니다');
    }
    setState(() {
      _revision = revision;
      _cameras = cameras;
      _hardware = hardware;
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
    final assigned = <int>{};
    for (final camera in _cameras) {
      if (camera.hardware != null && !assigned.add(camera.hardware!)) {
        setState(() => _error = '하드웨어마다 카메라 한 대만 배정할 수 있습니다.');
        return;
      }
      if (camera.hardware != null && !camera.discovered) {
        setState(
          () => _error =
              '${camera.serial}: 검색되지 않은 카메라입니다. 연결을 확인하거나 미사용으로 지정하세요.',
        );
        return;
      }
      if (camera.enabled &&
          camera.upload == null &&
          camera.calibrationName.isEmpty) {
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

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('카메라 · 하드웨어 · 왜곡 보정'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Inspect 장비에서 검색한 카메라입니다. 시리얼로 식별하며 담당 하드웨어와 보정 파일을 지정합니다.',
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
                const Text('검색되거나 저장된 카메라가 없습니다. 연결을 확인하고 다시 검색하세요.'),
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
                        Text(
                          '${camera.ip} · ${camera.model}\n${camera.discovered ? '검색됨' : '검색 안 됨 · 연결 확인 필요'}',
                        ),
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
                            for (var i = 0; i < 4; i++)
                              DropdownMenuItem(
                                value: i,
                                child: Text('${_labels[i]} ($i)'),
                              ),
                          ],
                          onChanged: _busy || _mustReload
                              ? null
                              : (value) => setState(() {
                                  camera.hardware = value == -1 ? null : value;
                                  _dirty = true;
                                }),
                        ),
                        if (camera.hardware != null)
                          Text(
                            '촬영 ${_hardware[camera.hardware!]['width']}×${_hardware[camera.hardware!]['height']} · ROI 시작 ${_hardware[camera.hardware!]['offset_x']}, ${_hardware[camera.hardware!]['offset_y']}',
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
                              (camera.calibrationName.isEmpty
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
                            TextButton.icon(
                              onPressed:
                                  _busy ||
                                      _dirty ||
                                      _mustReload ||
                                      camera.hardware == null ||
                                      !camera.discovered
                                  ? null
                                  : () => widget.onPreview(
                                      _hardware[camera.hardware!]['camera_id']
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
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, _saved),
          child: const Text('닫기'),
        ),
        TextButton(
          onPressed: _busy ? null : _load,
          child: const Text('서버 설정 다시 불러오기 · 재검색'),
        ),
        FilledButton(
          onPressed: _busy || _revision == null || _mustReload ? null : _save,
          child: const Text('저장 및 적용'),
        ),
      ],
    ),
  );
}
