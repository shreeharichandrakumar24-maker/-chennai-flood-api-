import 'dart:io';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

class PhotoUploadException implements Exception {
  final String message;
  const PhotoUploadException(this.message);

  @override
  String toString() => 'PhotoUploadException: $message';
}

/// Firebase Storage uploads — photos only (all report data stays on the
/// Render backend). Uploads never throw raw Firebase errors; failures come
/// back as [PhotoUploadException] with a human-readable message, and the
/// text report is always submitted FIRST so a photo failure can never lose
/// or block a report.
class PhotoService {
  /// False when Firebase isn't configured on this build (missing
  /// google-services.json) — the UI then hides photo upload gracefully
  /// instead of crashing.
  static bool get isAvailable {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Upload a report photo and return its public download URL.
  /// Storage path: `reports/{reportId}/{timestamp}-{rand}.jpg`.
  /// Respects the 5 MB Storage rule by rejecting oversized files up front.
  static Future<String> uploadReportPhoto({
    required int reportId,
    required String localPath,
    void Function(double progress)? onProgress,
  }) async {
    if (!isAvailable) {
      throw const PhotoUploadException(
          'Photo upload is not configured on this build');
    }
    final file = File(localPath);
    if (!await file.exists()) {
      throw const PhotoUploadException('Photo file not found on device');
    }
    final bytes = await file.length();
    if (bytes > 5 * 1024 * 1024) {
      throw const PhotoUploadException(
          'Photo is larger than 5 MB — pick a smaller image');
    }
    final ext = localPath.split('.').last.toLowerCase();
    final safeExt =
        ['jpg', 'jpeg', 'png', 'webp'].contains(ext) ? ext : 'jpg';
    final rand = Random().nextInt(1 << 30).toRadixString(36);
    final name = '${DateTime.now().millisecondsSinceEpoch}-$rand.$safeExt';
    final ref =
        FirebaseStorage.instance.ref().child('reports/$reportId/$name');
    try {
      final task = ref.putFile(
        file,
        SettableMetadata(contentType: 'image/${safeExt == 'jpg' ? 'jpeg' : safeExt}'),
      );
      task.snapshotEvents.listen((snap) {
        if (snap.totalBytes > 0) {
          onProgress?.call(snap.bytesTransferred / snap.totalBytes);
        }
      });
      await task;
      final url = await ref.getDownloadURL();
      debugPrint('[PhotoService] uploaded reports/$reportId/$name');
      return url;
    } on FirebaseException catch (e) {
      debugPrint('[PhotoService] upload failed: ${e.code} ${e.message}');
      throw PhotoUploadException(_friendlyMessage(e));
    } catch (e) {
      debugPrint('[PhotoService] upload failed: $e');
      throw PhotoUploadException('Photo upload failed: $e');
    }
  }

  static String _friendlyMessage(FirebaseException e) {
    switch (e.code) {
      case 'unauthorized':
        return 'Photo upload blocked by Storage rules (unauthorized)';
      case 'retry-limit-exceeded':
      case 'unavailable':
        return 'Photo upload failed — network unavailable, will retry';
      case 'canceled':
        return 'Photo upload was canceled';
      default:
        return 'Photo upload failed (${e.code})${e.message != null ? ': ${e.message}' : ''}';
    }
  }
}
