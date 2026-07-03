import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/app_settings.dart';

class CaptureDateSummary {
  const CaptureDateSummary({required this.date, required this.count});

  final String date;
  final int count;

  factory CaptureDateSummary.fromJson(Map<String, dynamic> json) {
    return CaptureDateSummary(
      date: json['date'] as String,
      count: (json['count'] as num).toInt(),
    );
  }
}

class CaptureStorageInfo {
  const CaptureStorageInfo({
    required this.path,
    required this.totalBytes,
    required this.availableBytes,
    required this.usedBytes,
    required this.usedPercent,
    required this.captureBytes,
    required this.captureCount,
  });

  final String path;
  final int totalBytes;
  final int availableBytes;
  final int usedBytes;
  final double usedPercent;
  final int captureBytes;
  final int captureCount;

  factory CaptureStorageInfo.fromJson(Map<String, dynamic> json) {
    return CaptureStorageInfo(
      path: json['path'] as String,
      totalBytes: (json['total_bytes'] as num).toInt(),
      availableBytes: (json['available_bytes'] as num).toInt(),
      usedBytes: (json['used_bytes'] as num).toInt(),
      usedPercent: (json['used_percent'] as num).toDouble(),
      captureBytes: (json['capture_bytes'] as num).toInt(),
      captureCount: (json['capture_count'] as num).toInt(),
    );
  }
}

class CaptureDatesResponse {
  const CaptureDatesResponse({required this.storage, required this.dates});

  final CaptureStorageInfo? storage;
  final List<CaptureDateSummary> dates;

  factory CaptureDatesResponse.fromJson(Map<String, dynamic> json) {
    final dates = json['dates'] as List<dynamic>;
    final storage = json['storage'];
    return CaptureDatesResponse(
      storage: storage is Map<String, dynamic>
          ? CaptureStorageInfo.fromJson(storage)
          : null,
      dates: dates
          .map(
            (date) => CaptureDateSummary.fromJson(date as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }
}

class CaptureImageItem {
  const CaptureImageItem({
    required this.date,
    required this.filename,
    required this.capturedAt,
    required this.sequence,
    required this.sizeBytes,
    required this.width,
    required this.height,
    required this.url,
  });

  final String date;
  final String filename;
  final String capturedAt;
  final int sequence;
  final int sizeBytes;
  final int width;
  final int height;
  final String url;

  factory CaptureImageItem.fromJson(Map<String, dynamic> json, {String? date}) {
    return CaptureImageItem(
      date: json['date'] as String? ?? date!,
      filename: json['filename'] as String,
      capturedAt: json['captured_at'] as String,
      sequence: (json['sequence'] as num).toInt(),
      sizeBytes: (json['size_bytes'] as num).toInt(),
      width: (json['width'] as num).toInt(),
      height: (json['height'] as num).toInt(),
      url: json['url'] as String,
    );
  }
}

class CaptureImageList {
  const CaptureImageList({
    required this.date,
    required this.items,
    required this.nextCursor,
  });

  final String date;
  final List<CaptureImageItem> items;
  final String nextCursor;

  factory CaptureImageList.fromJson(Map<String, dynamic> json) {
    final date = json['date'] as String;
    final rawItems = json['items'] as List<dynamic>;
    return CaptureImageList(
      date: date,
      items: rawItems
          .map(
            (item) => CaptureImageItem.fromJson(
              item as Map<String, dynamic>,
              date: date,
            ),
          )
          .toList(growable: false),
      nextCursor: json['next_cursor'] as String? ?? '',
    );
  }
}

class RemoteCaptureImageApiService {
  final HttpClient _client = HttpClient();

  Future<CaptureDatesResponse> fetchDates(AppSettings settings) async {
    final json = await _requestJson(
      'GET',
      settings.buildApiUri('captures/dates'),
    );
    return CaptureDatesResponse.fromJson(json);
  }

  Future<CaptureImageList> fetchImages(
    AppSettings settings, {
    required String date,
    int limit = 100,
    String? cursor,
  }) async {
    final query = <String, String>{
      'date': date,
      'limit': '$limit',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    final uri = settings
        .buildApiUri('captures')
        .replace(queryParameters: query);
    final json = await _requestJson('GET', uri);
    return CaptureImageList.fromJson(json);
  }

  Future<CaptureImageItem> fetchLatest(AppSettings settings) async {
    final json = await _requestJson(
      'GET',
      settings.buildApiUri('captures/latest'),
    );
    return CaptureImageItem.fromJson(json);
  }

  Future<Uint8List> fetchImageBytes(
    AppSettings settings,
    CaptureImageItem image,
  ) async {
    final request = await _client.openUrl(
      'GET',
      settings.buildApiUri('captures/file/${image.date}/${image.filename}'),
    );
    request.headers.set(HttpHeaders.acceptHeader, 'image/jpeg');

    final response = await request.close();
    final chunks = <int>[];
    await for (final chunk in response) {
      chunks.addAll(chunk);
    }
    if (response.statusCode != 200) {
      throw HttpException(
        'Request failed (${response.statusCode}) for ${request.uri}',
        uri: request.uri,
      );
    }
    return Uint8List.fromList(chunks);
  }

  Future<Map<String, dynamic>> _requestJson(String method, Uri uri) async {
    final request = await _client.openUrl(method, uri);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.contentLength = 0;

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      final errorBody = responseBody.isEmpty
          ? response.reasonPhrase
          : responseBody;
      throw HttpException(
        'Request failed (${response.statusCode}) for $uri: $errorBody',
        uri: uri,
      );
    }

    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('JSON object response expected');
    }
    return decoded;
  }
}
