import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:catcheye_studio/services/websocket_frame_decoder.dart';

String bundle({int size = 1}) => jsonEncode({
  'type': 'viewer_frame',
  'metadata': {
    'camera_ids': ['a', 'b'],
  },
  'streams': [
    for (var i = 0; i < 2; i++)
      {
        'name': i == 0 ? 'a' : 'b',
        'kind': 'camera',
        'encoding': 'jpeg',
        'payload_index': i,
        'payload_size': size,
        'frame_sequence': 1,
      },
  ],
});
void main() {
  test(
    'decoder preserves an in-flight bundle when camera selection changes',
    () {
      final decoder = WebSocketFrameDecoder()..setExpectedCameraIds(['a', 'b']);
      decoder.process(bundle());
      decoder.process([1]);
      expect(decoder.streams, isEmpty);
      decoder.setExpectedCameraIds(['b']);
      decoder.process([2]);
      expect(decoder.streams.keys, ['b']);
      expect(decoder.streams['b']!.payloadBytes, [2]);
    },
  );
  test(
    'payload length mismatch rejects the bundle and valid next bundle recovers',
    () {
      final decoder = WebSocketFrameDecoder()..setExpectedCameraIds(['a', 'b']);
      decoder.process(bundle(size: 2));
      decoder.process([1]);
      decoder.process([2]);
      expect(decoder.streams, isEmpty);
      expect(decoder.errorMessage, isNotNull);
      decoder.process(bundle());
      decoder.process([3]);
      decoder.process([4]);
      expect(decoder.streams['a']!.payloadBytes, [3]);
      expect(decoder.streams['b']!.payloadBytes, [4]);
      expect(decoder.errorMessage, isNull);
    },
  );
  test('reset clears frame state but retains explicitly selected cameras', () {
    final decoder = WebSocketFrameDecoder()..setExpectedCameraIds(['a']);
    decoder.process(bundle());
    decoder.process([1]);
    decoder.process([2]);
    expect(decoder.streams, isNotEmpty);
    decoder.reset();
    expect(decoder.streams, isEmpty);
    expect(decoder.latestMetadata, isNull);
    expect(decoder.frameCount, 0);
    expect(decoder.expectedCameraIds, {'a'});
  });
}
