import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../providers/settings_provider.dart';
import '../services/frame_receiver_service.dart';
import '../services/remote_capture_api_service.dart';
import '../services/remote_production_api_service.dart';
import '../widgets/station_inspection_image.dart';
import '../widgets/plc_settings_dialog.dart';
import '../widgets/plc_debug_panel.dart';

class ProductionScreen extends StatefulWidget {
  const ProductionScreen({super.key, this.api, this.active = true});
  final RemoteProductionApiService? api;
  final bool active;
  @override
  State<ProductionScreen> createState() => _ProductionScreenState();
}

class _ProductionScreenState extends State<ProductionScreen> {
  late final RemoteProductionApiService _api =
      widget.api ?? RemoteProductionApiService();
  final _captureApi = RemoteCaptureApiService();
  final _name = TextEditingController();
  final _scroll = ScrollController();
  RecipeCatalog? _catalog;
  ProductionStatus? _status;
  List<ProductionCapture> _history = [];
  List<RecipePoint> _points = [];
  int _product = 1;
  int _tab = 0;
  bool _dirty = false;
  bool _busy = false;
  bool _polling = false;
  bool _fresh = false;
  String? _error;
  DateTime? _updatedAt;
  Timer? _timer;
  String? _endpoint;
  int _generation = 0;
  int _statusGeneration = 0;

