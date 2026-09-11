import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'package:catcheye_studio/main.dart' show AppShell;
import 'package:catcheye_studio/models/app_settings.dart';
import 'package:catcheye_studio/providers/reference_credential_provider.dart';
import 'package:catcheye_studio/providers/settings_provider.dart';
import 'package:catcheye_studio/screens/reference_images_screen.dart';
import 'package:catcheye_studio/services/frame_receiver_service.dart';
import 'package:catcheye_studio/services/reference_credential_store.dart';
import 'package:catcheye_studio/services/remote_reference_api_service.dart';

void main() {
  setUpAll(() async {
    MediaKit.ensureInitialized();
    await (FontLoader('NotoSansKR')
          ..addFont(rootBundle.load('assets/fonts/NotoSansCJKkr-Regular.otf'))
          ..addFont(rootBundle.load('assets/fonts/NotoSansCJKkr-Bold.otf')))
        .load();
  });

  testWidgets('reference screen shows revision examples and model review', (
    tester,
  ) async {
    final settings = AppSettings(
      detectorBaseUrl: 'http://station.test:8090',
      remoteDeviceKind: RemoteDeviceKind.inspection,
    );
    final backend = _MemoryCredentialBackend();
    final credentialStore = ReferenceCredentialStore(backend: backend);
    await credentialStore.writeToken(
      settings,
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => SettingsProvider(initialSettings: settings),
          ),
          ChangeNotifierProvider(
            create: (_) => ReferenceCredentialProvider(store: credentialStore),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            fontFamily: 'NotoSansKR',
          ),
          home: Scaffold(
            body: ReferenceImagesScreen(
              initialStatus: _FakeReferenceApi.status,
              api: _FakeReferenceApi(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.text('촬영 대상'), const Offset(0, -420));
    await tester.pumpAndSettle();
    expect(find.text('현재 기준 이미지'), findsOneWidget);
    expect(find.text('Stud (stud)'), findsOneWidget);

    await tester.tap(find.text('모델'));
    await tester.pumpAndSettle();

    expect(find.text('모델 initial'), findsWidgets);
    expect(find.text('기술 검증 통과'), findsOneWidget);
    expect(find.textContaining('기술 검증이 생산 품질'), findsOneWidget);
    expect(find.text('사용 중'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  for (final isPhone in [false, true]) {
    testWidgets('model source labels and full IDs (phone: $isPhone)', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(
        isPhone ? const Size(390, 844) : const Size(1200, 900),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const modelId = 'model_a0736e17fbb47392a713d57677751ccb';
      const revisionId = 'refrev_d446ad82781715d5b49204e878e3c20f';
      final api = _FakeReferenceApi(modelId: modelId, revisionId: revisionId);
      final settings = AppSettings(
        detectorBaseUrl: 'http://station.test:8090',
        remoteDeviceKind: RemoteDeviceKind.inspection,
      );
      final store = ReferenceCredentialStore(
        backend: _MemoryCredentialBackend(),
      );
      await store.writeToken(
        settings,
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => SettingsProvider(initialSettings: settings),
            ),
            ChangeNotifierProvider(
              create: (_) => ReferenceCredentialProvider(store: store),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(
              brightness: Brightness.dark,
              useMaterial3: true,
              fontFamily: 'NotoSansKR',
            ),
            home: Scaffold(
              body: ReferenceImagesScreen(
                isPhone: isPhone,
                initialStatus: _FakeReferenceApi.status,
                api: api,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('base-revision-$revisionId-1')),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('개정본 d446ad82'), findsWidgets);
      final revisionItem = tester
          .widgetList<DropdownMenuItem<String>>(
            find.byType(DropdownMenuItem<String>),
          )
          .where((item) => item.value == revisionId);
      expect(revisionItem, hasLength(1));

      await tester.tap(find.byIcon(Icons.model_training_outlined));
      await tester.pumpAndSettle();
      expect(find.text('모델 a0736e17'), findsWidgets);
      expect(find.text('기준: 개정본 d446ad82'), findsOneWidget);
      expect(find.text('기준: 개정본 d446ad82\n검증 완료'), findsOneWidget);
      expect(find.text('빌드 기준: 개정본 d446ad82'), findsOneWidget);
      expect(find.textContaining(modelId), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('전체 식별자'));
      await tester.pumpAndSettle();
      expect(
        find.text('모델 ID: $modelId\n기준 개정본 ID: $revisionId'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('선택한 개정본으로 빌드'));
      await tester.pumpAndSettle();
      expect(find.text('빌드 기준: 개정본 d446ad82'), findsNWidgets(2));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('동의하고 빌드'));
      await tester.pumpAndSettle();
      expect(api.requestedRevisionId, revisionId);
      expect(find.textContaining('개정본 d446ad82 빌드 완료'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reference toolbar fits a 390px phone viewport', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = AppSettings(
      detectorBaseUrl: 'http://station.test:8090',
      remoteDeviceKind: RemoteDeviceKind.inspection,
    );
    final credentialStore = ReferenceCredentialStore(
      backend: _MemoryCredentialBackend(),
    );
    await credentialStore.writeToken(
      settings,
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => SettingsProvider(initialSettings: settings),
          ),
          ChangeNotifierProvider(
            create: (_) => ReferenceCredentialProvider(store: credentialStore),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            fontFamily: 'NotoSansKR',
          ),
          home: Scaffold(
            body: ReferenceImagesScreen(
              isPhone: true,
              initialStatus: _FakeReferenceApi.status,
              api: _FakeReferenceApi(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('reference-page-selector')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('authorization failure stays visible as a management error', (
    tester,
  ) async {
    final settings = AppSettings(
      detectorBaseUrl: 'http://station.test:8090',
      remoteDeviceKind: RemoteDeviceKind.inspection,
    );
    final credentialStore = ReferenceCredentialStore(
      backend: _MemoryCredentialBackend(),
    );
    await credentialStore.writeToken(
      settings,
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => SettingsProvider(initialSettings: settings),
          ),
          ChangeNotifierProvider(
            create: (_) => ReferenceCredentialProvider(store: credentialStore),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            fontFamily: 'NotoSansKR',
          ),
          home: Scaffold(
            body: ReferenceImagesScreen(
              initialStatus: _FakeReferenceApi.status,
              api: _UnauthorizedReferenceApi(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Management token was rejected.'), findsOneWidget);
    expect(find.text('기준 이미지를 관리할 수 없습니다'), findsNothing);
  });

  testWidgets('reference screen state survives navigation to another tab', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = AppSettings(remoteDeviceKind: RemoteDeviceKind.inspection);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => SettingsProvider(initialSettings: settings),
          ),
          ChangeNotifierProvider(
            create: (_) => ReferenceCredentialProvider(
              store: ReferenceCredentialStore(
                backend: _MemoryCredentialBackend(),
              ),
            ),
          ),
          ChangeNotifierProvider(create: (_) => FrameReceiverService()),
        ],
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            fontFamily: 'NotoSansKR',
          ),
          home: const AppShell(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('기준 이미지'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final beforeNavigation = tester.element(
      find.byType(ReferenceImagesScreen, skipOffstage: false),
    );

    await tester.tap(find.text('뷰어'));
    await tester.pump();
    final whileHidden = tester.element(
      find.byType(ReferenceImagesScreen, skipOffstage: false),
    );
    expect(identical(whileHidden, beforeNavigation), isTrue);

    await tester.tap(find.text('기준 이미지'));
    await tester.pump();
    final afterNavigation = tester.element(
      find.byType(ReferenceImagesScreen, skipOffstage: false),
    );
    expect(identical(afterNavigation, beforeNavigation), isTrue);
  });
}

class _FakeReferenceApi extends RemoteReferenceApiService {
  _FakeReferenceApi({
    this.modelId = 'model_initial',
    this.revisionId = 'refrev_initial',
  });

  final String modelId;
  final String revisionId;
  String? requestedRevisionId;

  @override
  Future<ModelBuild> requestModelBuild(
    AppSettings settings, {
    required String referenceRevisionId,
    required String bearerToken,
    String? requestId,
  }) async {
    requestedRevisionId = referenceRevisionId;
    return ModelBuild(
      buildId: 'build_test',
      state: ModelBuildState.succeeded,
      referenceRevisionId: referenceRevisionId,
      candidateModelId: modelId,
      validation: null,
      error: '',
      createdAtMs: 1788415200000,
    );
  }

  static const status = ReferenceApiStatus(
    apiVersion: 1,
    capabilities: ReferenceCapabilities(
      referenceCapture: true,
      referenceRevisions: true,
      modelBuild: true,
      modelActivation: true,
    ),
    deviceState: 'RUNNING',
    activeModelId: 'model_initial',
    cameraClasses: {
      'stud_camera': ['stud'],
    },
  );

  @override
  void close() {}

  @override
  Future<ReferenceApiStatus> fetchStatus(
    AppSettings settings, {
    required String bearerToken,
  }) async => status;

  @override
  Future<ReferenceRevisionList> fetchRevisions(
    AppSettings settings, {
    required String bearerToken,
    int limit = 20,
    String? cursor,
  }) async => ReferenceRevisionList(
    revisions: [
      ReferenceRevisionSummary(
        revisionId: revisionId,
        baseRevisionId: null,
        createdAtMs: 1788415200000,
      ),
    ],
    nextCursor: null,
  );

  @override
  Future<ReferenceRevision> fetchRevision(
    AppSettings settings,
    String revisionId, {
    required String bearerToken,
  }) async => ReferenceRevision(
    revisionId: revisionId,
    baseRevisionId: null,
    createdAtMs: 1788415200000,
    entries: const [
      ReferenceRevisionEntry(
        className: 'stud',
        imageId: 'img_initial',
        imageUrl: '/api/reference/images/img_initial',
        width: 1280,
        height: 800,
        boxes: [ReferenceBox(100, 100, 300, 400)],
        contextRatio: 0.1,
      ),
    ],
  );

  @override
  Future<ReferenceModelList> fetchModels(
    AppSettings settings, {
    required String bearerToken,
    int limit = 20,
    String? cursor,
  }) async => ReferenceModelList(
    models: [
      ReferenceModel(
        modelId: modelId,
        referenceRevisionId: revisionId,
        createdAtMs: 1788415200000,
        engineSha256: 'engine',
        metadataSha256: 'metadata',
        technicalPassed: true,
        reviewRequired: true,
        buildId: null,
        validation: null,
        weightsSha256: null,
        exportConfigSha256: null,
        onnxSha256: null,
      ),
    ],
    nextCursor: null,
  );
}

class _UnauthorizedReferenceApi extends _FakeReferenceApi {
  @override
  Future<ReferenceApiStatus> fetchStatus(
    AppSettings settings, {
    required String bearerToken,
  }) => Future.error(
    RemoteReferenceApiException(
      method: 'GET',
      uri: Uri.parse('http://station.test:8090/api/reference/status'),
      statusCode: 401,
      code: 'UNAUTHORIZED',
      message: 'Management token was rejected.',
    ),
  );
}

class _MemoryCredentialBackend implements SecureCredentialBackend {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
