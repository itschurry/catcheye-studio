import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:catcheye_studio/services/frame_receiver_service.dart';

void main() {
  test(
    'disconnect during WebSocket handshake cannot resurrect the old connection',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final request = Completer<HttpRequest>();
      server.listen(request.complete);
      final receiver = FrameReceiverService();
      addTearDown(receiver.dispose);
      expect(receiver.videoController, isNull);
      final connecting = receiver.connect('ws://127.0.0.1:${server.port}');
      final handshake = await request.future;
      await receiver.disconnect();
      final socket = await WebSocketTransformer.upgrade(handshake);
      socket.listen((_) {});
      addTearDown(socket.close);
      await connecting;
      expect(receiver.connected, isFalse);
      expect(receiver.connecting, isFalse);
      expect(receiver.connectedUri, isNull);
      expect(receiver.transport, isNull);
      expect(receiver.videoController, isNull);
    },
  );
}
