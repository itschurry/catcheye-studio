import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:catcheye_studio/services/api_http_client.dart';

void main() {
  test(
    'deadline includes response body and a timed out POST is sent once',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiHttpClient(timeout: const Duration(milliseconds: 200));
      addTearDown(client.close);
      addTearDown(() => server.close(force: true));
      var requests = 0;
      server.listen((request) async {
        requests++;
        await request.drain<void>();
        request.response.write('{"unfinished":');
        await request.response.flush();
        // 응답 본문을 완료하지 않아 전체 요청 제한 시간을 검증합니다.
      });
      await expectLater(
        client.requestJson(
          'POST',
          Uri.parse('http://127.0.0.1:${server.port}'),
          body: {'action': 'capture'},
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(requests, 1);
    },
  );

  test(
    'empty response must be explicitly supported; malformed JSON fails',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ApiHttpClient();
      addTearDown(client.close);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (request.uri.path == '/empty') {
          request.response.statusCode = 204;
        } else {
          request.response.write('[]');
        }
        await request.response.close();
      });
      final base = 'http://127.0.0.1:${server.port}';
      expect(
        await client.requestJson(
          'GET',
          Uri.parse('$base/empty'),
          expectedStatusCodes: {204},
          allowEmpty: true,
        ),
        isEmpty,
      );
      await expectLater(
        client.requestJson(
          'GET',
          Uri.parse('$base/empty'),
          expectedStatusCodes: {204},
        ),
        throwsFormatException,
      );
      await expectLater(
        client.requestJson('GET', Uri.parse('$base/array')),
        throwsFormatException,
      );
      client.close();
      await expectLater(
        client.requestJson('GET', Uri.parse(base)),
        throwsStateError,
      );
    },
  );
}
