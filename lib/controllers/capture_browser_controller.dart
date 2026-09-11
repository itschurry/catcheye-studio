import 'package:flutter/foundation.dart';
import '../models/app_settings.dart';
import '../services/remote_capture_api_service.dart';
import '../services/remote_capture_image_api_service.dart';

class CaptureBrowserController extends ChangeNotifier {
  CaptureBrowserController({
    RemoteCaptureImageApiService? api,
    RemoteCaptureApiService? captureApi,
  }) : _api = api ?? RemoteCaptureImageApiService(),
       _captureApi = captureApi ?? RemoteCaptureApiService(),
       _ownsApi = api == null,
       _ownsCaptureApi = captureApi == null;
  final RemoteCaptureImageApiService _api;
  final RemoteCaptureApiService _captureApi;
  final bool _ownsApi, _ownsCaptureApi;
  AppSettings? _settings;
  int _generation = 0, _deviceGeneration = 0;
  bool _disposed = false;
  List<CaptureDateSummary> dates = const [];
  List<CaptureImageItem> images = const [];
  CaptureStorageInfo? storage;
  CaptureImageItem? selectedImage;
  Uint8List? imageBytes;
  String? selectedDate, error;
  bool loading = false, imageLoading = false, captureBusy = false;

  bool _current(int generation) => !_disposed && generation == _generation;

  bool bind(AppSettings settings) {
    final changed =
        _settings?.buildApiUri('captures') != settings.buildApiUri('captures');
    _settings = settings;
    if (!changed) return false;
    _generation++;
    _deviceGeneration++;
    dates = const [];
    images = const [];
    storage = null;
    selectedImage = null;
    imageBytes = null;
    selectedDate = error = null;
    loading = true;
    imageLoading = captureBusy = false;
    return true;
  }

  Future<void> reload() async {
    final generation = ++_generation;
    final settings = _settings!;
    final previousFilename = selectedImage?.filename;
    loading = true;
    imageLoading = false;
    error = null;
    notifyListeners();
    try {
      final response = await _api.fetchDates(settings);
      if (!_current(generation)) return;
      dates = response.dates;
      storage = response.storage;
      selectedDate = dates.any((date) => date.date == selectedDate)
          ? selectedDate
          : dates.firstOrNull?.date;
      if (selectedDate != null) {
        await _loadImages(
          settings,
          selectedDate!,
          generation,
          previousFilename,
        );
      } else {
        images = const [];
        selectedImage = null;
        imageBytes = null;
        loading = false;
        notifyListeners();
      }
    } catch (failure) {
      _fail(generation, failure);
    }
  }

  Future<void> loadImages(String date) async {
    final generation = ++_generation;
    selectedDate = date;
    loading = true;
    imageLoading = false;
    error = null;
    notifyListeners();
    try {
      await _loadImages(_settings!, date, generation, null);
    } catch (failure) {
      _fail(generation, failure);
    }
  }

  Future<void> _loadImages(
    AppSettings settings,
    String date,
    int generation,
    String? preferredFilename,
  ) async {
    final list = await _api.fetchImages(settings, date: date);
    if (!_current(generation)) return;
    images = list.items;
    selectedDate = date;
    selectedImage =
        images
            .where((item) => item.filename == preferredFilename)
            .firstOrNull ??
        images.firstOrNull;
    imageBytes = null;
    loading = false;
    imageLoading = selectedImage != null;
    notifyListeners();
    if (selectedImage != null) {
      await _loadImage(settings, selectedImage!, generation);
    }
  }

  Future<void> selectImage(CaptureImageItem image) async {
    final generation = ++_generation;
    selectedImage = image;
    imageBytes = null;
    loading = false;
    imageLoading = true;
    error = null;
    notifyListeners();
    try {
      await _loadImage(_settings!, image, generation);
    } catch (failure) {
      _fail(generation, failure);
    }
  }

  Future<void> _loadImage(
    AppSettings settings,
    CaptureImageItem image,
    int generation,
  ) async {
    final bytes = await _api.fetchImageBytes(settings, image);
    if (!_current(generation)) return;
    imageBytes = bytes;
    imageLoading = false;
    notifyListeners();
  }

  Future<void> showLatest() async {
    final generation = ++_generation;
    final settings = _settings!;
    loading = true;
    imageLoading = false;
    error = null;
    notifyListeners();
    try {
      final latest = await _api.fetchLatest(settings);
      if (!_current(generation)) return;
      await _loadImages(settings, latest.date, generation, latest.filename);
    } catch (failure) {
      _fail(generation, failure);
    }
  }

  Future<void> captureAndShowLatest() async {
    if (captureBusy) return;
    final device = _deviceGeneration;
    captureBusy = true;
    notifyListeners();
    try {
      await _captureApi.requestCapture(_settings!);
      if (_disposed || device != _deviceGeneration) return;
      await showLatest();
    } catch (failure) {
      if (!_disposed && device == _deviceGeneration) error = '$failure';
    } finally {
      if (!_disposed && device == _deviceGeneration) {
        captureBusy = false;
        notifyListeners();
      }
    }
  }

  void _fail(int generation, Object failure) {
    if (!_current(generation)) return;
    loading = imageLoading = false;
    error = '$failure';
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    if (_ownsApi) _api.close();
    if (_ownsCaptureApi) _captureApi.close();
    super.dispose();
  }
}
