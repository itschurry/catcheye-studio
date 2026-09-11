import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../services/remote_capture_api_service.dart';
import 'zoomable_viewport.dart';

/// Shows saved evidence for one inspection cycle. Never subscribes to preview.
class StationInspectionImage extends StatefulWidget {
  const StationInspectionImage({
    super.key,
    required this.result,
    required this.inspection,
    required this.api,
    this.archived = false,
  });
  final StationCaptureResult result;
  final StationInspectionResult inspection;
  final RemoteCaptureApiService api;
  final bool archived;

  @override
  State<StationInspectionImage> createState() => _StationInspectionImageState();
}

class _StationInspectionImageState extends State<StationInspectionImage> {
  String _kind = 'overlay';
  String? _connection;
  Uint8List? _bytes;
  String? _error;
  bool _loading = true;
  int _session = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final connection = context
        .watch<SettingsProvider>()
        .settings
        .buildApiUri('capture/results')
        .toString();
    if (_connection != connection) {
      _connection = connection;
      unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(covariant StationInspectionImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.result.cycleId != widget.result.cycleId ||
        oldWidget.inspection.inspectionId != widget.inspection.inspectionId ||
        oldWidget.result.state != widget.result.state ||
        oldWidget.inspection.artifacts[_kind] !=
            widget.inspection.artifacts[_kind] ||
        oldWidget.api != widget.api) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final session = ++_session;
    setState(() {
      _bytes = null;
      _error = null;
      _loading = true;
    });
    try {
      if (!widget.result.state.isFinal) {
        throw StateError('완료된 검사의 이미지가 아직 없습니다.');
      }
      if (!widget.inspection.artifacts.containsKey(_kind)) {
        throw StateError(
          widget.inspection.artifactError.isNotEmpty
              ? '이미지 저장 실패: ${widget.inspection.artifactError}'
              : '이 검사의 ${_kind == 'overlay' ? '검출 결과' : '원본'} 이미지가 저장되지 않았습니다. Inspect 저장 설정과 검사 오류를 확인해 주세요.',
        );
      }
      final storagePath = widget.result.rawJson['storage_path'];
      if (widget.archived && (storagePath is! String || storagePath.isEmpty)) {
        throw StateError('저장된 검사 이미지 경로가 없습니다.');
      }
      final bytes = await widget.api.fetchStationImage(
        context.read<SettingsProvider>().settings,
        cycleId: widget.result.cycleId,
        inspectionId: widget.inspection.inspectionId,
        kind: _kind,
        storagePath: widget.archived ? storagePath as String : null,
      );
      if (!mounted || session != _session) return;
      setState(() => _bytes = bytes);
    } on RemoteCaptureApiException catch (error) {
      if (!mounted || session != _session) return;
      setState(
        () => _error = error.statusCode == 404
            ? '이미지를 찾을 수 없습니다. Inspect의 이미지 조회 API 적용 여부와 파일 보존 상태를 확인해 주세요.\n${error.message}'
            : '이미지 조회 실패 (${error.statusCode})\n${error.message}',
      );
    } catch (error) {
      if (!mounted || session != _session) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted && session == _session) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            const Text(
              '검사 당시 저장 이미지',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'overlay', label: Text('검출 결과')),
                ButtonSegment(value: 'raw', label: Text('원본')),
              ],
              selected: {_kind},
              onSelectionChanged: (value) {
                setState(() => _kind = value.single);
                unawaited(_load());
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: MediaQuery.sizeOf(context).width < 760 ? 260 : 420,
          child: ColoredBox(
            color: Colors.black,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.image_not_supported_outlined,
                            size: 36,
                            color: Colors.orangeAccent,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            style: const TextStyle(color: Colors.orangeAccent),
                          ),
                        ],
                      ),
                    ),
                  )
                : ZoomableViewport(
                    key: ValueKey(
                      '${widget.result.cycleId}-${widget.inspection.inspectionId}-$_kind',
                    ),
                    child: Image.memory(
                      _bytes!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Center(
                        child: Text(
                          '저장 이미지 파일을 해석할 수 없습니다.',
                          style: TextStyle(color: Colors.orangeAccent),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          '휠·+/−로 확대 · 드래그로 이동 · 실시간 미리보기가 아닌 이 검사의 이미지',
          style: TextStyle(color: Colors.white60, fontSize: 12),
        ),
      ],
    );
  }
}
