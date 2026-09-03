import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/remote_capture_api_service.dart';

class InspectionResultsScreen extends StatefulWidget {
  const InspectionResultsScreen({super.key});

  @override
  State<InspectionResultsScreen> createState() =>
      _InspectionResultsScreenState();
}

class _InspectionResultsScreenState extends State<InspectionResultsScreen> {
  final RemoteCaptureApiService _api = RemoteCaptureApiService();
  final List<StationCaptureResult> _results = [];
  Timer? _pollTimer;
  String? _selectedCycleId;
  String? _error;
  DateTime? _lastUpdatedAt;
  bool _loading = true;
  bool _pollInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_refresh());
      _pollTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(_refresh()),
      );
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _api.close();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_pollInFlight || !mounted) return;
    _pollInFlight = true;
    final settings = context.read<SettingsProvider>().settings;
    List<StationCaptureResult>? nextResults;
    String? nextError;
    try {
      try {
        nextResults = (await _api.fetchStationResults(settings)).results;
      } on RemoteCaptureApiException catch (error) {
        if (error.statusCode != 404) rethrow;
        final status = await _api.fetchStationStatus(settings);
        final lastResult = status.lastResult;
        nextResults = lastResult == null
            ? const []
            : [StationCaptureResult.fromJson(lastResult)];
      }
    } catch (error) {
      nextError = 'Failed to load capture results: $error';
    } finally {
      _pollInFlight = false;
    }
    if (!mounted) return;
    if (nextResults != null) {
      nextResults = List.of(nextResults)
        ..sort(
          (left, right) =>
              (right.requestedAtMs ?? 0).compareTo(left.requestedAtMs ?? 0),
        );
    }
    setState(() {
      if (nextResults != null) {
        _results
          ..clear()
          ..addAll(nextResults);
        if (!_results.any((result) => result.cycleId == _selectedCycleId)) {
          _selectedCycleId = _results.isEmpty ? null : _results.first.cycleId;
        }
        _lastUpdatedAt = DateTime.now();
      }
      _error = nextError;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = _results.cast<StationCaptureResult?>().firstWhere(
      (result) => result?.cycleId == _selectedCycleId,
      orElse: () => null,
    );
    return Column(
      children: [
        _buildHeader(),
        const Divider(height: 1),
        if (_error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.deepOrange.withValues(alpha: 0.12),
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          ),
        Expanded(
          child: _loading && _results.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _results.isEmpty
              ? const _EmptyResults()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 760) {
                      return Column(
                        children: [
                          SizedBox(height: 230, child: _buildResultList()),
                          const Divider(height: 1),
                          Expanded(child: _buildResultDetails(selected)),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        SizedBox(width: 340, child: _buildResultList()),
                        const VerticalDivider(width: 1),
                        Expanded(child: _buildResultDetails(selected)),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final updated = _lastUpdatedAt;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          Icon(
            Icons.fact_check_outlined,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(width: 10),
          const Text(
            'Capture Results',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 12),
          Text(
            '${_results.length} cycles',
            style: const TextStyle(color: Colors.white60),
          ),
          const Spacer(),
          if (updated != null) ...[
            Text(
              'Updated ${_formatClock(updated)}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(width: 10),
          ],
          IconButton(
            tooltip: 'Refresh',
            onPressed: _pollInFlight ? null : () => unawaited(_refresh()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  Widget _buildResultList() {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final result = _results[index];
        final selected = result.cycleId == _selectedCycleId;
        return Material(
          color: selected
              ? Theme.of(context).colorScheme.secondary.withValues(alpha: 0.12)
              : const Color(0xFF252525),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _selectedCycleId = result.cycleId),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected
                      ? Theme.of(context).colorScheme.secondary
                      : const Color(0xFF484848),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _shortCycleId(result.cycleId),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      _statusChip(result.presentationStatus),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    [
                      if (result.group.isNotEmpty) result.group,
                      _formatTimestamp(result.requestedAtMs),
                    ].join(' · '),
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildResultDetails(StationCaptureResult? result) {
    if (result == null) {
      return const Center(child: Text('Select a capture cycle'));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  result.cycleId,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _statusChip(result.presentationStatus),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _showRawResult(result),
                icon: const Icon(Icons.data_object, size: 16),
                label: const Text('Raw JSON'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              _detailValue('Set', result.setId),
              _detailValue('Group', result.group),
              _detailValue('Requested', _formatTimestamp(result.requestedAtMs)),
              _detailValue('Started', _formatTimestamp(result.startedAtMs)),
              _detailValue('Finished', _formatTimestamp(result.finishedAtMs)),
            ],
          ),
          if (result.error.isNotEmpty || result.artifactError.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              result.artifactError.isNotEmpty
                  ? 'Artifact error: ${result.artifactError}'
                  : result.error,
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          ],
          const SizedBox(height: 22),
          const Text(
            'Inspections',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          if (result.inspections.isEmpty)
            Text(
              result.state.isFinal
                  ? 'No inspection details'
                  : 'Waiting for inspection results…',
              style: const TextStyle(color: Colors.white60),
            )
          else
            for (final inspection in result.inspections.values) ...[
              _buildInspectionCard(inspection),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  Widget _buildInspectionCard(StationInspectionResult inspection) {
    final measurements = inspection.measurements.isEmpty
        ? ''
        : const JsonEncoder.withIndent('  ').convert(inspection.measurements);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF484848)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  inspection.inspectionId,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              _statusChip(inspection.status),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              _detailValue('Camera', inspection.cameraId),
              _detailValue(
                'Latency',
                inspection.latencyMs == null
                    ? '-'
                    : '${inspection.latencyMs!.toStringAsFixed(1)} ms',
              ),
              _detailValue('Detections', '${inspection.detections.length}'),
            ],
          ),
          if (inspection.reason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Reason: ${inspection.reason}'),
          ],
          if (inspection.failedMetrics.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Failed metrics: ${inspection.failedMetrics.join(', ')}',
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          ],
          if (measurements.isNotEmpty) ...[
            const SizedBox(height: 10),
            SelectableText(
              measurements,
              style: const TextStyle(
                color: Colors.white70,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailValue(String label, String value) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label  ',
            style: const TextStyle(color: Colors.white54),
          ),
          TextSpan(text: value.isEmpty ? '-' : value),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final color = switch (status) {
      'OK' || 'PRESENT' || 'COMPLETED' => Colors.greenAccent,
      'NG' || 'ABSENT' => Colors.redAccent,
      'RECHECK' => Colors.orangeAccent,
      'EQUIPMENT_ERROR' => Colors.deepOrangeAccent,
      'CANCELLED' || 'EXPIRED' => Colors.grey,
      _ => Colors.lightBlueAccent,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color),
      ),
      child: Text(
        status.isEmpty ? 'UNKNOWN' : status,
        style: TextStyle(color: color, fontSize: 11),
      ),
    );
  }

  void _showRawResult(StationCaptureResult result) {
    final json = result.rawJson.isEmpty
        ? {'cycle_id': result.cycleId, 'state': result.state.name}
        : result.rawJson;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Capture result JSON'),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(json),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(int? milliseconds) {
    if (milliseconds == null) return '-';
    return _formatDateTime(
      DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal(),
    );
  }

  String _formatDateTime(DateTime value) {
    String two(int part) => part.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  String _formatClock(DateTime value) {
    String two(int part) => part.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  String _shortCycleId(String cycleId) =>
      cycleId.length <= 24 ? cycleId : '${cycleId.substring(0, 24)}…';
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 52, color: Colors.white38),
          SizedBox(height: 12),
          Text('No capture results yet'),
          SizedBox(height: 5),
          Text(
            'Request a capture from Viewer to create a result.',
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }
}
