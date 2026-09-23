import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class PhotoUploadException implements Exception {
  final String message;
  const PhotoUploadException(this.message);

  @override
  String toString() => 'PhotoUploadException: $message';
}

/// Cloudinary unsigned uploads — photos only (all report data stays on the
/// Render backend). No API secret in the app: the `flood_reports` preset is
/// Unsigned, so uploads need only the cloud name + preset name.
///
/// Uploads never throw raw transport errors; failures come back as
/// [PhotoUploadException] with a human-readable message, and the text
/// report is always submitted FIRST so a photo failure can never lose or
/// block a report.
class PhotoService {
  // Cloudinary account (free tier, no card). The `flood_reports` upload
  // preset must exist as Unsigned with asset folder `flood_reports`.
  static const String _cloudName = 'bg9apdxe';
  static const String _uploadPreset = 'flood_reports';
  static const int _maxBytes = 5 * 1024 * 1024;

  /// No SDK setup needed — plain HTTPS. Always available.
  static bool get isAvailable => true;

  /// Upload a report photo and return its public `secure_url`.
  /// Storage path: `<preset asset folder>/<timestamp>-<rand>.<ext>`.
  static Future<String> uploadReportPhoto({
    required int reportId,
    required String localPath,
    void Function(double progress)? onProgress,
  }) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw const PhotoUploadException('Photo file not found on device');
    }
    final bytes = await file.length();
    if (bytes > _maxBytes) {
      throw const PhotoUploadException(
          'Photo is larger than 5 MB — pick a smaller image');
    }
    final ext = localPath.split('.').last.toLowerCase();
    final safeExt =
        ['jpg', 'jpeg', 'png', 'webp'].contains(ext) ? ext : 'jpg';
    final rand =
        DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final filename = 'report-$reportId-$rand.$safeExt';
    final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$_cloudName/image/upload');

    http.StreamedResponse resp;
    try {
      onProgress?.call(0.2);
      final req = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = _uploadPreset
        ..files.add(await http.MultipartFile.fromPath(
          'file',
          localPath,
          filename: filename,
        ));
      resp = await req.send().timeout(const Duration(seconds: 60));
    } on Exception catch (e) {
      debugPrint('[PhotoService] upload transport failed: $e');
      throw PhotoUploadException(
          'Photo upload failed — check internet and retry ($e)');
    }
    final body = await resp.stream.bytesToString();
    if (resp.statusCode != 200) {
      debugPrint(
          '[PhotoService] Cloudinary HTTP ${resp.statusCode}: $body');
      throw PhotoUploadException(_friendlyHttpError(resp.statusCode, body));
    }
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final url = json['secure_url']?.toString();
      if (url == null || url.isEmpty) {
        throw const PhotoUploadException(
            'Photo upload gave no URL — retry (preset may be Signed or missing)');
      }
      onProgress?.call(1.0);
      debugPrint('[PhotoService] uploaded $filename');
      return url;
    } catch (e) {
      if (e is PhotoUploadException) rethrow;
      debugPrint('[PhotoService] bad Cloudinary response: $body');
      throw PhotoUploadException('Photo upload gave an unreadable reply');
    }
  }

  static String _friendlyHttpError(int status, String body) {
    if (status == 400 && body.contains('preset')) {
      return 'Photo upload rejected — upload preset "flood_reports" is '
          'missing or not Unsigned in the Cloudinary console';
    }
    if (status == 401 || status == 403) {
      return 'Photo upload rejected by Cloudinary (HTTP $status) — '
          'check the upload preset is Unsigned';
    }
    if (status == 429) {
      return 'Photo service is busy (rate-limited) — wait a minute and retry';
    }
    return 'Photo upload failed (HTTP $status) — retry';
  }
}
