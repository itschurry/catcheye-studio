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
  final signals = <String, Map<String, String>>{
    'rx': {
      'hardware_0': '볼트 머리 선택 (0)',
      'hardware_1': '스터드 선택 (1)',
      'hardware_2': '너트 선택 (2)',
      'hardware_3': '너트 홀 선택 (3)',
    },
    'tx': {'ok': 'OK', 'ng': 'NG', 'heartbeat': 'Heartbeat'},
  };
  final _selectionNumber = TextEditingController();
  final _productCount = TextEditingController();
  final _pointCount = TextEditingController();
  final _advanced = ExpansibleController();
  int _requiredProducts = 0;
  int _requiredPoints = 0;
  bool _generated = false;
  String _selectionKind = 'product';

  int? get _products => int.tryParse(_productCount.text.trim());
  int? get _points => int.tryParse(_pointCount.text.trim());
  bool get _countsValid =>
      _products != null &&
      _products! >= _requiredProducts &&
      _products! >= 1 &&
      _products! <= 255 &&
      _points != null &&
      _points! >= _requiredPoints &&
      _points! >= 1 &&
      _points! <= 200;

  bool get _missingRecipeSignals => [
    for (var i = 1; i <= _requiredProducts; i++) 'product_$i',
    for (var i = 1; i <= _requiredPoints; i++) 'point_$i',
  ].any((name) => int.tryParse(_fields['rx.$name']?.text ?? '') == null);

  void _generateSignals() {
    if (!widget.canSave()) {
      setState(() => _error = '촬영이 끝나고 PLC 연결을 해제한 뒤 신호표를 생성하세요.');
      return;
    }
    if (!_countsValid) return;
    final rx = <String, String>{
      for (var i = 1; i <= _products!; i++) 'product_$i': '제품 $i 선택',
      for (var i = 1; i <= _points!; i++) 'point_$i': '포인트 $i 선택',
      'hardware_0': '볼트 머리 선택 (0)',
      'hardware_1': '스터드 선택 (1)',
      'hardware_2': '너트 선택 (2)',
      'hardware_3': '너트 홀 선택 (3)',
    };
    final removed = <TextEditingController>[];
    for (final name in signals['rx']!.keys) {
      if (!rx.containsKey(name)) removed.add(_fields.remove('rx.$name')!);
    }
    signals['rx'] = rx;
    for (final direction in signals.entries) {
      var index = 0;
      for (final name in direction.value.keys) {
        (_fields['${direction.key}.$name'] ??= TextEditingController()).text =
            '${index++}';
      }
      _fields['${direction.key}_words']!.text = '$index';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in removed) {
        controller.dispose();
      }
    });
    setState(() {
      _generated = true;
      _error = null;
    });
  }

  String _selectionLabel(String name) {
    final match = RegExp(
      r'^(product|point)_([1-9][0-9]{0,2})$',
    ).firstMatch(name);
    if (match == null ||
        int.parse(match[2]!) > (match[1] == 'product' ? 255 : 200)) {
      throw FormatException('지원하지 않는 선택 신호: $name');
    }
    return '${match[1] == 'product' ? '제품' : '포인트'} ${match[2]} 선택';
  }

  void _addSelection() {
    final number = int.tryParse(_selectionNumber.text.trim());
    if (number == null ||
        number < 1 ||
        number > (_selectionKind == 'product' ? 255 : 200)) {
      setState(() => _error = '제품은 1~255, 포인트는 1~200 번호를 입력하세요.');
      return;
    }
    final name = '${_selectionKind}_$number';
    if (signals['rx']!.containsKey(name)) {
      setState(() => _error = '이미 등록된 선택 신호입니다: $name');
      return;
    }
    setState(() {
      signals['rx']![name] = _selectionLabel(name);
      // New locations must be assigned explicitly; existing offsets never shift.
      _fields['rx.$name'] = TextEditingController();
      _generated = false;
      _error = null;
    });
  }

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
    _selectionNumber.dispose();
    _productCount.dispose();
    _pointCount.dispose();
    _advanced.dispose();
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
      final catalog = await widget.api.recipes(widget.settings);
      var requiredPoints = 0;
      for (final product in catalog.products) {
        for (final recipe in [product.draft, product.active]) {
          if (recipe != null && recipe.points.length > requiredPoints) {
            requiredPoints = recipe.points.length;
          }
        }
      }
      final revision = response['revision'];
      final config = productionObject(response['config']);
      if (revision is! int ||
          revision < 0 ||
          config['enabled'] is! bool ||
          !{'little', 'big'}.contains(config['byte_order'])) {
        throw const FormatException('지원하지 않는 PLC 설정 응답입니다');
      }
      final rx = productionObject(config['rx']);
      final tx = productionObject(config['tx']);
      if (![for (var i = 0; i < 4; i++) 'hardware_$i'].every(rx.containsKey) ||
          tx.length != 3 ||
          !signals['tx']!.keys.every(tx.containsKey)) {
        throw const FormatException('PLC 신호 매핑이 올바르지 않습니다');
      }
      final rxLabels = <String, String>{
        'hardware_0': '볼트 머리 선택 (0)',
        'hardware_1': '스터드 선택 (1)',
        'hardware_2': '너트 선택 (2)',
        'hardware_3': '너트 홀 선택 (3)',
      };
      for (final name in rx.keys) {
        if (!rxLabels.containsKey(name)) rxLabels[name] = _selectionLabel(name);
      }
      if (!mounted) return;
      for (final field in _fields.values) {
        field.dispose();
      }
      _fields.clear();
      signals['rx'] = rxLabels;
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
        _requiredProducts = catalog.products.length;
        _requiredPoints = requiredPoints;
        // Preserve reserved capacity in the suggestion; never renumber on load.
        var products = _requiredProducts;
        var points = _requiredPoints;
        for (final name in rx.keys) {
          final id = int.parse(name.split('_').last);
          if (name.startsWith('product_') && id > products) products = id;
          if (name.startsWith('point_') && id > points) points = id;
        }
        _productCount.text = '$products';
        _pointCount.text = points == 0 ? '' : '$points';
        _generated = false;
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
      onChanged: (_) => setState(() => _generated = false),
    ),
  );

  Future<void> _save() async {
    if (!widget.canSave()) {
      setState(
        () => _error = '촬영이 끝나고 PLC 연결을 해제한 뒤 다시 시도하세요. 장비 연결 상태도 확인하세요.',
      );
      return;
    }
    if (!_form.currentState!.validate()) {
      _advanced.expand();
      return;
    }
    if (_enabled &&
        (!signals['rx']!.keys.any((name) => name.startsWith('product_')) ||
            !signals['rx']!.keys.any((name) => name.startsWith('point_')))) {
      setState(() => _error = '제품 선택 신호와 포인트 선택 신호를 각각 하나 이상 추가하세요.');
      return;
    }
    int? number(String key) => int.tryParse(_fields[key]!.text.trim());
    final config = <String, dynamic>{
      'enabled': _enabled,
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

  Widget _signalGenerator() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('신호표 자동 생성', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text('저장된 레시피 기준: 제품 $_requiredProducts종 · 최대 $_requiredPoints포인트'),
      const Text(
        '제품마다 포인트 수가 달라도 포인트 신호는 공통으로 사용합니다. 초안·적용 레시피의 최대 개수 이상으로 여유를 둘 수 있습니다.',
      ),
      if (_missingRecipeSignals)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('레시피에 필요한 선택 신호 위치가 부족합니다. 신호표를 생성하거나 고급 설정에서 추가하세요.'),
        ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final item in [
            (
              _productCount,
              '제품 수',
              'auto-product-count',
              '$_requiredProducts~255',
            ),
            (
              _pointCount,
              '최대 촬영 포인트 수',
              'auto-point-count',
              '${_requiredPoints == 0 ? 1 : _requiredPoints}~200',
            ),
          ])
            SizedBox(
              width: 220,
              child: TextField(
                key: ValueKey(item.$3),
                controller: item.$1,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: item.$2,
                  helperText: '${item.$4}개',
                ),
                onChanged: (_) => setState(() => _generated = false),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      const Text('하드웨어 4종: 볼트 머리(0) · 스터드(1) · 너트(2) · 너트 홀(3)'),
      const SizedBox(height: 12),
      if (_countsValid) ...[
        const Text('생성할 신호표 미리보기 · 위치는 0부터 시작'),
        const SizedBox(height: 8),
        Table(
          columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(3)},
          children: [
            for (final row in [
              ('신호', '배정 위치'),
              ('제품 1~$_products', '0~${_products! - 1}'),
              ('포인트 1~$_points', '$_products~${_products! + _points! - 1}'),
              (
                '하드웨어 0~3',
                '${_products! + _points!}~${_products! + _points! + 3}',
              ),
              ('결과 출력', 'OK=0 · NG=1 · Heartbeat=2'),
            ])
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(row.$1),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(row.$2),
                  ),
                ],
              ),
          ],
        ),
        Text('수신 ${_products! + _points! + 4}워드 · 송신 3워드 (1워드 = 2바이트)'),
      ] else
        const Text('레시피에 필요한 개수 이상의 정수를 입력하세요. 제품은 최대 255종, 포인트는 1~200개입니다.'),
      const SizedBox(height: 12),
      const Text(
        '개수 입력만으로 기존 신호표가 바뀌지 않습니다. 생성하면 모든 수신·송신 위치와 워드 수를 위 표로 교체합니다. PLC 쪽 신호표도 함께 맞추세요.',
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        key: const ValueKey('generate-signal-map'),
        onPressed: _busy || !_countsValid ? null : _generateSignals,
        icon: const Icon(Icons.auto_fix_high),
        label: const Text('신호표 생성 · 편집에 반영'),
      ),
      if (_generated)
        const Text('신호표를 편집에 반영했습니다. 아래 저장 및 적용을 눌러 Inspect에 저장하세요.'),
      Text(
        '현재 편집값: 수신 ${_fields['rx_words']!.text.isEmpty ? '미설정' : _fields['rx_words']!.text}워드 · 송신 ${_fields['tx_words']!.text.isEmpty ? '미설정' : _fields['tx_words']!.text}워드',
      ),
      const SizedBox(height: 12),
    ],
  );

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
                  _signalGenerator(),
                  ExpansionTile(
                    controller: _advanced,
                    maintainState: true,
                    tilePadding: EdgeInsets.zero,
                    title: const Text('고급 설정 · 프레임과 신호 매핑'),
                    children: [
                      const Text(
                        'PLC 프로그램과 신호표를 동일하게 설정하세요. 신호 위치는 0부터 시작하며 신호 하나는 2바이트의 0/1입니다. 제품·포인트·하드웨어가 각각 하나씩 ON이 되면 1회 촬영합니다. 별도 트리거는 없습니다. 제품 5는 제품 5 선택 신호만 ON입니다. 다음 촬영 전에는 한 종류의 선택을 모두 OFF로 내린 프레임을 보내야 합니다. 예: 하드웨어 전체 OFF → 원하는 하드웨어 하나 ON.',
                      ),
                      const SizedBox(height: 12),
                      _numberField(
                        'rx_words',
                        '수신 워드 수 (PLC → Inspect)',
                        6,
                        512,
                      ),
                      _numberField(
                        'tx_words',
                        '송신 워드 수 (Inspect → PLC)',
                        3,
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
                          Row(
                            key: ValueKey('${direction.key}.${signal.key}'),
                            children: [
                              Expanded(
                                child: _numberField(
                                  '${direction.key}.${signal.key}',
                                  '${signal.value} (${direction.key}.${signal.key})',
                                  0,
                                  511,
                                ),
                              ),
                              if (direction.key == 'rx' &&
                                  !signal.key.startsWith('hardware_'))
                                IconButton(
                                  key: ValueKey('remove-${signal.key}'),
                                  tooltip: '선택 신호 삭제',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: _busy
                                      ? null
                                      : () => setState(() {
                                          signals['rx']!.remove(signal.key);
                                          _generated = false;
                                          // Controllers are disposed after the old field leaves the widget tree.
                                          final controller = _fields.remove(
                                            'rx.${signal.key}',
                                          );
                                          WidgetsBinding.instance
                                              .addPostFrameCallback(
                                                (_) => controller?.dispose(),
                                              );
                                        }),
                                ),
                            ],
                          ),
                        if (direction.key == 'rx') ...[
                          const Text(
                            '제품·포인트를 추가할 때 새 신호에 빈 위치를 지정하세요. 기존 위치는 변경되지 않습니다.',
                          ),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              SizedBox(
                                width: 130,
                                child: DropdownButtonFormField<String>(
                                  key: const ValueKey('selection-kind'),
                                  initialValue: _selectionKind,
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'product',
                                      child: Text('제품'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'point',
                                      child: Text('포인트'),
                                    ),
                                  ],
                                  onChanged: _busy
                                      ? null
                                      : (value) => setState(
                                          () => _selectionKind = value!,
                                        ),
                                ),
                              ),
                              SizedBox(
                                width: 130,
                                child: TextField(
                                  key: const ValueKey('selection-number'),
                                  controller: _selectionNumber,
                                  enabled: !_busy,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: '선택 번호',
                                  ),
                                ),
                              ),
                              OutlinedButton(
                                onPressed: _busy ? null : _addSelection,
                                child: const Text('선택 신호 추가'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
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
