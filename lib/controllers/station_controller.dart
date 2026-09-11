import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/app_settings.dart';
import '../models/station_viewer_layout.dart';
import '../services/remote_capture_api_service.dart';

class StationController extends ChangeNotifier {
  StationController({
    required this.api,
    required this.selectCameras,
    required this.persistLayout,
  });
  final RemoteCaptureApiService api;
  final void Function(List<String>? ids) selectCameras;
  final Future<void> Function(StationViewerLayout layout, List<String> slots)
  persistLayout;
  bool active = false, sourceBusy = false, undistortionBusy = false;
  StationCaptureStatus? status;
  StationViewerSource? source;
  StationViewerLayout layout = StationViewerLayout.oneByOne;
  List<String> slots = const [''];
  final Map<String, StationCaptureResult> _cycles = {};
  Map<String, StationCaptureResult> get cycles => Map.unmodifiable(_cycles);
  String? selectedCycleId;
  String? _operationError, _pollError;
  String? get error => _operationError ?? _pollError;
  set error(String? value) {
    _operationError = value;
  }

  bool _suspended = true;
  int session = 0;
  Timer? _timer;
  bool _disposed = false;
  int? _pollingSession;
  AppSettings? _settings;
  String? _endpoint;
  bool _current(int value) =>
      !_disposed && active && !_suspended && session == value;

  void restoreLayout(AppSettings settings) {
    layout = settings.stationViewerLayout;
    slots = resizeStationCameraSlots(layout, settings.stationViewerCameraSlots);
  }

