import '../controllers/model_jobs_controller.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../widgets/status_label.dart';
import 'package:flutter/gestures.dart';
import '../widgets/zoomable_viewport.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../providers/reference_credential_provider.dart';
import '../providers/settings_provider.dart';
import '../services/remote_reference_api_service.dart';

class ReferenceImagesScreen extends StatefulWidget {
  const ReferenceImagesScreen({
    super.key,
    this.isPhone = false,
    this.initialStatus,
    this.refreshKey,
    this.api,
  });

  final bool isPhone;
  final ReferenceApiStatus? initialStatus;
  final String? refreshKey;
  final RemoteReferenceApiService? api;

  @override
  State<ReferenceImagesScreen> createState() => _ReferenceImagesScreenState();
}

class _ReferenceImagesScreenState extends State<ReferenceImagesScreen> {
  late final RemoteReferenceApiService _api;
  late final bool _ownsApi;

  ReferenceApiStatus? _status;
  List<ReferenceRevisionSummary> _revisions = const [];
  ReferenceRevision? _currentRevision;
  String? _baseRevisionId;
  String? _cameraId;
  String? _className;
  ReferenceCapture? _capture;
  _EditableReferenceImage? _editorImage;
  Uint8List? _imageBytes;
  List<ReferenceBox> _boxes = const [];
  String? _error;
  bool _loading = false;
  bool _capturing = false;
  bool _saving = false;
  int _pollSession = 0;
  String? _captureRequestId;
  String? _revisionRequestId;
  _ReferencePage _page = _ReferencePage.references;
  List<ReferenceModel> _models = const [];
  ReferenceModel? _selectedModel;
  late final ModelJobsController _jobs;
  ReferenceApiStatus? _lastJobStatus;
  int _reloadGeneration = 0;
  String? _endpoint;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? RemoteReferenceApiService();
    _ownsApi = widget.api == null;
    _jobs = ModelJobsController(
      api: _api,
      readToken: _readToken,
      showMessage: _showMessage,
      refresh: _reload,
      displayId: _displayId,
      modelLabel: _modelLabel,
    )..addListener(_onJobsChanged);
    _status = widget.initialStatus;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_reload());
    });
  }

  void _onJobsChanged() {
    if (!mounted) return;
    setState(() {
      final status = _jobs.status;
      if (status != null && !identical(status, _lastJobStatus)) {
        _status = status;
        _lastJobStatus = status;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = context.watch<SettingsProvider>().settings;
    final endpoint = settings.buildApiUri('reference').toString();
    _jobs.bind(settings);
    if (_endpoint != null && _endpoint != endpoint) {
      _pollSession++;
      _reloadGeneration++;
      _capture = null;
      _editorImage = null;
      _imageBytes = null;
      _boxes = const [];
      _cameraId = _className = _baseRevisionId = null;
      _currentRevision = null;
      _selectedModel = null;
      _captureRequestId = _revisionRequestId = null;
      _capturing = _saving = false;
      _status = null;
      _revisions = const [];
      _models = const [];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_reload());
      });
    }
    _endpoint = endpoint;
  }

  @override
  void didUpdateWidget(covariant ReferenceImagesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey) {
      unawaited(_reload());
    }
  }

  @override
  void dispose() {
    _pollSession++;
    _jobs.dispose();
    _reloadGeneration++;
    if (_ownsApi) _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Column(
      children: [
        _buildToolbar(context, status),
        const Divider(height: 1),
        if (_error != null && status != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(
              context,
            ).colorScheme.errorContainer.withValues(alpha: 0.45),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
        Expanded(child: _buildBody(context, status)),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context, ReferenceApiStatus? status) {
    final scheme = Theme.of(context).colorScheme;
    final hasModelPages =
        status != null &&
        (status.capabilities.modelBuild || status.capabilities.modelActivation);
    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: widget.isPhone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.collections_bookmark_outlined,
                      color: scheme.secondary,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '기준 이미지',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (status != null) _StateChip(state: status.deviceState),
                    const SizedBox(width: 8),
                    _buildRefreshButton(),
                  ],
                ),
                if (status?.activeModelId case final activeModel?) ...[
                  const SizedBox(height: 6),
                  Text(
                    '사용 중: ${_modelLabel(activeModel)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (hasModelPages) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _buildPageSelector(compact: true),
                  ),
                ],
              ],
            )
          : Row(
              children: [
                Icon(
                  Icons.collections_bookmark_outlined,
                  color: scheme.secondary,
                ),
                const SizedBox(width: 8),
                const Text(
                  '기준 이미지',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 12),
                if (status != null) _StateChip(state: status.deviceState),
                if (status?.activeModelId case final activeModel?) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '사용 중: ${_modelLabel(activeModel)}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (hasModelPages) ...[
                  _buildPageSelector(compact: false),
                  const SizedBox(width: 8),
                ],
                _buildRefreshButton(),
              ],
            ),
    );
  }

  Widget _buildPageSelector({required bool compact}) {
    return SegmentedButton<_ReferencePage>(
      key: const ValueKey('reference-page-selector'),
      showSelectedIcon: false,
      segments: compact
          ? const [
              ButtonSegment(
                value: _ReferencePage.references,
                icon: Icon(Icons.crop_free, size: 18),
              ),
              ButtonSegment(
                value: _ReferencePage.models,
                icon: Icon(Icons.model_training_outlined, size: 18),
              ),
            ]
          : const [
              ButtonSegment(
                value: _ReferencePage.references,
                icon: Icon(Icons.crop_free, size: 18),
                label: Text('기준 이미지'),
              ),
              ButtonSegment(
                value: _ReferencePage.models,
                icon: Icon(Icons.model_training_outlined, size: 18),
                label: Text('모델'),
              ),
            ],
      selected: {_page},
      onSelectionChanged: (selection) =>
          setState(() => _page = selection.single),
    );
  }

  Widget _buildRefreshButton() {
    return IconButton.outlined(
      tooltip: '지원 기능과 개정본 새로고침',
      onPressed: _loading ? null : _reload,
      icon: const Icon(Icons.refresh, size: 20),
    );
  }

  Widget _buildBody(BuildContext context, ReferenceApiStatus? status) {
    if (_loading && status == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (status == null) {
      return _MessagePanel(
        icon: Icons.extension_off_outlined,
        title: '기준 이미지를 관리할 수 없습니다',
        message: _error ?? '이 장비는 Reference API v1을 지원하지 않습니다.',
        onRetry: _reload,
      );
    }
    if (!status.capabilities.hasReferenceManagement) {
      return _MessagePanel(
        icon: Icons.extension_off_outlined,
        title: '기준 이미지 관리가 비활성화되어 있습니다',
        message: '장비에서 해당 기능이 비활성화되어 있습니다.',
        onRetry: _reload,
      );
    }
    if (_page == _ReferencePage.models) {
      return _buildModelsBody(context, status);
    }

    final controls = _buildControls(context, status);
    final editor = _buildEditor(context);
    final boxes = _buildBoxesPanel(context, status);
    if (widget.isPhone || MediaQuery.sizeOf(context).width < 820) {
      return Column(
        children: [
          SizedBox(height: 280, child: controls),
          const Divider(height: 1),
          Expanded(child: editor),
          const Divider(height: 1),
          SizedBox(height: 210, child: boxes),
        ],
      );
    }
    return Row(
      children: [
        SizedBox(width: 300, child: controls),
        const VerticalDivider(width: 1),
        Expanded(child: editor),
        const VerticalDivider(width: 1),
        SizedBox(width: 300, child: boxes),
      ],
    );
  }

  Widget _buildControls(BuildContext context, ReferenceApiStatus status) {
    final classes = _cameraId == null
        ? const <String>[]
        : status.cameraClasses[_cameraId] ?? const <String>[];
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('촬영 대상', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('reference-camera-$_cameraId'),
            initialValue: _cameraId,
            decoration: const InputDecoration(
              labelText: '카메라',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final cameraId in status.cameraClasses.keys)
                DropdownMenuItem(value: cameraId, child: Text(cameraId)),
            ],
            onChanged: _capturing ? null : _selectCamera,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('reference-class-$_cameraId-$_className'),
            initialValue: classes.contains(_className) ? _className : null,
            decoration: const InputDecoration(
              labelText: '분류',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final className in classes)
                DropdownMenuItem(
                  value: className,
                  child: Text(_classLabel(className)),
                ),
            ],
            onChanged: _capturing ? null : _selectClass,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed:
                status.capabilities.referenceCapture &&
                    status.isRunning &&
                    _cameraId != null &&
                    !_capturing
                ? _startCapture
                : null,
            icon: _capturing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.camera_alt_outlined),
            label: Text(_capturing ? '촬영 중…' : '새 이미지 촬영'),
          ),
          if (!status.isRunning) ...[
            const SizedBox(height: 8),
            Text(
              '장비가 실행 중일 때만 촬영할 수 있습니다.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          if (!status.capabilities.referenceCapture) ...[
            const SizedBox(height: 8),
            const Text(
              '이 장비에서는 이미지 촬영이 비활성화되어 있습니다.',
              style: TextStyle(fontSize: 12),
            ),
          ],
          if (_capture case final capture?) ...[
            const SizedBox(height: 18),
            const Divider(),
            const SizedBox(height: 6),
            const Text('촬영 작업', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SelectableText(
              capture.captureId,
              style: const TextStyle(fontFamily: 'NotoSansKR', fontSize: 12),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _StateChip(state: capture.state.name.toUpperCase()),
                const Spacer(),
                if (!capture.state.isFinal ||
                    capture.state == ReferenceCaptureState.failed)
                  IconButton(
                    tooltip: '촬영 상태 확인',
                    onPressed: _capturing ? null : _refreshCapture,
                    icon: const Icon(Icons.sync),
                  ),
              ],
            ),
            if (capture.error.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                capture.error,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 6),
          const Text('기준 개정본', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey(
              'base-revision-$_baseRevisionId-${_revisions.length}',
            ),
            initialValue:
                _revisions.any(
                  (revision) => revision.revisionId == _baseRevisionId,
                )
                ? _baseRevisionId
                : null,
            decoration: const InputDecoration(
              labelText: '개정본',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final revision in _revisions)
                DropdownMenuItem(
                  value: revision.revisionId,
                  child: Tooltip(
                    message: revision.revisionId,
                    child: Text(
                      _displayId(revision.revisionId),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
            onChanged: _saving ? null : _selectBaseRevision,
          ),
          if (_revisions.isEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              '기준 개정본이 없어서 새 개정본을 저장할 수 없습니다.',
              style: TextStyle(fontSize: 12),
            ),
          ] else if (_currentRevision != null) ...[
            const SizedBox(height: 12),
            const Text(
              '현재 기준 이미지',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            for (final entry in _currentRevision!.entries)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(_classLabel(entry.className)),
                subtitle: Text(
                  '${entry.width} × ${entry.height} · 박스 ${entry.boxes.length}개',
                ),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: _loading ? null : () => _openRevisionEntry(entry),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    final image = _editorImage;
    if (image == null || _imageBytes == null) {
      return const _MessagePanel(
        icon: Icons.crop_free,
        title: '원본 이미지를 촬영해 주세요',
        message: '이미지 위를 드래그해서 바운딩박스를 추가해 주세요.',
      );
    }
    return Container(
      color: const Color(0xFF101010),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${image.cameraId} · ${image.width} × ${image.height}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '드래그해서 박스 추가',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ReferenceBoxEditor(
              key: ValueKey(image.imageId),
              imageBytes: _imageBytes!,
              imageWidth: image.width,
              imageHeight: image.height,
              boxes: _boxes,
              onBoxesChanged: _setBoxes,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoxesPanel(BuildContext context, ReferenceApiStatus status) {
    final scheme = Theme.of(context).colorScheme;
    final canSave =
        status.capabilities.referenceRevisions &&
        _editorImage != null &&
        _baseRevisionId != null &&
        _className != null &&
        _boxes.isNotEmpty &&
        !_saving;
    return Material(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  '바운딩박스',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text('${_boxes.length} / 64'),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _boxes.isEmpty
                  ? Center(
                      child: Text(
                        '등록된 박스가 없습니다',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _boxes.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final box = _boxes[index];
                        final values = box.toJson();
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 13,
                            child: Text('${index + 1}'),
                          ),
                          title: Text(
                            '[${values.join(', ')}]',
                            style: const TextStyle(
                              fontFamily: 'NotoSansKR',
                              fontSize: 12,
                            ),
                          ),
                          trailing: IconButton(
                            tooltip: '박스 삭제',
                            onPressed: _saving ? null : () => _removeBox(index),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _boxes.isEmpty || _saving
                  ? null
                  : () => _setBoxes(const []),
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('박스 모두 삭제'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: canSave ? _saveRevision : null,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? '저장 중…' : '개정본 저장'),
            ),
            if (!status.capabilities.referenceRevisions) ...[
              const SizedBox(height: 8),
              const Text(
                '이 장비에서는 개정본 저장이 비활성화되어 있습니다.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModelsBody(BuildContext context, ReferenceApiStatus status) {
    final scheme = Theme.of(context).colorScheme;
    if (!status.capabilities.modelBuild &&
        !status.capabilities.modelActivation) {
      return const _MessagePanel(
        icon: Icons.model_training_outlined,
        title: '모델 관리가 비활성화되어 있습니다',
        message: '이 장비는 모델 관리 기능을 지원하지 않습니다.',
      );
    }
    final list = Material(
      color: scheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '모델을 빌드하는 동안 장비가 유지보수 상태로 전환되어 검사와 실시간 검출이 일시 중지됩니다.',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                if (_baseRevisionId case final revisionId?) ...[
                  Tooltip(
                    message: revisionId,
                    child: Text('빌드 기준: ${_displayId(revisionId)}'),
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton.icon(
                  onPressed:
                      status.capabilities.modelBuild &&
                          _baseRevisionId != null &&
                          !_jobs.busy
                      ? _confirmModelBuild
                      : null,
                  icon: const Icon(Icons.build_outlined),
                  label: const Text('선택한 개정본으로 빌드'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _models.isEmpty
                ? const Center(child: Text('등록된 모델이 없습니다'))
                : ListView.separated(
                    itemCount: _models.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final model = _models[index];
                      final active = model.modelId == status.activeModelId;
                      return ListTile(
                        selected: model.modelId == _selectedModel?.modelId,
                        leading: Icon(
                          active ? Icons.check_circle : Icons.memory_outlined,
                          color: active ? Colors.greenAccent : null,
                        ),
                        title: Tooltip(
                          message: model.modelId,
                          child: Text(
                            _displayId(model.modelId),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: 'NotoSansKR'),
                          ),
                        ),
                        isThreeLine: true,
                        subtitle: Tooltip(
                          message: model.referenceRevisionId,
                          child: Text(
                            '기준: ${_displayId(model.referenceRevisionId)}\n'
                            '${active
                                ? '사용 중'
                                : model.technicalPassed
                                ? '검증 완료'
                                : '미검증'}',
                          ),
                        ),
                        onTap: () => setState(() {
                          _selectedModel = model;
                          _jobs.activationRequestId = null;
                        }),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
    final details = _buildModelDetails(context, status);
    if (widget.isPhone || MediaQuery.sizeOf(context).width < 820) {
      return Column(
        children: [
          SizedBox(height: 310, child: list),
          const Divider(height: 1),
          Expanded(child: details),
        ],
      );
    }
    return Row(
      children: [
        SizedBox(width: 390, child: list),
        const VerticalDivider(width: 1),
        Expanded(child: details),
      ],
    );
  }

  Widget _buildModelDetails(BuildContext context, ReferenceApiStatus status) {
    final model = _selectedModel;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: const Color(0xFF181818),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_jobs.build case final build?) ...[
            _JobCard(
              title: '모델 빌드',
              id: build.buildId,
              state: build.state.name.toUpperCase(),
              error: build.error,
              onRefresh: !build.state.isFinal && !_jobs.busy
                  ? _jobs.resumeBuild
                  : null,
            ),
            const SizedBox(height: 12),
          ],
          if (_jobs.activation case final activation?) ...[
            _JobCard(
              title: '모델 적용',
              id: activation.activationId,
              state: _activationStateLabel(activation.state),
              error: activation.error,
              detail: '현재 사용 중: ${_modelLabel(activation.activeModelId)}',
              onRefresh: !activation.state.isFinal && !_jobs.busy
                  ? _jobs.resumeActivation
                  : null,
            ),
            const SizedBox(height: 12),
          ],
          if (model == null)
            const _MessagePanel(
              icon: Icons.memory_outlined,
              title: '모델을 선택해 주세요',
              message: '적용하기 전에 기술 검증 결과를 확인해 주세요.',
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    _displayId(model.modelId),
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(fontFamily: 'NotoSansKR'),
                  ),
                ),
                if (model.modelId == status.activeModelId)
                  const _StateChip(state: 'ACTIVE'),
              ],
            ),
            const SizedBox(height: 8),
            Tooltip(
              message: model.referenceRevisionId,
              child: Text('기준: ${_displayId(model.referenceRevisionId)}'),
            ),
            Text('생성: ${_formatTimestamp(model.createdAtMs)}'),
            ExpansionTile(
              key: ValueKey('model-identifiers-${model.modelId}'),
              tilePadding: EdgeInsets.zero,
              title: const Text('전체 식별자'),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    '모델 ID: ${model.modelId}\n'
                    '기준 개정본 ID: ${model.referenceRevisionId}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(
                  model.technicalPassed
                      ? Icons.verified_outlined
                      : Icons.warning_amber,
                  color: model.technicalPassed
                      ? Colors.greenAccent
                      : scheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    model.technicalPassed ? '기술 검증 통과' : '기술 검증 미통과',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.6)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '기술 검증이 생산 품질을 보증하지는 않습니다. 적용 전에 양품·불량 샘플로 확인해 주세요.',
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed:
                  status.capabilities.modelActivation &&
                      model.technicalPassed &&
                      model.modelId != status.activeModelId &&
                      !_jobs.busy &&
                      status.activeModelId != null
                  ? () => _confirmActivation(model)
                  : null,
              icon: const Icon(Icons.publish_outlined),
              label: Text(
                model.createdAtMs <
                        (_models
                                .where(
                                  (item) =>
                                      item.modelId == status.activeModelId,
                                )
                                .firstOrNull
                                ?.createdAtMs ??
                            0)
                    ? '이 모델로 복원'
                    : '이 모델 적용',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _reload() async {
    final generation = ++_reloadGeneration;
    final settings = context.read<SettingsProvider>().settings;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await _readToken(settings);
      final status = await _api.fetchStatus(settings, bearerToken: token);
      var revisions = const <ReferenceRevisionSummary>[];
      if (status.capabilities.referenceRevisions) {
        revisions = await _fetchAllRevisions(settings, token);
      }
      var models = const <ReferenceModel>[];
      if (status.capabilities.modelBuild ||
          status.capabilities.modelActivation) {
        models = (await _api.fetchModels(
          settings,
          bearerToken: token,
          limit: 100,
        )).models;
      }
      if (!mounted || generation != _reloadGeneration) return;
      final cameraId = status.cameraClasses.containsKey(_cameraId)
          ? _cameraId
          : status.cameraClasses.keys.firstOrNull;
      final classes = cameraId == null
          ? const <String>[]
          : status.cameraClasses[cameraId] ?? const <String>[];
      final baseRevisionId =
          revisions.any((revision) => revision.revisionId == _baseRevisionId)
          ? _baseRevisionId
          : revisions.firstOrNull?.revisionId;
      ReferenceRevision? currentRevision;
      if (baseRevisionId != null) {
        currentRevision = await _api.fetchRevision(
          settings,
          baseRevisionId,
          bearerToken: token,
        );
      }
      if (!mounted || generation != _reloadGeneration) return;
      final preferredModelId =
          _jobs.build?.candidateModelId ??
          _jobs.activation?.activeModelId ??
          _selectedModel?.modelId;
      final selectedModel = models
          .where((model) => model.modelId == preferredModelId)
          .firstOrNull;
      setState(() {
        _status = status;
        _revisions = revisions;
        _baseRevisionId = baseRevisionId;
        _currentRevision = currentRevision;
        _models = models;
        _selectedModel =
            selectedModel ??
            models
                .where((model) => model.modelId == status.activeModelId)
                .firstOrNull ??
            models.firstOrNull;
        _cameraId = cameraId;
        if (!classes.contains(_className)) _className = classes.firstOrNull;
      });
    } on RemoteReferenceApiException catch (error) {
      if (!mounted || generation != _reloadGeneration) return;
      setState(() {
        final statusMissing =
            error.statusCode == 404 &&
            error.uri.path.endsWith('/reference/status');
        if (statusMissing) _status = null;
        _error = statusMissing
            ? '이 장비에 Reference API v1이 설치되어 있지 않습니다.'
            : error.message;
      });
    } catch (error) {
      if (!mounted || generation != _reloadGeneration) return;
      setState(() => _error = _describeError(error));
    } finally {
      if (mounted && generation == _reloadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  void _selectCamera(String? cameraId) {
    final classes = cameraId == null
        ? const <String>[]
        : _status?.cameraClasses[cameraId] ?? const <String>[];
    _pollSession++;
    setState(() {
      _cameraId = cameraId;
      _className = classes.firstOrNull;
      _capture = null;
      _editorImage = null;
      _imageBytes = null;
      _boxes = const [];
      _captureRequestId = null;
      _revisionRequestId = null;
    });
  }

  void _selectClass(String? className) {
    setState(() {
      _className = className;
      _boxes = const [];
      _revisionRequestId = null;
    });
  }

  Future<void> _startCapture() async {
    final cameraId = _cameraId;
    if (cameraId == null) return;
    final session = ++_pollSession;
    setState(() {
      _capturing = true;
      _capture = null;
      _imageBytes = null;
      _boxes = const [];
      _error = null;
    });
    try {
      final settings = context.read<SettingsProvider>().settings;
      final token = await _readToken(settings);
      if (!mounted || session != _pollSession) return;
      _captureRequestId ??= generateRequestId();
      var capture = await _api.requestCapture(
        settings,
        cameraId,
        bearerToken: token,
        requestId: _captureRequestId,
      );
      if (!mounted || session != _pollSession) return;
      setState(() {
        _capture = capture;
        _captureRequestId = null;
      });
      for (var attempt = 0; !capture.state.isFinal && attempt < 60; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!mounted || session != _pollSession) return;
        capture = await _api.fetchCapture(
          settings,
          capture.captureId,
          bearerToken: token,
        );
        if (!mounted || session != _pollSession) return;
        setState(() => _capture = capture);
      }
      if (capture.state == ReferenceCaptureState.ready) {
        await _loadCaptureImage(settings, capture, session, token);
      } else if (!capture.state.isFinal) {
        _showMessage(
          '촬영 상태: ${statusLabel(capture.state.name)}. 새로고침으로 계속 확인해 주세요.',
        );
      } else if (capture.error.isNotEmpty) {
        _showMessage(capture.error, error: true);
      }
    } catch (error) {
      if (mounted && session == _pollSession) {
        _showMessage(_describeError(error), error: true);
      }
    } finally {
      if (mounted && session == _pollSession) {
        setState(() => _capturing = false);
      }
    }
  }

  Future<void> _refreshCapture() async {
    final current = _capture;
    if (current == null) return;
    final session = ++_pollSession;
    setState(() => _capturing = true);
    try {
      final settings = context.read<SettingsProvider>().settings;
      final token = await _readToken(settings);
      if (!mounted || session != _pollSession) return;
      final capture = await _api.fetchCapture(
        settings,
        current.captureId,
        bearerToken: token,
      );
      if (!mounted || session != _pollSession) return;
      setState(() => _capture = capture);
      if (capture.state == ReferenceCaptureState.ready) {
        await _loadCaptureImage(settings, capture, session, token);
      } else if (capture.error.isNotEmpty) {
        _showMessage(capture.error, error: true);
      }
    } catch (error) {
      if (mounted && session == _pollSession) {
        _showMessage(_describeError(error), error: true);
      }
    } finally {
      if (mounted && session == _pollSession) {
        setState(() => _capturing = false);
      }
    }
  }

  Future<void> _loadCaptureImage(
    AppSettings settings,
    ReferenceCapture capture,
    int session,
    String token,
  ) async {
    final image = capture.image;
    if (image == null) return;
    final bytes = await _api.fetchImage(settings, image, bearerToken: token);
    if (!mounted || session != _pollSession) return;
    setState(() {
      _editorImage = _EditableReferenceImage(
        imageId: image.imageId,
        imageUrl: image.url,
        cameraId: image.cameraId,
        width: image.width,
        height: image.height,
      );
      _imageBytes = bytes;
      _boxes = const [];
      _revisionRequestId = null;
    });
  }

  Future<void> _saveRevision() async {
    if (_saving) return;
    final session = _pollSession;
    final image = _editorImage;
    final className = _className;
    if (image == null || className == null || _boxes.isEmpty) return;
    if (_boxes.any((box) => !box.isValidFor(image.width, image.height))) {
      _showMessage('원본 이미지 범위를 벗어난 박스가 있습니다.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final settings = context.read<SettingsProvider>().settings;
      final token = await _readToken(settings);
      if (!mounted || session != _pollSession) return;
      _revisionRequestId ??= generateRequestId();
      final revision = await _api.createRevision(
        settings,
        baseRevisionId: _baseRevisionId,
        className: className,
        imageId: image.imageId,
        boxes: _boxes,
        bearerToken: token,
        requestId: _revisionRequestId,
      );
      if (!mounted || session != _pollSession) return;
      setState(() {
        _baseRevisionId = revision.revisionId;
        _revisionRequestId = null;
        _revisions = [
          ReferenceRevisionSummary(
            revisionId: revision.revisionId,
            baseRevisionId: revision.baseRevisionId,
            createdAtMs: revision.createdAtMs,
          ),
          ..._revisions.where((item) => item.revisionId != revision.revisionId),
        ];
      });
      _showMessage('${_displayId(revision.revisionId)} 저장 완료.');
      unawaited(_reload());
    } catch (error) {
      if (mounted && session == _pollSession) {
        _showMessage(_describeError(error), error: true);
      }
    } finally {
      if (mounted && session == _pollSession) {
        setState(() => _saving = false);
      }
    }
  }

  void _removeBox(int index) {
    _setBoxes([
      for (var i = 0; i < _boxes.length; i++)
        if (i != index) _boxes[i],
    ]);
  }

  void _setBoxes(List<ReferenceBox> boxes) {
    setState(() {
      _boxes = boxes;
      _revisionRequestId = null;
    });
  }

  Future<List<ReferenceRevisionSummary>> _fetchAllRevisions(
    AppSettings settings,
    String token,
  ) async {
    final revisions = <ReferenceRevisionSummary>[];
    String? cursor;
    do {
      final page = await _api.fetchRevisions(
        settings,
        bearerToken: token,
        limit: 100,
        cursor: cursor,
      );
      revisions.addAll(page.revisions);
      cursor = page.nextCursor;
    } while (cursor != null);
    return List.unmodifiable(revisions);
  }

  Future<void> _selectBaseRevision(String? revisionId) async {
    if (revisionId == null) return;
    final session = ++_pollSession;
    _reloadGeneration++;
    setState(() {
      _baseRevisionId = revisionId;
      _revisionRequestId = null;
      _jobs.buildRequestId = null;
      _loading = true;
    });
    try {
      final settings = context.read<SettingsProvider>().settings;
      final token = await _readToken(settings);
      if (!mounted || session != _pollSession) return;
      final revision = await _api.fetchRevision(
        settings,
        revisionId,
        bearerToken: token,
      );
      if (mounted && session == _pollSession && _baseRevisionId == revisionId) {
        setState(() => _currentRevision = revision);
      }
    } catch (error) {
      if (mounted && session == _pollSession) {
        _showMessage(_describeError(error), error: true);
      }
    } finally {
      if (mounted && session == _pollSession) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openRevisionEntry(ReferenceRevisionEntry entry) async {
    final session = ++_pollSession;
    _reloadGeneration++;
    setState(() => _loading = true);
    try {
      final settings = context.read<SettingsProvider>().settings;
      final token = await _readToken(settings);
      if (!mounted || session != _pollSession) return;
      final bytes = await _api.fetchImageUrl(
        settings,
        entry.imageUrl,
        bearerToken: token,
      );
      if (!mounted || session != _pollSession) return;
      final cameraId = _cameraForClass(entry.className);
      setState(() {
        _cameraId = cameraId;
        _className = entry.className;
        _capture = null;
        _editorImage = _EditableReferenceImage(
          imageId: entry.imageId,
          imageUrl: entry.imageUrl,
          cameraId: cameraId,
          width: entry.width,
          height: entry.height,
        );
        _imageBytes = bytes;
        _boxes = entry.boxes;
        _revisionRequestId = null;
      });
    } catch (error) {
      if (mounted && session == _pollSession) {
        _showMessage(_describeError(error), error: true);
      }
    } finally {
      if (mounted && session == _pollSession) {
        setState(() => _loading = false);
      }
    }
  }

  String _cameraForClass(String className) {
    for (final entry
        in _status?.cameraClasses.entries ??
            const <MapEntry<String, List<String>>>[]) {
      if (entry.value.contains(className)) return entry.key;
    }
    throw FormatException('$className 분류에 연결된 카메라가 없습니다');
  }

  Future<void> _confirmModelBuild() async {
    final session = _pollSession;
    final revisionId = _baseRevisionId;
    if (revisionId == null) return;
    var confirmed = false;
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('후보 모델을 빌드하시겠습니까?'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: revisionId,
                  child: Text('빌드 기준: ${_displayId(revisionId)}'),
                ),
                const SizedBox(height: 12),
                const Text(
                  '모델 내보내기·빌드·검증 중에는 검사 요청과 실시간 검출이 일시 중지됩니다. 빌드가 끝나면 현재 모델로 복원됩니다.',
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: confirmed,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('유지보수를 위한 일시 중지에 동의합니다.'),
                  onChanged: (value) =>
                      setDialogState(() => confirmed = value ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: confirmed
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: const Text('동의하고 빌드'),
            ),
          ],
        ),
      ),
    );
    if (mounted && session == _pollSession && approved == true) {
      await _jobs.startBuild(revisionId);
    }
  }

  Future<void> _confirmActivation(ReferenceModel model) async {
    final session = _pollSession;
    final current = _status?.activeModelId;
    if (current == null || current == model.modelId) return;
    var reviewed = false;
    final activeRecord = _models
        .where((item) => item.modelId == current)
        .firstOrNull;
    final restoring =
        activeRecord != null && model.createdAtMs < activeRecord.createdAtMs;
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(restoring ? '이전 모델로 복원하시겠습니까?' : '후보 모델을 적용하시겠습니까?'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('현재: ${_modelLabel(current)}'),
                Text('요청: ${_modelLabel(model.modelId)}'),
                const SizedBox(height: 12),
                const Text(
                  '기술 검증이 생산 정확도를 보증하지는 않습니다. 적용 중에는 검사가 일시 중지되고, 로딩에 실패하면 장비가 현재 모델로 복원할 수 있습니다.',
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: reviewed,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('양품·불량 샘플을 확인했고 모델 변경에 동의합니다.'),
                  onChanged: (value) =>
                      setDialogState(() => reviewed = value ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: reviewed
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: Text(restoring ? '동의하고 복원' : '동의하고 적용'),
            ),
          ],
        ),
      ),
    );
    if (mounted && session == _pollSession && approved == true) {
      await _jobs.startActivation(model, current);
    }
  }

  String _modelLabel(String id) {
    final model = _models.where((model) => model.modelId == id).firstOrNull;
    return model == null
        ? _displayId(id)
        : '${_displayId(id)} · ${_displayId(model.referenceRevisionId)}';
  }

  String _displayId(String id) {
    final match = RegExp(
      r'^(model|refrev)_([0-9a-f]{32}|initial)$',
    ).firstMatch(id);
    if (match == null) return id;
    final kind = match[1] == 'model' ? '모델' : '개정본';
    final suffix = match[2]!;
    return '$kind ${suffix == 'initial' ? suffix : suffix.substring(0, 8)}';
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<String> _readToken(AppSettings settings) async {
    final token = await context.read<ReferenceCredentialProvider>().readToken(
      settings,
    );
    if (token == null) {
      throw StateError('관리 토큰이 설정되지 않았습니다.');
    }
    return token;
  }
}

enum _ReferencePage { references, models }

class _EditableReferenceImage {
  const _EditableReferenceImage({
    required this.imageId,
    required this.imageUrl,
    required this.cameraId,
    required this.width,
    required this.height,
  });

  final String imageId;
  final String imageUrl;
  final String cameraId;
  final int width;
  final int height;
}

class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.title,
    required this.id,
    required this.state,
    required this.error,
    this.detail,
    this.onRefresh,
  });

  final String title;
  final String id;
  final String state;
  final String error;
  final String? detail;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                _StateChip(state: state),
                if (onRefresh != null) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: '이 작업 상태 계속 확인',
                    onPressed: onRefresh,
                    icon: const Icon(Icons.sync, size: 20),
                  ),
                ],
              ],
            ),
            SelectableText(
              id,
              style: const TextStyle(fontFamily: 'NotoSansKR', fontSize: 12),
            ),
            if (detail != null) ...[
              const SizedBox(height: 5),
              Text(detail!, style: TextStyle(color: scheme.onSurfaceVariant)),
            ],
            if (error.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(error, style: TextStyle(color: scheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}

class ReferenceBoxEditor extends StatefulWidget {
  const ReferenceBoxEditor({
    super.key,
    required this.imageBytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.boxes,
    required this.onBoxesChanged,
  });

  final Uint8List imageBytes;
  final int imageWidth;
  final int imageHeight;
  final List<ReferenceBox> boxes;
  final ValueChanged<List<ReferenceBox>> onBoxesChanged;

  @override
  State<ReferenceBoxEditor> createState() => _ReferenceBoxEditorState();
}

class _ReferenceBoxEditorState extends State<ReferenceBoxEditor> {
  Offset? _dragStart;
  Offset? _dragCurrent;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = _containScale(
          Size(widget.imageWidth.toDouble(), widget.imageHeight.toDouble()),
          Size(constraints.maxWidth, constraints.maxHeight),
        );
        final displaySize = Size(
          widget.imageWidth * scale,
          widget.imageHeight * scale,
        );
        return ZoomableViewport(
          editable: true,
          child: Center(
            child: SizedBox.fromSize(
              size: displaySize,
              child: GestureDetector(
                dragStartBehavior: DragStartBehavior.down,
                behavior: HitTestBehavior.opaque,
                onPanStart: widget.boxes.length >= 64
                    ? null
                    : (details) {
                        setState(() {
                          _dragStart = _clamp(
                            details.localPosition,
                            displaySize,
                          );
                          _dragCurrent = _dragStart;
                        });
                      },
                onPanUpdate: widget.boxes.length >= 64
                    ? null
                    : (details) => setState(
                        () => _dragCurrent = _clamp(
                          details.localPosition,
                          displaySize,
                        ),
                      ),
                onPanCancel: _cancelDrag,
                onPanEnd: (_) => _finishDrag(scale),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(
                      widget.imageBytes,
                      fit: BoxFit.fill,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                    ),
                    CustomPaint(
                      painter: _ReferenceBoxesPainter(
                        boxes: widget.boxes,
                        scale: scale,
                        pending: _pendingRect,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Rect? get _pendingRect {
    final start = _dragStart;
    final current = _dragCurrent;
    if (start == null || current == null) return null;
    return Rect.fromPoints(start, current);
  }

  void _finishDrag(double scale) {
    final rect = _pendingRect;
    _cancelDrag();
    if (rect == null || rect.width < 3 || rect.height < 3) return;
    final box = ReferenceBox(
      (rect.left / scale).roundToDouble(),
      (rect.top / scale).roundToDouble(),
      (rect.right / scale).roundToDouble(),
      (rect.bottom / scale).roundToDouble(),
    );
    if (!box.isValidFor(widget.imageWidth, widget.imageHeight)) return;
    widget.onBoxesChanged(List.unmodifiable([...widget.boxes, box]));
  }

  void _cancelDrag() {
    if (_dragStart == null && _dragCurrent == null) return;
    setState(() {
      _dragStart = null;
      _dragCurrent = null;
    });
  }
}

class _ReferenceBoxesPainter extends CustomPainter {
  const _ReferenceBoxesPainter({
    required this.boxes,
    required this.scale,
    required this.pending,
  });

  final List<ReferenceBox> boxes;
  final double scale;
  final Rect? pending;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = const Color(0x33FF7A2F);
    final stroke = Paint()
      ..color = const Color(0xFFFF7A2F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final label = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < boxes.length; i++) {
      final box = boxes[i];
      final rect = Rect.fromLTRB(
        box.x1 * scale,
        box.y1 * scale,
        box.x2 * scale,
        box.y2 * scale,
      );
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, stroke);
      label.text = TextSpan(
        text: '${i + 1}',
        style: const TextStyle(
          color: Colors.white,
          backgroundColor: Color(0xDDFF7A2F),
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );
      label.layout();
      label.paint(canvas, Offset(rect.left + 2, rect.top + 2));
    }
    if (pending != null) {
      canvas.drawRect(pending!, fill);
      canvas.drawRect(pending!, stroke);
    }
  }

  @override
  bool shouldRepaint(_ReferenceBoxesPainter oldDelegate) =>
      oldDelegate.boxes != boxes ||
      oldDelegate.scale != scale ||
      oldDelegate.pending != pending;
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final String state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      'RUNNING' || 'READY' || 'ACTIVE' || 'SUCCEEDED' => Colors.green,
      'MAINTENANCE' ||
      'QUEUED' ||
      'CAPTURING' ||
      'PREPARING' ||
      'EXPORTING' ||
      'BUILDING' ||
      'VALIDATING' ||
      'DRAINING' ||
      'LOADING' => Colors.orange,
      'ERROR' || 'FAILED' || 'INTERRUPTED' || 'ROLLED_BACK' => Colors.red,
      _ => Colors.blueGrey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        statusLabel(state),
        style: TextStyle(
          color: color.shade200,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('다시 시도'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

double _containScale(Size image, Size available) {
  if (image.width <= 0 ||
      image.height <= 0 ||
      available.width <= 0 ||
      available.height <= 0) {
    return 1;
  }
  return (available.width / image.width).clamp(
    0.000001,
    available.height / image.height,
  );
}

Offset _clamp(Offset point, Size size) =>
    Offset(point.dx.clamp(0, size.width), point.dy.clamp(0, size.height));

String _classLabel(String className) => switch (className) {
  'stud' => 'Stud (stud)',
  'bolt_head' => 'Bolt Head (bolt_head)',
  'nut' => 'Nut (nut)',
  'nut_hole' => 'Nut Hole (nut_hole)',
  'plain_hole' => 'Plain Hole (plain_hole)',
  _ => className,
};

String _activationStateLabel(ModelActivationState state) => switch (state) {
  ModelActivationState.rolledBack => 'ROLLED_BACK',
  _ => state.name.toUpperCase(),
};

String _formatTimestamp(int milliseconds) {
  final value = DateTime.fromMillisecondsSinceEpoch(
    milliseconds,
    isUtc: true,
  ).toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}

String _describeError(Object error) => switch (error) {
  RemoteReferenceApiException() => error.message,
  TimeoutException() => '장비 응답 시간이 초과되었습니다.',
  _ => error.toString(),
};
