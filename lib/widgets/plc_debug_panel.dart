import 'package:flutter/material.dart';
import '../models/production.dart';
import '../services/remote_capture_api_service.dart';
import 'station_inspection_image.dart';

class PlcDebugPanel extends StatefulWidget {
  const PlcDebugPanel({
    super.key,
    required this.catalog,
    required this.status,
    required this.fresh,
    required this.busy,
    required this.captureApi,
    required this.onConnect,
    required this.onDisconnect,
    required this.onCapture,
    required this.onConfigure,
    this.onPreview,
  });
  final ValueChanged<RecipePoint>? onPreview;
  final RecipeCatalog catalog;
  final ProductionStatus? status;
  final bool fresh, busy;
  final RemoteCaptureApiService captureApi;
  final void Function(bool simulator) onConnect;
  final VoidCallback onDisconnect, onConfigure;
  final void Function(String simulatorId, int product, int point, int hardware)
  onCapture;
  @override
  State<PlcDebugPanel> createState() => _PlcDebugPanelState();
}

class _PlcDebugPanelState extends State<PlcDebugPanel> {
  bool _simulated = true;
  int _product = 1;
  int? _point;
  int _hardware = 0;
  @override
  void initState() {
    super.initState();
    if (widget.status?.plc?.canDisconnect == true) {
      _simulated = widget.status?.plc?.source == 'simulator';
    }
  }