  Future<void> initialize(AppSettings settings) async {
    final generation = ++session;
    _timer?.cancel();
    final endpoint = settings.buildApiUri('capture').toString();
    if (_endpoint != endpoint) {
      _cycles.clear();
      selectedCycleId = null;
    }
    _endpoint = endpoint;
    _settings = settings;
    active = true;
    _suspended = false;
    _pollError = null;
    sourceBusy = undistortionBusy = false;
    status = null;
    source = null;
    error = null;
    selectCameras(const []);
    notifyListeners();
    StationCaptureStatus? nextStatus;
    StationViewerSource? nextSource;
    final errors = <String>[];
    await Future.wait([
      () async {
        try {
          nextStatus = await api.fetchStationStatus(settings);
        } catch (e) {
          if (_current(generation)) _pollError = '상태 조회 실패: $e';
        }
      }(),
      () async {
        try {
          nextSource = await api.fetchViewerSource(settings);
        } catch (e) {
          errors.add('미리보기 조회 실패: $e');
        }
      }(),
    ]);
    if (!_current(generation)) return;
    status = nextStatus;
    source = nextSource;
    error = errors.isEmpty ? null : errors.join(' · ');
    if (nextSource != null) {
      _confirmSource(nextSource!, layout, slots);
      await _persist(generation);
    }
    if (!_current(generation)) return;
    notifyListeners();
    unawaited(poll());
    _timer = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => unawaited(poll()),
    );
  }

  void suspend() {
    session++;
    _suspended = true;
    _timer?.cancel();
    sourceBusy = undistortionBusy = false;
    status = null;
    source = null;
  }

  void leave() {
    suspend();
    active = false;
    _cycles.clear();
    selectedCycleId = error = _endpoint = null;
    _settings = null;
    selectCameras(null);
    notifyListeners();
  }

  Future<void> poll() async {
    final generation = session;
    final settings = _settings;
    if (!_current(generation) ||
        settings == null ||
        _pollingSession == generation) {
      return;
    }
    _pollingSession = generation;
    StationCaptureStatus? nextStatus;
    String? nextError;
    final results = <String, StationCaptureResult>{};
    final pending = _cycles.values.where((r) => !r.state.isFinal).toList();
    try {
      try {
        nextStatus = await api.fetchStationStatus(settings);
      } catch (e) {
        nextError = '장비 상태 조회 실패: $e';
      }
      for (final result in pending) {
        if (!_current(generation)) return;
        try {
          results[result.cycleId] = await api.fetchStationResult(
            settings,
            result.cycleId,
          );
        } on RemoteCaptureApiException catch (e) {
          if (e.statusCode == 404) {
            results[result.cycleId] = StationCaptureResult.expired(
              result.cycleId,
            );
          } else {
            nextError ??= '검사 결과 조회 실패: $e';
          }
        } catch (e) {
          nextError ??= '검사 결과 조회 실패: $e';
        }
      }
    } finally {
      if (_pollingSession == generation) _pollingSession = null;
    }
    if (!_current(generation)) return;
    status = nextStatus;
    _cycles.addAll(results);
    _pollError = nextError;
    _trim();
    notifyListeners();
  }

  void _trim() {
    while (_cycles.length > 32) {
      final removable = _cycles.entries
          .where((e) => e.value.state.isFinal && e.key != selectedCycleId)
          .firstOrNull;
      if (removable == null) return;
      _cycles.remove(removable.key);
    }
  }

  String cameraForSlot(int slot) => slot < slots.length ? slots[slot] : '';

  Future<void> changeLayout(
    StationViewerLayout value,
    List<String> available,
  ) async {
    final next = resizeStationCameraSlots(value, slots);
    final selected = next.where((id) => id.isNotEmpty).toSet();
    for (var i = 0; i < next.length; i++) {
      if (next[i].isNotEmpty) continue;
      for (final id in available) {
        if (selected.add(id)) {
          next[i] = id;
          break;
        }
      }
    }
    await setSources(value, next);
  }

  Future<void> changeCamera(int slot, String id) async {
    final next = resizeStationCameraSlots(layout, slots);
    final previousSlot = id.isEmpty ? -1 : next.indexOf(id);
    if (previousSlot >= 0 && previousSlot != slot) {
      next[previousSlot] = next[slot];
    }
    next[slot] = id;
    await setSources(layout, next);
  }

  Future<void> setSources(
    StationViewerLayout requestedLayout,
    List<String> requestedSlots,
  ) async {
    if (sourceBusy || !_current(session) || _settings == null) return;
    final generation = session;
    final settings = _settings!;
    sourceBusy = true;
    error = null;
    notifyListeners();
    try {
      final confirmed = await api.setViewerSources(
        settings,
        requestedSlots.where((s) => s.isNotEmpty).toList(),
      );
      if (!_current(generation)) return;
      _confirmSource(confirmed, requestedLayout, requestedSlots);
      await _persist(generation);
    } catch (failure) {
      if (!_current(generation)) return;
      source = null;
      selectCameras(const []);
      error = '카메라 선택 실패: $failure';
      // 서버의 확인 응답만 반영하며, 확인 실패 시 이전 선택을 실제 상태로 가정하지 않습니다.
      try {
        final actual = await api.fetchViewerSource(settings);
        if (!_current(generation)) return;
        _confirmSource(actual, requestedLayout, requestedSlots);
        await _persist(generation);
      } catch (readFailure) {
        if (!_current(generation)) return;
        error = '카메라 선택 실패: $failure · 실제 선택 확인 실패: $readFailure';
      }
    } finally {
      if (_current(generation)) {
        sourceBusy = false;
        notifyListeners();
      }
    }
  }

  void _confirmSource(
    StationViewerSource confirmed,
    StationViewerLayout requestedLayout,
    List<String> requestedSlots,
  ) {
    source = confirmed;
    layout = requestedLayout.accommodate(confirmed.cameraIds.length);
    slots = reconcileStationCameraSlots(
      layout: layout,
      preferredSlots: requestedSlots,
      activeCameraIds: confirmed.cameraIds,
    );
    selectCameras(confirmed.cameraIds);
  }

  Future<void> _persist(int generation) async {
    try {
      await persistLayout(layout, slots);
    } catch (failure) {
      if (_current(generation)) error = '화면 배치 저장 실패: $failure';
    }
  }

  Future<bool> capture(StationCaptureTarget target) async {
    final generation = session;
    final current = status;
    if (!_current(generation) ||
        current == null ||
        !current.ready ||
        !current.captureTargets.contains(target)) {
      throw StateError('현재 장비에서 사용할 수 없는 촬영 대상입니다');
    }
    final accepted = await api.requestStationCapture(
      _settings!,
      target: target,
    );
    if (!_current(generation)) return false;
    if (!accepted.accepted || accepted.cycleId.isEmpty) {
      throw StateError(
        accepted.error.isEmpty ? '장비가 촬영 요청을 거부했습니다' : accepted.error,
      );
    }
    _cycles[accepted.cycleId] = StationCaptureResult.pending(accepted.cycleId);
    selectedCycleId = accepted.cycleId;
    error = null;
    _trim();
    notifyListeners();
    unawaited(poll());
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    suspend();
    super.dispose();
  }
}
