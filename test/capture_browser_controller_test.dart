import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:catcheye_studio/controllers/capture_browser_controller.dart';
import 'package:catcheye_studio/models/app_settings.dart';
import 'package:catcheye_studio/services/remote_capture_image_api_service.dart';

class ImageApi extends RemoteCaptureImageApiService {
  final images = <String, Completer<Uint8List>>{};
  @override
  Future<Uint8List> fetchImageBytes(
    AppSettings settings,
    CaptureImageItem image,
  ) => (images[image.filename] = Completer<Uint8List>()).future;
}

CaptureImageItem item(String id) => CaptureImageItem(
  date: '2026-09-11',
  filename: id,
  capturedAt: '',
  sequence: 0,
  sizeBytes: 1,
  width: 1,
  height: 1,
  url: '/$id',
);

void main() {
  late ImageApi api;
  late CaptureBrowserController controller;
  setUp(() {
    api = ImageApi();
    controller = CaptureBrowserController(api: api)..bind(AppSettings());
  });
  tearDown(() {
    controller.dispose();
    api.close();
  });
  test('late selected image cannot replace a newer selection', () async {
    final first = controller.selectImage(item('a'));
    final second = controller.selectImage(item('b'));
    api.images['b']!.complete(Uint8List.fromList([2]));
    await second;
    api.images['a']!.complete(Uint8List.fromList([1]));
    await first;
    expect(controller.selectedImage!.filename, 'b');
    expect(controller.imageBytes, [2]);
    expect(controller.imageLoading, isFalse);
  });
  test('late failure cannot overwrite a successful newer selection', () async {
    final first = controller.selectImage(item('a'));
    final second = controller.selectImage(item('b'));
    api.images['b']!.complete(Uint8List.fromList([2]));
    await second;
    api.images['a']!.completeError(StateError('old device error'));
    await first;
    expect(controller.error, isNull);
    expect(controller.imageBytes, [2]);
  });
  test('API base path change invalidates pending image', () async {
    final pending = controller.selectImage(item('a'));
    expect(controller.bind(AppSettings(apiBasePath: '/other')), isTrue);
    api.images['a']!.complete(Uint8List.fromList([1]));
    await pending;
    expect(controller.imageBytes, isNull);
    expect(controller.selectedImage, isNull);
  });
}
