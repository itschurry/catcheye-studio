import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:catcheye_studio/models/app_settings.dart';
import 'package:catcheye_studio/services/remote_reference_api_service.dart';

ReferenceRevisionEntry sample(String id) => ReferenceRevisionEntry(
  className: 'nut_hole',
  imageId: id,
  imageUrl: '/api/reference/images/$id',
  width: 100,
  height: 100,
  boxes: const [ReferenceBox(10, 10, 50, 50)],
  contextRatio: .1,
);

void main() {
  test('add, edit and remove preserve the explicit class image list', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final sent = <List<dynamic>>[];
    server.listen((request) async {
      expect(request.uri.path, '/api/reference/revisions');
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      sent.add(body['entries'] as List);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'revision_id': 'refrev_${sent.length}',
          'base_revision_id': body['base_revision_id'],
          'created_at_ms': 1,
          'entries': [
            for (final e in body['entries'])
              {
                ...e,
                'image_url': '/api/reference/images/${e['image_id']}',
                'width': 100,
                'height': 100,
                'context_ratio': .1,
              },
          ],
        }),
      );
      await request.response.close();
    });
    final api = RemoteReferenceApiService();
    addTearDown(api.close);
    final settings = AppSettings(
      detectorBaseUrl: 'http://127.0.0.1:${server.port}',
    );
    const token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final added = await api.createRevision(
      settings,
      baseRevisionId: 'refrev_initial',
      className: 'nut_hole',
      imageId: 'img_new',
      boxes: sample('img_new').boxes,
      otherImages: [sample('img_old')],
      bearerToken: token,
    );
    expect(sent[0].map((e) => e['image_id']), ['img_old', 'img_new']);
    final edited = await api.createRevision(
      settings,
      baseRevisionId: added.revisionId,
      className: 'nut_hole',
      imageId: 'img_old',
      boxes: const [ReferenceBox(20, 20, 70, 70)],
      otherImages: added.entries,
      bearerToken: token,
    );
    expect(sent[1].length, 2);
    expect(sent[1].map((e) => e['image_id']), ['img_old', 'img_new']);
    expect(
      edited.entries.singleWhere((e) => e.imageId == 'img_old').boxes.single.x1,
      20,
    );
    final removed = await api.replaceClassReferences(
      settings,
      baseRevisionId: edited.revisionId,
      className: 'nut_hole',
      samples: [edited.entries.first],
      bearerToken: token,
    );
    expect(removed.entries.length, 1);
    expect(sent.length, 3);
    for (final samples in [
      <ReferenceRevisionEntry>[],
      [sample('x'), sample('x')],
      List.generate(17, (i) => sample('img_$i')),
    ]) {
      await expectLater(
        api.replaceClassReferences(
          settings,
          baseRevisionId: removed.revisionId,
          className: 'nut_hole',
          samples: samples,
          bearerToken: token,
        ),
        throwsFormatException,
      );
    }
    expect(sent.length, 3);
  });
}
