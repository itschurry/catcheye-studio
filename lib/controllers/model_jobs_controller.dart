import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/app_settings.dart';
import '../services/remote_reference_api_service.dart';
import '../widgets/status_label.dart';

class ModelJobsController extends ChangeNotifier {
  ModelJobsController({
    required this.api,
    required this.readToken,
    required this.showMessage,
    required this.refresh,
    required this.displayId,
    required this.modelLabel,
  });
  final RemoteReferenceApiService api;
  final Future<String> Function(AppSettings settings) readToken;
  final void Function(String message, {bool error}) showMessage;
  final Future<void> Function() refresh;
  final String Function(String id) displayId, modelLabel;
  ReferenceApiStatus? status;
  ModelBuild? build;
  ModelActivation? activation;
  String? buildRequestId, activationRequestId;
  bool busy = false;
  bool _disposed = false;
  bool get mounted => !_disposed;
  int _generation = 0;
  AppSettings? _settings;
  void bind(AppSettings settings) {
    if (_settings?.buildApiUri('model') != settings.buildApiUri('model')) {
      _generation++;
      status = null;
      build = null;
      activation = null;
      buildRequestId = activationRequestId = null;
      busy = false;
    }
    _settings = settings;
  }

  void _update(VoidCallback change) {
    change();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }

  Future<void> startBuild(String revisionId) async {
    if (busy || _disposed) return;
    final session = ++_generation;
    _update(() {
      busy = true;
      activation = null;
    });
    try {
      final settings = _settings!;
      final token = await readToken(settings);
      if (!mounted || session != _generation) return;
      buildRequestId ??= generateRequestId();
      final build = await api.requestModelBuild(
        settings,
        referenceRevisionId: revisionId,
        bearerToken: token,
        requestId: buildRequestId,
      );
      if (!mounted || session != _generation) return;
      _update(() {
        this.build = build;
        buildRequestId = null;
      });
      await _pollBuild(settings, token, build, session);
    } catch (error) {
      if (mounted && session == _generation) {
        showMessage(_describeError(error), error: true);
      }
    } finally {
      if (mounted && session == _generation) {
        _update(() => busy = false);
      }
    }
  }

  Future<void> resumeBuild() async {
    if (busy || _disposed) return;
    final build = this.build;
    if (build == null) return;
    final session = ++_generation;
    _update(() => busy = true);
    try {
      final settings = _settings!;
      final token = await readToken(settings);
      if (!mounted || session != _generation) return;
      await _pollBuild(settings, token, build, session);
    } catch (error) {
      if (mounted && session == _generation) {
        showMessage(_describeError(error), error: true);
      }
    } finally {
      if (mounted && session == _generation) {
        _update(() => busy = false);
      }
    }
  }

  Future<void> _pollBuild(
    AppSettings settings,
    String token,
    ModelBuild initial,
    int session,
  ) async {
    var build = initial;
    for (var attempt = 0; !build.state.isFinal && attempt < 1800; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted || session != _generation) return;
      build = await api.fetchModelBuild(
        settings,
        build.buildId,
        bearerToken: token,
      );
      if (!mounted || session != _generation) return;
      final status = await api.fetchStatus(settings, bearerToken: token);
      if (!mounted || session != _generation) return;
      _update(() {
        this.build = build;
        this.status = status;
      });
    }
    if (!mounted || session != _generation) return;
    if (build.state == ModelBuildState.succeeded) {
      showMessage(
        '${displayId(build.referenceRevisionId)} 빌드 완료. 후보 모델은 아직 적용되지 않았습니다.',
      );
    } else if (build.state.isFinal) {
      showMessage(
        build.error.isEmpty
            ? '모델 빌드: ${statusLabel(build.state.name)}.'
            : build.error,
        error: true,
      );
    } else {
      showMessage('빌드가 진행 중입니다. 새로고침으로 상태를 계속 확인해 주세요.');
    }
    await refresh();
  }

  Future<void> startActivation(
    ReferenceModel model,
    String expectedActiveModelId,
  ) async {
    if (busy || _disposed) return;
    final session = ++_generation;
    _update(() {
      busy = true;
      build = null;
    });
    try {
      final settings = _settings!;
      final token = await readToken(settings);
      if (!mounted || session != _generation) return;
      activationRequestId ??= generateRequestId();
      final activation = await api.requestModelActivation(
        settings,
        modelId: model.modelId,
        expectedActiveModelId: expectedActiveModelId,
        bearerToken: token,
        requestId: activationRequestId,
      );
      if (!mounted || session != _generation) return;
      _update(() {
        this.activation = activation;
        activationRequestId = null;
      });
      await _pollActivation(settings, token, activation, session);
    } on RemoteReferenceApiException catch (error) {
      if (mounted &&
          session == _generation &&
          error.code == 'ACTIVE_MODEL_CHANGED') {
        await refresh();
      }
      if (mounted && session == _generation) {
        showMessage(error.message, error: true);
      }
    } catch (error) {
      if (mounted && session == _generation) {
        showMessage(_describeError(error), error: true);
      }
    } finally {
      if (mounted && session == _generation) {
        _update(() => busy = false);
      }
    }
  }

  Future<void> resumeActivation() async {
    if (busy || _disposed) return;
    final activation = this.activation;
    if (activation == null) return;
    final session = ++_generation;
    _update(() => busy = true);
    try {
      final settings = _settings!;
      final token = await readToken(settings);
      if (!mounted || session != _generation) return;
      await _pollActivation(settings, token, activation, session);
    } catch (error) {
      if (mounted && session == _generation) {
        showMessage(_describeError(error), error: true);
      }
    } finally {
      if (mounted && session == _generation) {
        _update(() => busy = false);
      }
    }
  }

  Future<void> _pollActivation(
    AppSettings settings,
    String token,
    ModelActivation initial,
    int session,
  ) async {
    var activation = initial;
    for (
      var attempt = 0;
      !activation.state.isFinal && attempt < 300;
      attempt++
    ) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted || session != _generation) return;
      activation = await api.fetchModelActivation(
        settings,
        activation.activationId,
        bearerToken: token,
      );
      if (!mounted || session != _generation) return;
      final status = await api.fetchStatus(settings, bearerToken: token);
      if (!mounted || session != _generation) return;
      _update(() {
        this.activation = activation;
        this.status = status;
      });
    }
    if (!mounted || session != _generation) return;
    if (activation.state == ModelActivationState.succeeded) {
      showMessage('${modelLabel(activation.activeModelId)} 적용 완료.');
    } else if (activation.state == ModelActivationState.rolledBack) {
      showMessage(
        '적용에 실패해서 ${modelLabel(activation.activeModelId)}로 복원되었습니다.',
        error: true,
      );
    } else if (activation.state.isFinal) {
      showMessage(
        activation.error.isEmpty
            ? '모델 적용: ${statusLabel(activation.state.name)}.'
            : activation.error,
        error: true,
      );
    } else {
      showMessage('모델 적용 중입니다. 새로고침으로 상태를 계속 확인해 주세요.');
    }
    await refresh();
  }
}

String _describeError(Object error) => switch (error) {
  RemoteReferenceApiException() => error.message,
  TimeoutException() => '장비 응답 시간이 초과되었습니다.',
  _ => error.toString(),
};
