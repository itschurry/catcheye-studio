import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:catcheye_studio/controllers/model_jobs_controller.dart';
import 'package:catcheye_studio/models/app_settings.dart';
import 'package:catcheye_studio/services/remote_reference_api_service.dart';

class JobsApi extends RemoteReferenceApiService {
  int requests = 0;
  final response = Completer<ModelBuild>();
  @override
  Future<ModelBuild> requestModelBuild(
    AppSettings settings, {
    required String referenceRevisionId,
    required String bearerToken,
    String? requestId,
  }) {
    requests++;
    return response.future;
  }
}

void main() {
  test(
    'device change while credentials load prevents sending the old command',
    () async {
      final api = JobsApi();
      final token = Completer<String>();
      final messages = <String>[];
      final controller = ModelJobsController(
        api: api,
        readToken: (_) => token.future,
        showMessage: (message, {bool error = false}) => messages.add(message),
        refresh: () async {},
        displayId: (id) => id,
        modelLabel: (id) => id,
      )..bind(AppSettings());
      addTearDown(controller.dispose);
      addTearDown(api.close);
      final pending = controller.startBuild('revision-1');
      controller.bind(AppSettings(apiBasePath: '/other'));
      token.complete('test-token');
      await pending;
      expect(api.requests, 0);
      expect(controller.busy, isFalse);
      expect(messages, isEmpty);
    },
  );
  test(
    'duplicate start is suppressed and late failure cannot affect a new device',
    () async {
      final api = JobsApi();
      final messages = <String>[];
      final controller = ModelJobsController(
        api: api,
        readToken: (_) async => 'test-token',
        showMessage: (message, {bool error = false}) => messages.add(message),
        refresh: () async {},
        displayId: (id) => id,
        modelLabel: (id) => id,
      )..bind(AppSettings());
      addTearDown(controller.dispose);
      addTearDown(api.close);
      final pending = controller.startBuild('revision-1');
      await Future<void>.delayed(Duration.zero);
      await controller.startBuild('revision-1');
      expect(api.requests, 1);
      controller.bind(AppSettings(apiBasePath: '/other'));
      api.response.completeError(StateError('old failure'));
      await pending;
      expect(controller.build, isNull);
      expect(controller.buildRequestId, isNull);
      expect(controller.busy, isFalse);
      expect(messages, isEmpty);
    },
  );
}