  AppSettings get _settings => context.read<SettingsProvider>().settings;
  RecipeSlot? get _slot => _catalog?.products[_product - 1];
  ProductionCapture? get _capture => _status?.capture;
  bool get _active => _capture?.active == true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final endpoint = context
        .watch<SettingsProvider>()
        .settings
        .buildApiUri('production')
        .toString();
    if (_endpoint != endpoint) {
      final changed = _endpoint != null;
      _endpoint = endpoint;
      _generation++;
      _catalog = null;
      _status = null;
      _history = [];
      _fresh = false;
      _points = [];
      _name.clear();
      _dirty = false;
      if (changed) _error = '연결 장비가 바뀌어 이전 장비의 편집 내용을 닫았습니다.';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_reload());
      });
      _timer?.cancel();
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(_poll()),
      );
    }
  }

  @override
  void didUpdateWidget(covariant ProductionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      _fresh = false;
      if (widget.active && !_busy) unawaited(_reload());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (widget.api == null) _api.close();
    _captureApi.close();
    _name.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _loadEditor() {
    _name.text = _slot?.draft.name ?? '';
    _points = List.of(_slot?.draft.points ?? []);
    _dirty = false;
  }

  Future<void> _reload() async {
    final generation = _generation;
    final settings = _settings;
    _statusGeneration++;
    setState(() => _busy = true);
    try {
      final catalog = await _api.recipes(settings);
      final status = await _api.status(settings);
      if (!mounted || generation != _generation) return;
      setState(() {
        final conflict =
            _dirty &&
            _slot != null &&
            catalog.products[_product - 1].revision != _slot!.revision;
        if (!_dirty) _catalog = catalog;
        _status = status;
        _fresh = true;
        _updatedAt = DateTime.now();
        if (!_dirty) _loadEditor();
        _error = conflict
            ? '서버 초안이 다른 곳에서 변경되었습니다. 현재 편집의 기준 버전은 유지했습니다. 서버 초안을 다시 불러온 뒤 편집해 주세요.'
            : null;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = '$error';
          _fresh = false;
        });
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _poll() async {
    if (!mounted || !widget.active || _polling || _busy || _catalog == null) {
      return;
    }
    final generation = _generation;
    _polling = true;
    final statusGeneration = _statusGeneration;
    try {
      final status = await _api.status(_settings);
      if (mounted &&
          generation == _generation &&
          statusGeneration == _statusGeneration) {
        setState(() {
          _status = status;
          _fresh = true;
          _updatedAt = DateTime.now();
        });
      }
    } catch (error) {
      if (mounted &&
          generation == _generation &&
          statusGeneration == _statusGeneration) {
        setState(() {
          _fresh = false;
          _error = '상태 갱신 실패: $error';
        });
      }
    } finally {
      _polling = false;
    }
  }

  Future<bool> _discardChanges() async {
    if (!_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('저장하지 않은 변경이 있습니다'),
            content: const Text('변경 내용을 버리고 이동하시겠습니까?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('계속 편집'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('변경 버리기'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _selectProduct(int product) async {
    if (product == _product || !await _discardChanges() || !mounted) return;
    setState(() {
      _product = product;
      _loadEditor();
    });
  }

  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    _statusGeneration++;
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = error is TimeoutException
              ? '응답 시간이 초과되었습니다. 요청은 자동 반복하지 않습니다. 상태를 새로고침해서 접수 여부를 확인해 주세요.'
              : '$error';
          _fresh = false;
        });
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _act(() async {
    final generation = _generation;
    final slot = _slot!;
    final result = await _api.save(
      _settings,
      slot,
      ProductRecipe(_name.text.trim(), List.of(_points)),
    );
    if (!mounted || generation != _generation) return;
    setState(() {
      _catalog = RecipeCatalog([
        for (final p in _catalog!.products)
          if (p.productId == result.productId) result else p,
      ], _catalog!.defaults);
      _loadEditor();
    });
  });
  Future<void> _activate() => _act(() async {
    final generation = _generation;
    final result = await _api.activate(_settings, _slot!);
    if (!mounted || generation != _generation) return;
    setState(() {
      _catalog = RecipeCatalog([
        for (final p in _catalog!.products)
          if (p.productId == result.productId) result else p,
      ], _catalog!.defaults);
    });
  });
  Future<void> _command(
    String action, [
    Map<String, dynamic> values = const {},
  ]) => _act(() async {
    final generation = _generation;
    final response = await _api.command(
      _settings,
      action,
      values: {...values, 'control_epoch': _status!.controlEpoch},
    );
    if (mounted && generation == _generation) {
      setState(() {
        _status = _status!.withCapture(response);
      });
    }
  });
  Future<void> _plcAction(String endpoint, [Map<String, dynamic>? body]) =>
      _act(() async {
        final generation = _generation;
        final settings = _settings;
        await _api.request(settings, 'POST', endpoint, body);
        final status = await _api.status(settings);
        if (mounted && generation == _generation) {
          setState(() {
            _status = status;
            _fresh = true;
            _updatedAt = DateTime.now();
          });
        }
      });

  Future<void> _editPoint([int? index]) async {
    final generation = _generation;
    final point = await showDialog<RecipePoint>(
      context: context,
      builder: (context) => _PointEditor(
        point: index == null ? null : _points[index],
        defaults: _catalog!.defaults,
      ),
    );
    if (!mounted || generation != _generation || point == null) return;
    setState(() {
      if (index == null) {
        _points.add(point);
      } else {
        _points[index] = point;
      }
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !widget.active || (!_dirty && !_busy),
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop || !widget.active || _busy) return;
      if (await _discardChanges() && mounted) {
        setState(() => _dirty = false);
        if (context.mounted) Navigator.pop(context);
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('검사 관리'),
        actions: [
          IconButton(
            tooltip: '서버 상태 새로고침',
            onPressed: _busy ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (index, label) in [
                  '제품 레시피',
                  '생산 검사',
                  'PLC 통신 진단',
                  'PLC 디버그',
                ].indexed)
                  ChoiceChip(
                    label: Text(label),
                    selected: _tab == index,
                    onSelected: (_) => setState(() => _tab = index),
                  ),
                Chip(
                  label: Text(
                    _fresh ? '상태 갱신 ${_time(_updatedAt)}' : '상태 확인 불가',
                  ),
                  avatar: Icon(
                    _fresh ? Icons.check_circle_outline : Icons.error_outline,
                    color: _fresh ? Colors.green : Colors.orange,
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SelectableText(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: _catalog == null
                ? Center(
                    child: Text(
                      _busy
                          ? 'Inspect에서 레시피를 읽는 중…'
                          : '레시피를 불러올 수 없습니다. Inspect API와 연결 설정을 확인해 주세요.',
                    ),
                  )
                : switch (_tab) {
                    0 => _recipes(),
                    1 => _operation(),
                    2 => _diagnostics(),
                    _ => PlcDebugPanel(
                      key: ValueKey('debug-$_endpoint'),
                      catalog: _catalog!,
                      status: _status,
                      fresh: _fresh,
                      busy: _busy,
                      captureApi: _captureApi,
                      onConnect: (simulator) => _plcAction(
                        simulator ? 'plc/simulator/connect' : 'plc/connect',
                      ),
                      onDisconnect: () => _plcAction('plc/disconnect'),
                      onConfigure: () => setState(() => _tab = 2),
                      onCapture: (id, product, point, hardware) =>
                          _plcAction('plc/simulator/capture', {
                            'simulator_id': id,
                            'request_id':
                                RemoteProductionApiService.requestId(),
                            'product_id': product,
                            'point_number': point,
                            'hardware_id': hardware,
                          }),
                    ),
                  },
          ),
        ],
      ),
    ),
  );

  Widget _recipes() => ListView(
    controller: _scroll,
    padding: const EdgeInsets.all(16),
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('add-product'),
            onPressed: _busy || _catalog!.products.length >= 255
                ? null
                : () => _act(() async {
                    final generation = _generation;
                    final slot = await _api.addProduct(
                      _settings,
                      _catalog!.products.length,
                    );
                    if (mounted && generation == _generation) {
                      setState(() {
                        _catalog = RecipeCatalog([
                          ..._catalog!.products,
                          slot,
                        ], _catalog!.defaults);
                      });
                    }
                  }),
            icon: const Icon(Icons.add),
            label: const Text('제품 추가'),
          ),
          for (final slot in _catalog!.products)
            ChoiceChip(
              key: ValueKey('product-${slot.productId}'),
              selected: _product == slot.productId,
              onSelected: _busy ? null : (_) => _selectProduct(slot.productId),
              label: Text(
                '${slot.productId}. ${slot.draft.name.isEmpty ? '이름 미설정' : slot.draft.name}',
              ),
            ),
        ],
      ),
      const SizedBox(height: 20),
      TextField(
        key: const ValueKey('recipe-name'),
        controller: _name,
        enabled: !_busy,
        decoration: const InputDecoration(
          labelText: '제품 이름',
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() => _dirty = true),
      ),
      const SizedBox(height: 12),
      Text(
        '초안 v${_slot!.revision} · 적용 ${_slot!.activeRevision == null ? '안 됨' : 'v${_slot!.activeRevision}'}${_dirty ? ' · 저장하지 않은 변경' : ''}',
      ),
      const SizedBox(height: 8),
      const Text(
        '목록 번호가 PLC에서 지정하는 촬영 포인트 번호입니다. 순서를 바꾸면 번호도 변경됩니다. 기대 개수를 비워 두면 초안으로 저장할 수 있지만 생산 검사에는 적용할 수 없습니다.',
      ),
      const SizedBox(height: 12),
      for (var i = 0; i < _points.length; i++)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${i + 1}. ${_points[i].name.isEmpty ? '포인트 이름 미설정' : _points[i].name}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '${inspectionLabels[_points[i].inspectionId]} · 기대 ${_points[i].expectedCount?.toString() ?? '미정'}개',
                ),
                Wrap(
                  spacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: _busy ? null : () => _editPoint(i),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('편집'),
                    ),
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _points.insert(
                                i + 1,
                                RecipePoint.fromJson(_points[i].toJson()),
                              );
                              _dirty = true;
                            }),
                      icon: const Icon(Icons.copy),
                      label: const Text('복제'),
                    ),
                    IconButton(
                      tooltip: '위로 이동',
                      onPressed: _busy || i == 0
                          ? null
                          : () => setState(() {
                              final point = _points.removeAt(i);
                              _points.insert(i - 1, point);
                              _dirty = true;
                            }),
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    IconButton(
                      tooltip: '아래로 이동',
                      onPressed: _busy || i == _points.length - 1
                          ? null
                          : () => setState(() {
                              final point = _points.removeAt(i);
                              _points.insert(i + 1, point);
                              _dirty = true;
                            }),
                      icon: const Icon(Icons.arrow_downward),
                    ),
                    IconButton(
                      tooltip: '포인트 삭제',
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _points.removeAt(i);
                              _dirty = true;
                            }),
                      icon: const Icon(Icons.delete_outline),
                    ),
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _preview(_points[i].inspectionId),
                      icon: const Icon(Icons.videocam_outlined),
                      label: const Text('카메라 확인'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      if (_points.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('등록된 촬영 포인트가 없습니다. PLC에서 사용할 포인트 번호에 맞춰 추가해 주세요.'),
        ),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('add-point'),
            onPressed: _busy || _points.length >= 200
                ? null
                : () => _editPoint(),
            icon: const Icon(Icons.add),
            label: const Text('촬영 포인트 추가'),
          ),
          FilledButton(
            key: const ValueKey('save-recipe'),
            onPressed: _busy || !_dirty ? null : _save,
            child: const Text('초안 저장'),
          ),
          FilledButton.tonal(
            key: const ValueKey('activate-recipe'),
            onPressed:
                _busy || _dirty || !_fresh || _active || _slot!.revision == 0
                ? null
                : _activate,
            child: const Text('검증 후 적용'),
          ),
        ],
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: _busy
              ? null
              : () async {
                  if (!await _discardChanges() || !mounted) return;
                  setState(() => _dirty = false);
                  await _reload();
                },
          child: const Text('서버 초안 다시 불러오기'),
        ),
      ),
      if (_active)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('제품 검사 중에는 레시피를 적용할 수 없습니다. 초안 편집·저장은 가능합니다.'),
        ),
    ],
  );

  Widget _operation() {
    final capture = _capture;
    final enabled =
        !_busy &&
        _fresh &&
        !_active &&
        {
          PlcConnectionState.disabled,
          PlcConnectionState.disconnected,
        }.contains(_status?.plc?.state);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '제품과 촬영 포인트를 선택하면 실제 카메라로 1회 검사합니다. 수동 검증은 PLC 연결을 해제한 상태에서 사용하세요.',
        ),
        const SizedBox(height: 12),
        for (final slot in _catalog!.products)
          ExpansionTile(
            title: Text('${slot.productId}. ${slot.active?.name ?? '미적용'}'),
            children: [
              for (var i = 0; i < (slot.active?.points.length ?? 0); i++)
                ListTile(
                  title: Text('${i + 1}. ${slot.active!.points[i].name}'),
                  subtitle: Text(
                    '${inspectionLabels[slot.active!.points[i].inspectionId]} · 기대 ${slot.active!.points[i].expectedCount}개',
                  ),
                  trailing: FilledButton(
                    onPressed: enabled
                        ? () => _command('capture', {
                            'product_id': slot.productId,
                            'point_number': i + 1,
                            'hardware_id':
                                inspectionHardwareIds[slot
                                    .active!
                                    .points[i]
                                    .inspectionId],
                          })
                        : null,
                    child: const Text('1회 촬영'),
                  ),
                ),
            ],
          ),
        if (capture != null) ...[
          const Divider(height: 32),
          Text(
            '${capture.recipe.name} · 포인트 ${capture.pointNumber} · ${capture.state.code} · ${capture.status}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          SelectableText(
            '촬영 ${capture.id} · 레시피 v${capture.recipeRevision} · 요청 ${capture.origin}',
          ),
          if (capture.error.isNotEmpty)
            Text(capture.error, style: const TextStyle(color: Colors.orange)),
          for (final result in capture.results)
            ListTile(
              title: Text(_resultSummary(result)),
              trailing: TextButton(
                onPressed: () => _showResult(result),
                child: const Text('이미지·사유'),
              ),
            ),
        ],
        const Divider(height: 32),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: _busy
                ? null
                : () => _act(() async {
                    final generation = _generation;
                    final history = await _api.captures(_settings);
                    if (mounted && generation == _generation) {
                      setState(() => _history = history);
                    }
                  }),
            child: const Text('최근 촬영 이력 100건 조회'),
          ),
        ),
        for (final record in _history)
          ExpansionTile(
            title: Text(
              '${record.productId} · ${record.recipe.name} · 포인트 ${record.pointNumber} · ${record.status}',
            ),
            subtitle: Text(
              '${record.id} · 레시피 v${record.recipeRevision} · ${record.origin == 'plc_simulator' ? 'PLC 시뮬레이터' : record.origin}',
            ),
            children: [
              if (record.error.isNotEmpty) ListTile(title: Text(record.error)),
              for (final result in record.results)
                ListTile(
                  title: Text(_resultSummary(result)),
                  trailing: TextButton(
                    onPressed: () => _showResult(result),
                    child: const Text('이미지·사유'),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  String _resultSummary(ProductionResult result) =>
      '${result.capture.status}${result.reason == null ? '' : ' · ${result.reason}'} · ${result.summaries.map((inspection) => '기대 ${inspection.expectedCount} / 검출 ${inspection.presentCount} · ${inspection.reason}').join(' / ')}';

  void _showResult(ProductionResult record) {
    final result = record.capture;
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: 1100,
          height: 760,
          child: Column(
            children: [
              ListTile(
                title: Text(_resultSummary(record)),
                trailing: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
              Expanded(
                child: result.inspections.isEmpty
                    ? const Center(child: Text('이 결과에는 검사 이미지 정보가 없습니다.'))
                    : StationInspectionImage(
                        result: result,
                        inspection: result.inspections.values.first,
                        api: _captureApi,
                        archived: true,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _diagnostics() {
    final plc = _status?.plc;
    final events = [...?_status?.events, ...?plc?.events]
      ..sort((a, b) => b.atMs.compareTo(a.atMs));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          _fresh ? 'PLC ${plc?.state.code ?? '미설정'}' : 'PLC 상태 확인 불가',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          '주소 ${plc?.host ?? ''}:${plc?.port ?? ''} · 프로토콜 ${plc?.protocol ?? ''}',
        ),
        Text(
          '최근 수신 ${_millis(plc?.lastRxAtMs)} / 송신 ${_millis(plc?.lastTxAtMs)}',
        ),
        const Text('OK/NG는 이번 촬영 결과입니다. PLC의 결과 수신 여부는 별도로 확인하지 않습니다.'),
        if (plc?.productId != null && plc?.pointNumber != null)
          Text(
            '최근 촬영 요청: 제품 ${plc!.productId} · 포인트 ${plc.pointNumber} · 하드웨어 ${plc.hardwareId}',
          ),
        if (plc?.enabled == false)
          const Text('현장 IP·포트·신호표가 미설정이어서 PLC 연결은 비활성 상태입니다.'),
        if ((plc?.error ?? '').isNotEmpty)
          SelectableText(
            plc!.error,
            style: const TextStyle(color: Colors.orange),
          ),
        if ((_status?.error ?? '').isNotEmpty)
          SelectableText('Inspect 오류: ${_status!.error}'),
        const Text('PLC 설정은 촬영이 끝나고 연결을 해제한 상태에서 변경할 수 있습니다.'),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.settings),
              label: const Text('PLC 설정'),
              onPressed: !_busy && _canEditPlc
                  ? () async {
                      final settings = _settings;
                      final endpoint = _endpoint;
                      final saved = await showDialog<bool>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => PlcSettingsDialog(
                          api: _api,
                          settings: settings,
                          canSave: () =>
                              mounted && _endpoint == endpoint && _canEditPlc,
                        ),
                      );
                      if (saved == true && mounted && _endpoint == endpoint) {
                        await _poll();
                      }
                    }
                  : null,
            ),
            OutlinedButton(
              onPressed: !_busy && _fresh && plc?.canConnect == true
                  ? () => _act(() async {
                      await _api.request(_settings, 'POST', 'plc/connect');
                    })
                  : null,
              child: const Text('PLC 연결'),
            ),
            OutlinedButton(
              onPressed: !_busy && _fresh && plc?.canDisconnect == true
                  ? () => _act(() async {
                      await _api.request(_settings, 'POST', 'plc/disconnect');
                    })
                  : null,
              child: const Text('연결 해제'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        for (final direction in ['rx', 'tx'])
          ExpansionTile(
            title: Text(
              direction == 'rx' ? 'PLC → Inspect 신호' : 'Inspect → PLC 신호',
            ),
            children: [
              for (final entry
                  in (plc?.mapping(direction) ?? const <String, int>{}).entries)
                ListTile(
                  dense: true,
                  title: Text(entry.key),
                  subtitle: Text('워드 ${entry.value}'),
                  trailing: Text(_word(plc, direction, entry.value)),
                ),
            ],
          ),
        const Divider(height: 24),
        const Text(
          '선택 신호 수신 → 제품·포인트·하드웨어 확인 → 촬영·판정 → OK/NG 송신',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const Text('다음 이동과 재촬영 여부는 PLC에서 결정합니다.'),
        const SizedBox(height: 8),
        for (final event in events.take(200))
          ListTile(
            dense: true,
            title: Text('${_millis(event.atMs)}  ${event.name}'),
            subtitle: SelectableText(jsonEncode(event.detail)),
          ),
      ],
    );
  }

  String _word(PlcStatus? plc, String direction, int word) {
    final value = _fresh && plc?.state == PlcConnectionState.connected
        ? plc?.word(direction, word)
        : null;
    return value == null
        ? '확인 안 됨'
        : value == 1
        ? 'ON (1)'
        : value == 0
        ? 'OFF (0)'
        : '잘못된 값 ($value)';
  }

  bool get _canEditPlc =>
      _fresh &&
      !_active &&
      {
        PlcConnectionState.disabled,
        PlcConnectionState.disconnected,
      }.contains(_status?.plc?.state);

  Future<void> _preview(String inspectionId) async {
    final defaults = productionObject(_catalog!.defaults[inspectionId]);
    final camera = defaults['camera_id'] as String;
    final settings = _settings;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _RecipePreview(settings: settings, camera: camera),
    );
  }
}

String _time(DateTime? value) =>
    value == null ? '없음' : value.toLocal().toIso8601String().substring(11, 19);
String _millis(Object? value) => value is int
    ? DateTime.fromMillisecondsSinceEpoch(value).toLocal().toIso8601String()
    : '없음';

class _PointEditor extends StatefulWidget {
  const _PointEditor({this.point, required this.defaults});
  final RecipePoint? point;
  final Map<String, dynamic> defaults;
  @override
  State<_PointEditor> createState() => _PointEditorState();
}

class _PointEditorState extends State<_PointEditor> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _count = TextEditingController();
  final _candidate = TextEditingController();
  final _present = TextEditingController();
  final _geometry = <String, TextEditingController>{};
  late String _inspection;
  static const geometryLabels = {
    'min_circularity': '최소 원형도',
    'min_axis_ratio': '최소 축 비율',
    'max_relative_eccentricity': '최대 상대 편심',
    'min_arc_detection_rate': '최소 원호 검출률',
  };
  @override
  void initState() {
    super.initState();
    _inspection = widget.point?.inspectionId ?? widget.defaults.keys.first;
    _name.text = widget.point?.name ?? '';
    _count.text = widget.point?.expectedCount?.toString() ?? '';
    for (final key in geometryLabels.keys) {
      _geometry[key] = TextEditingController();
    }
    _criteria(widget.point);
  }

  void _criteria(RecipePoint? point) {
    final defaults = productionObject(widget.defaults[_inspection]);
    _candidate.text =
        '${point?.candidateConfidence ?? defaults['candidate_confidence']}';
    _present.text =
        '${point?.presentConfidence ?? defaults['present_confidence']}';
    final geometry = point?.geometry ?? defaults['geometry'];
    for (final key in _geometry.keys) {
      _geometry[key]!.text = geometry?[key]?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _count,
      _candidate,
      _present,
      ..._geometry.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _ratio(String? text, {bool optional = false}) {
    if (optional && (text == null || text.trim().isEmpty)) return null;
    final value = double.tryParse(text ?? '');
    return value == null || !value.isFinite || value < 0 || value > 1
        ? '0~1 사이 숫자를 입력해 주세요'
        : null;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.point == null ? '촬영 포인트 추가' : '촬영 포인트 편집'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: '포인트 이름'),
                maxLength: 160,
              ),
              DropdownButtonFormField<String>(
                initialValue: _inspection,
                decoration: const InputDecoration(labelText: '검사 항목'),
                items: [
                  for (final id in widget.defaults.keys)
                    DropdownMenuItem(
                      value: id,
                      child: Text(inspectionLabels[id]!),
                    ),
                ],
                onChanged: (id) {
                  if (id != null) {
                    setState(() {
                      _inspection = id;
                      _criteria(null);
                    });
                  }
                },
              ),
              TextFormField(
                key: const ValueKey('expected-count'),
                controller: _count,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '기대 개수',
                  helperText: '미정이면 비워 두고 초안으로 저장해 주세요',
                ),
                validator: (text) {
                  if (text == null || text.trim().isEmpty) return null;
                  final n = int.tryParse(text);
                  return n == null || n < 1 || n > 100
                      ? '1~100 사이 정수를 입력해 주세요'
                      : null;
                },
              ),
              ExpansionTile(
                title: const Text('상세 판정 기준'),
                initiallyExpanded: _inspection == 'nut_hole_alignment',
                children: [
                  TextFormField(
                    controller: _candidate,
                    decoration: const InputDecoration(labelText: '후보 신뢰도'),
                    validator: _ratio,
                  ),
                  TextFormField(
                    controller: _present,
                    decoration: const InputDecoration(labelText: '확정 신뢰도'),
                    validator: (text) {
                      final error = _ratio(text);
                      if (error != null) return error;
                      return double.parse(text!) <
                              (double.tryParse(_candidate.text) ?? 0)
                          ? '후보 신뢰도 이상이어야 합니다'
                          : null;
                    },
                  ),
                  if (_inspection == 'nut_hole_alignment')
                    for (final entry in _geometry.entries)
                      TextFormField(
                        controller: entry.value,
                        decoration: InputDecoration(
                          labelText: geometryLabels[entry.key],
                        ),
                        validator: (text) => _ratio(text, optional: true),
                      ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          Navigator.pop(
            context,
            RecipePoint(
              name: _name.text.trim(),
              inspectionId: _inspection,
              expectedCount: _count.text.trim().isEmpty
                  ? null
                  : int.parse(_count.text.trim()),
              candidateConfidence: double.parse(_candidate.text),
              presentConfidence: double.parse(_present.text),
              geometry: _inspection == 'nut_hole_alignment'
                  ? _geometry.map(
                      (key, controller) => MapEntry(
                        key,
                        controller.text.trim().isEmpty
                            ? null
                            : double.parse(controller.text),
                      ),
                    )
                  : null,
            ),
          );
        },
        child: const Text('포인트 저장'),
      ),
    ],
  );
}

class _RecipePreview extends StatefulWidget {
  const _RecipePreview({required this.settings, required this.camera});
  final AppSettings settings;
  final String camera;
  @override
  State<_RecipePreview> createState() => _RecipePreviewState();
}

class _RecipePreviewState extends State<_RecipePreview> {
  final _api = RemoteCaptureApiService();
  late final FrameReceiverService _receiver;
  String? _error;
  bool _ready = false;
  bool _starting = true;
  @override
  void initState() {
    super.initState();
    _receiver = FrameReceiverService();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _api.setViewerSource(widget.settings, widget.camera);
      if (!mounted) return;
      _receiver.setExpectedCameraId(widget.camera);
      await _receiver.connect(widget.settings.streamUri.toString());
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _close() {
    if (!_starting) Navigator.pop(context);
  }

  @override
  void dispose() {
    _receiver.dispose();
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Dialog(
      child: SizedBox(
        width: 1000,
        height: 700,
        child: Column(
          children: [
            ListTile(
              title: Text('${widget.camera} 실시간 미리보기'),
              subtitle: const Text('선택한 카메라가 뷰어 미리보기에도 적용됩니다.'),
              trailing: TextButton(
                onPressed: _starting ? null : _close,
                child: const Text('닫기'),
              ),
            ),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
            Expanded(
              child: AnimatedBuilder(
                animation: _receiver,
                builder: (context, _) {
                  final frame = _receiver.currentFrame;
                  return frame == null
                      ? Center(
                          child: Text(
                            _receiver.errorMessage ??
                                (_ready ? '카메라 프레임 대기 중' : '카메라 연결 중…'),
                          ),
                        )
                      : Image.memory(
                          frame,
                          gaplessPlayback: true,
                          fit: BoxFit.contain,
                        );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
