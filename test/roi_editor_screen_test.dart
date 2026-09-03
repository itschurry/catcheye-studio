import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:catcheye_studio/providers/roi_config_provider.dart';
import 'package:catcheye_studio/providers/settings_provider.dart';
import 'package:catcheye_studio/screens/roi_editor_screen.dart';
import 'package:catcheye_studio/services/frame_receiver_service.dart';
import 'package:catcheye_studio/widgets/roi_editor_canvas.dart';

class TestReceiver extends ChangeNotifier implements FrameReceiverService {
  TestReceiver(this.streamName);

  final String streamName;
  @override
  final Map<String, ViewerStreamFrame> streams = {};
  @override
  bool connected = true;
  @override
  bool get connecting => false;
  @override
  String? errorMessage;
  int disconnects = 0;
  bool get listening => hasListeners;
  @override
  Future<void> connect([String url = '']) async {}
  @override
  Future<void> disconnect() async {
    disconnects++;
  }

  void emit(Uint8List bytes) {
    streams[streamName] = ViewerStreamFrame(
      name: streamName,
      kind: streamName,
      encoding: ViewerStreamEncoding.jpeg,
      payloadIndex: 0,
      payloadBytes: bytes,
      receivedAt: DateTime.now(),
      width: 640,
      height: 480,
    );
    notifyListeners();
  }

  void fail() {
    connected = false;
    streams.clear();
    errorMessage = 'Connection lost';
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final streamName in ['camera', 'color']) {
    testWidgets(
      'ROI keeps receiving $streamName frames and surfaces connection failure',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1400, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final receiver = TestReceiver(streamName);
        final roi = RoiConfigProvider();
        final settings = SettingsProvider();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<FrameReceiverService>.value(
                value: receiver,
              ),
              ChangeNotifierProvider.value(value: roi),
              ChangeNotifierProvider.value(value: settings),
            ],
            child: const MaterialApp(
              home: Scaffold(body: RoiEditorScreen(isPhone: true)),
            ),
          ),
        );
        final first = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
        );
        receiver.emit(first);
        await tester.pump();
        expect(find.text('Live'), findsOneWidget);
        expect(
          tester
              .widget<RoiEditorCanvas>(find.byType(RoiEditorCanvas))
              .backgroundImageBytes,
          same(first),
        );
        expect(roi.config.imageWidth, 640);
        expect(roi.config.imageHeight, 480);
        final second = Uint8List.fromList(first);
        receiver.emit(second);
        await tester.pump(const Duration(seconds: 4));
        expect(
          tester
              .widget<RoiEditorCanvas>(find.byType(RoiEditorCanvas))
              .backgroundImageBytes,
          same(second),
        );
        expect(receiver.disconnects, 0);
        receiver.fail();
        await tester.pump();
        expect(find.text('Connection lost'), findsOneWidget);
        expect(
          tester
              .widget<RoiEditorCanvas>(find.byType(RoiEditorCanvas))
              .backgroundImageBytes,
          isNull,
        );
        await tester.pumpWidget(const SizedBox());
        expect(receiver.listening, isFalse);
        receiver.dispose();
        roi.dispose();
        settings.dispose();
      },
    );
  }
}