  @override
  void didUpdateWidget(covariant PlcDebugPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.status?.plc?.canDisconnect == true) {
      _simulated = widget.status?.plc?.source == 'simulator';
    }
    if (_product > widget.catalog.products.length) {
      _product = 1;
      _point = null;
    }
    final count =
        widget.catalog.products[_product - 1].active?.points.length ?? 0;
    if (_point != null && _point! > count) _point = null;
  }

  String _hardwareLabel(int? id) => id == null
      ? '미확인'
      : '$id · ${inspectionLabels[inspectionHardwareIds.entries.firstWhere((e) => e.value == id).key]}';
  Widget _signal(String label, int? value) => Chip(
    avatar: Icon(
      Icons.circle,
      size: 14,
      color: value == null
          ? Colors.grey
          : value == 1
          ? Colors.green
          : Colors.grey,
    ),
    label: Text(
      '$label ${value == null
          ? '미확인'
          : value == 1
          ? 'ON'
          : 'OFF'}',
    ),
  );
  @override
  Widget build(BuildContext context) {
    final plc = widget.status?.plc;
    final sim = plc?.simulator;
    final active = widget.status?.capture?.active == true;
    final disconnected =
        plc != null &&
        {
          PlcConnectionState.disabled,
          PlcConnectionState.disconnected,
        }.contains(plc.state);
    final connected =
        widget.fresh && plc?.state == PlcConnectionState.connected;
    final modeMatches = plc?.source == (_simulated ? 'simulator' : 'real');
    final canSwitch = widget.fresh && !widget.busy && disconnected && !active;
    final canCapture =
        !widget.busy &&
        connected &&
        modeMatches &&
        _simulated &&
        sim?.ready == true &&
        !active &&
        _point != null;
    final slot = widget.catalog.products[_product - 1];
    final points = slot.active?.points ?? const <RecipePoint>[];
    final point = _point == null ? null : points[_point! - 1];
    final requestMatches =
        !_simulated ||
        (sim?.requestId != null && plc?.simulatorRequestId == sim?.requestId);
    final current = widget.status?.capture;
    final capture =
        requestMatches &&
            {'plc', 'plc_simulator'}.contains(current?.origin) &&
            current?.requestId != null &&
            current?.requestId == plc?.requestId
        ? current
        : null;
    int? output(int index, String name) {
      if (!connected || !modeMatches) return null;
      if (_simulated) {
        final words = sim?.receivedWords;
        return words == null ? null : words[index];
      }
      final position = plc?.txMap[name];
      return position == null ? null : plc!.word('tx', position);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('연결 대상', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Text(
          '실제 카메라로 촬영합니다. 대상을 바꾸려면 먼저 연결을 해제하세요.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              key: const ValueKey('debug-simulator'),
              label: const Text('PLC 시뮬레이터'),
              selected: _simulated,
              onSelected: canSwitch
                  ? (_) => setState(() => _simulated = true)
                  : null,
            ),
            ChoiceChip(
              key: const ValueKey('debug-real'),
              label: const Text('실제 PLC'),
              selected: !_simulated,
              onSelected: canSwitch
                  ? (_) => setState(() => _simulated = false)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              key: const ValueKey('debug-connect'),
              onPressed:
                  canSwitch &&
                      (!_simulated || plc.simulatorSupported) &&
                      (_simulated || plc.enabled)
                  ? () => widget.onConnect(_simulated)
                  : null,
              child: Text(_simulated ? '시뮬레이터 연결' : '실제 PLC 연결'),
            ),
            OutlinedButton(
              key: const ValueKey('debug-disconnect'),
              onPressed:
                  !widget.busy && widget.fresh && plc?.canDisconnect == true
                  ? widget.onDisconnect
                  : null,
              child: const Text('연결 해제'),
            ),
            TextButton(
              onPressed: widget.onConfigure,
              child: const Text('실제 PLC 설정·진단'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          widget.fresh
              ? '연결 상태: ${plc?.state.code ?? '미지원'} · ${plc?.host ?? ''}:${plc?.port ?? ''}'
              : '상태 확인 불가 — 신호 전송이 잠겼습니다.',
        ),
        if (_simulated && plc?.simulatorSupported != true)
          const Text('이 Inspect는 GUI 시뮬레이터 API를 지원하지 않습니다. Inspect를 업데이트하세요.'),
        if (!_simulated && plc?.enabled != true)
          const Text('실제 PLC의 IP·포트·신호표를 설정하고 사용을 켜세요.'),
        if ((plc?.error ?? '').isNotEmpty)
          SelectableText(
            plc!.error,
            style: const TextStyle(color: Colors.orange),
          ),
        if ((sim?.error ?? '').isNotEmpty)
          SelectableText(
            sim!.error,
            style: const TextStyle(color: Colors.orange),
          ),
        const Divider(height: 28),
        if (_simulated) ...[
          Text('1. 촬영 대상', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: const ValueKey('debug-product'),
            initialValue: _product,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '제품',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final product in widget.catalog.products)
                DropdownMenuItem(
                  value: product.productId,
                  child: Text(
                    '${product.productId} · ${product.active?.name ?? '${product.draft.name} (미적용)'}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: !widget.busy && !active
                ? (v) => setState(() {
                    _product = v!;
                    _point = null;
                  })
                : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: ValueKey('debug-point-$_product'),
            initialValue: _point,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '촬영 포인트',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final (i, p) in points.indexed)
                DropdownMenuItem(
                  value: i + 1,
                  child: Text(
                    '${i + 1} · ${p.name}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: !widget.busy && !active
                ? (v) => setState(() => _point = v)
                : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: const ValueKey('debug-hardware'),
            initialValue: _hardware,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '하드웨어 번호',
              border: OutlineInputBorder(),
            ),
            items: [
              for (var i = 0; i < 4; i++)
                DropdownMenuItem(value: i, child: Text(_hardwareLabel(i))),
            ],
            onChanged: !widget.busy && !active
                ? (v) => setState(() => _hardware = v!)
                : null,
          ),
          const SizedBox(height: 8),
          if (points.isEmpty) const Text('적용된 촬영 포인트가 없습니다. 레시피를 먼저 저장·적용하세요.'),
          if (point != null)
            Text(
              '적용 기준: ${inspectionLabels[point.inspectionId]} · 기대 ${point.expectedCount}개 · ${point.roi?.summary ?? '전체 프레임'}',
            ),
          if (point != null && widget.onPreview != null)
            TextButton.icon(
              onPressed: widget.busy ? null : () => widget.onPreview!(point),
              icon: const Icon(Icons.center_focus_strong),
              label: const Text('검사 영역 · 위치 확인'),
            ),
          if (point != null &&
              inspectionHardwareIds[point.inspectionId] != _hardware)
            const Text(
              '선택한 하드웨어가 레시피와 다릅니다. 전송하면 촬영 없이 NG가 반환됩니다.',
              style: TextStyle(color: Colors.orange),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text('제품 $_product ON')),
              Chip(
                label: Text(
                  '포인트 ${_point ?? '미선택'} ${_point == null ? '' : 'ON'}',
                ),
              ),
              Chip(label: Text('하드웨어 $_hardware ON')),
              FilledButton.icon(
                key: const ValueKey('debug-capture'),
                onPressed: canCapture
                    ? () => widget.onCapture(
                        sim!.id,
                        _product,
                        _point!,
                        _hardware,
                      )
                    : null,
                icon: const Icon(Icons.camera_alt),
                label: const Text('신호 전송 · 실제 촬영'),
              ),
            ],
          ),
          const Text(
            '버튼을 누르면 세 선택을 ON으로 전송하고 다음 프레임에서 하드웨어를 모두 OFF로 내립니다. 결과가 올 때까지 재전송하지 않습니다.',
          ),
          if (sim?.requestId != null) ...[
            const SizedBox(height: 12),
            Text(
              '이번 전송: 제품 ${sim!.productId} · 포인트 ${sim.pointNumber} · ${_hardwareLabel(sim.hardwareId)}',
            ),
            Text(
              '진행: ${sim.state} · Inspect 수신 ${requestMatches ? '확인' : '대기'} · 결과 초기화 ${sim.cleared ? '확인' : '대기'} · 선택 OFF ${sim.rearmed ? '완료' : '대기'}',
            ),
          ],
        ] else ...[
          const Text(
            '촬영 신호는 실제 PLC에서 보냅니다. 아래에서 Inspect가 받은 선택과 촬영 결과를 확인하세요.',
          ),
          Text(
            '수신 선택: 제품 ${plc?.productId ?? '미확인'} · 포인트 ${plc?.pointNumber ?? '미확인'} · 하드웨어 ${_hardwareLabel(plc?.hardwareId)}',
          ),
        ],
        const Divider(height: 28),
        Text(
          _simulated ? '2. 시뮬레이터 수신 결과' : 'Inspect → 실제 PLC 송신 신호',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Wrap(
          spacing: 8,
          children: [
            _signal('OK', output(0, 'ok')),
            _signal('NG', output(1, 'ng')),
            _signal('Heartbeat', output(2, 'heartbeat')),
          ],
        ),
        if (_simulated && sim?.result != null)
          Text(
            '이번 요청 결과: ${sim!.result}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        if (!_simulated) const Text('송신 기록이며 실제 PLC가 읽었다는 확인은 아닙니다.'),
        const Divider(height: 28),
        Text('3. 실제 촬영 결과', style: Theme.of(context).textTheme.titleMedium),
        if (capture == null)
          const Text('이번 요청의 촬영 결과를 기다립니다. 촬영 전에 거부된 요청은 이미지가 없습니다.'),
        if (capture != null) ...[
          Text(
            '${capture.recipe.name} · 포인트 ${capture.pointNumber} · ${capture.state.code} · ${capture.status}',
          ),
          if (capture.error.isNotEmpty) SelectableText(capture.error),
          for (final result in capture.results) ...[
            Text(
              '${result.capture.status} · ${result.summaries.map((s) => '기대 ${s.expectedCount} / 검출 ${s.presentCount} · ${s.reason}').join(' / ')}',
            ),
            if (result.reason != null) SelectableText(result.reason!),
            if (result.capture.inspections.isNotEmpty)
              StationInspectionImage(
                key: ValueKey(result.capture.cycleId),
                result: result.capture,
                inspection: result.capture.inspections.values.first,
                api: widget.captureApi,
                archived: true,
              ),
          ],
        ],
      ],
    );
  }
}
