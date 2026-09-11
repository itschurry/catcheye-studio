import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../services/remote_production_api_service.dart';

/// PLC configuration stays in Inspect; the dialog never connects automatically.
class PlcSettingsDialog extends StatefulWidget {
  const PlcSettingsDialog({
    super.key,
    required this.api,
    required this.settings,
    required this.canSave,
  });
  final RemoteProductionApiService api;
  final AppSettings settings;
  final bool Function() canSave;

  @override
  State<PlcSettingsDialog> createState() => _PlcSettingsDialogState();
}

class _PlcSettingsDialogState extends State<PlcSettingsDialog> {
  static const signals = {
    'rx': {
      'request_sequence': '요청 순번',
      'command': '검사 명령',
      'product_id': '제품 번호',
      'result_ack': '결과 수신 확인',
      'heartbeat': '하트비트',
    },
    'tx': {
      'accepted_sequence': '접수한 요청 순번',
      'rejected_sequence': '거부한 요청 순번',
      'result_sequence': '결과 순번',
      'result_status': '판정 결과',
      'step': '현재 촬영 포인트',
      'total': '전체 촬영 포인트',
      'state': '검사 상태',
      'heartbeat': '하트비트',
      'error_code': '오류 코드',
    },
  };
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  int? _revision;
  bool _enabled = false;
  String _order = 'little';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await widget.api.request(
        widget.settings,
        'GET',
        'plc/config',
      );
      final revision = response['revision'];
      final config = productionObject(response['config']);
      if (revision is! int ||
          revision < 0 ||
          config['enabled'] is! bool ||
          config['protocol'] != 'inspect_words_v1' ||
          !{'little', 'big'}.contains(config['byte_order'])) {
        throw const FormatException('지원하지 않는 PLC 설정 응답입니다');
      }
      if (!mounted) return;
      for (final field in _fields.values) {
        field.dispose();
      }
      _fields.clear();
      for (final key in [
        'host',
        'port',
        'rx_words',
        'tx_words',
        'exchange_interval_ms',
        'timeout_ms',
      ]) {
        _fields[key] = TextEditingController(
          text: config[key]?.toString() ?? '',
        );
      }
      for (final direction in signals.entries) {
        final map = productionObject(config[direction.key]);
        for (final name in direction.value.keys) {
          _fields['${direction.key}.$name'] = TextEditingController(
            text: map[name]?.toString() ?? '',
          );
        }
      }
      setState(() {
        _revision = revision;
        _enabled = config['enabled'] as bool;
        _order = config['byte_order'] as String;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _number(String? text, int low, int high, {bool required = false}) {
    if ((text ?? '').trim().isEmpty && !required && !_enabled) return null;
    final value = int.tryParse((text ?? '').trim());
    return value == null || value < low || value > high
        ? '$low~$high 범위의 정수를 입력하세요'
        : null;
  }

  Widget _numberField(
    String key,
    String label,
    int low,
    int high, {
    bool required = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: _fields[key],
      enabled: !_busy,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      validator: (text) => _number(text, low, high, required: required),
    ),
  );

  Future<void> _save() async {
    if (!widget.canSave()) {
      setState(
        () => _error = '검사를 종료하고 PLC 연결을 해제한 뒤 다시 시도하세요. 장비 연결 상태도 확인하세요.',
      );
      return;
    }
    if (!_form.currentState!.validate()) return;
    int? number(String key) => int.tryParse(_fields[key]!.text.trim());
    final config = <String, dynamic>{
      'enabled': _enabled,
      'protocol': 'inspect_words_v1',
      'host': _fields['host']!.text.trim(),
      'port': number('port'),
      'rx_words': number('rx_words'),
      'tx_words': number('tx_words'),
      'byte_order': _order,
      'exchange_interval_ms': number('exchange_interval_ms'),
      'timeout_ms': number('timeout_ms'),
      for (final direction in signals.entries)
        direction.key: {
          for (final name in direction.value.keys)
            name: number('${direction.key}.$name'),
        },
    };
    for (final direction in signals.keys) {
      final words = number('${direction}_words');
      final used = <int>{};
      for (final name in signals[direction]!.keys) {
        final word = number('$direction.$name');
        if (word != null &&
            ((words != null && word >= words) || !used.add(word))) {
          setState(
            () => _error = '$direction 신호 위치가 중복되었거나 워드 수를 벗어났습니다: $name',
          );
          return;
        }
      }
    }
    if (number('timeout_ms')! < 3 * number('exchange_interval_ms')!) {
      setState(() => _error = '통신 제한 시간은 송신 주기의 3배 이상이어야 합니다.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.request(widget.settings, 'PUT', 'plc/config', {
        'base_revision': _revision,
        'config': config,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('PLC 통신 설정'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                if (_revision != null) ...[
                  const Text(
                    '설정은 Inspect에 저장됩니다. 저장 후 재시작 없이 적용되며, 연결은 별도로 실행합니다.',
                  ),
                  SwitchListTile(
                    title: const Text('PLC 사용'),
                    subtitle: const Text(
                      '끄면 미완성 설정을 저장할 수 있습니다. 켜려면 모든 신호 위치가 필요합니다.',
                    ),
                    contentPadding: EdgeInsets.zero,
                    value: _enabled,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _enabled = value),
                  ),
                  TextFormField(
                    controller: _fields['host'],
                    enabled: !_busy,
                    decoration: const InputDecoration(labelText: 'PLC IPv4 주소'),
                    validator: (text) {
                      final host = (text ?? '').trim();
                      if (host.isEmpty && !_enabled) return null;
                      final parts = host.split('.');
                      if (parts.length != 4 ||
                          parts.any(
                            (part) =>
                                !RegExp(
                                  r'^(0|[1-9][0-9]{0,2})$',
                                ).hasMatch(part) ||
                                int.parse(part) > 255,
                          )) {
                        return '올바른 IPv4 주소를 입력하세요';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _numberField('port', 'PLC 포트', 1, 65535),
                  ExpansionTile(
                    initiallyExpanded: true,
                    tilePadding: EdgeInsets.zero,
                    title: const Text('고급 설정 · 프레임과 신호 매핑'),
                    children: [
                      const Text(
                        'inspect_words_v1 · PLC 프로그램과 동일하게 설정하세요. 워드 위치는 0부터 시작하며 1워드는 2바이트입니다.',
                      ),
                      const SizedBox(height: 12),
                      _numberField(
                        'rx_words',
                        '수신 워드 수 (PLC → Inspect)',
                        5,
                        512,
                      ),
                      _numberField(
                        'tx_words',
                        '송신 워드 수 (Inspect → PLC)',
                        9,
                        512,
                      ),
                      DropdownButtonFormField<String>(
                        key: ValueKey('byte-order-$_revision-$_order'),
                        initialValue: _order,
                        decoration: const InputDecoration(labelText: '바이트 순서'),
                        items: const [
                          DropdownMenuItem(
                            value: 'little',
                            child: Text('Little endian'),
                          ),
                          DropdownMenuItem(
                            value: 'big',
                            child: Text('Big endian'),
                          ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _order = value!),
                      ),
                      const SizedBox(height: 12),
                      _numberField(
                        'exchange_interval_ms',
                        '송신 주기 (ms)',
                        20,
                        1000,
                        required: true,
                      ),
                      _numberField(
                        'timeout_ms',
                        '통신 제한 시간 (ms)',
                        500,
                        60000,
                        required: true,
                      ),
                      for (final direction in signals.entries) ...[
                        Text(direction.key == 'rx' ? '수신 신호 위치' : '송신 신호 위치'),
                        const SizedBox(height: 12),
                        for (final signal in direction.value.entries)
                          _numberField(
                            '${direction.key}.${signal.key}',
                            '${signal.value} (${direction.key}.${signal.key})',
                            0,
                            511,
                          ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
        TextButton(
          onPressed: _busy ? null : _load,
          child: const Text('서버 설정 다시 불러오기'),
        ),
        FilledButton(
          onPressed: _busy || _revision == null ? null : _save,
          child: const Text('저장 및 적용'),
        ),
      ],
    ),
  );
}
