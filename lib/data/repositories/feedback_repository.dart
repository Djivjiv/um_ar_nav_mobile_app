import 'package:flutter/foundation.dart';

import '../../core/utils/device_utils.dart';
import '../local/pending_write_queue.dart';
import '../models/feedback_person.dart';

/// Optional comments, written to `feedback_comments`
/// (`supabase/feedback_comments.sql`).
class FeedbackRepository {
  final PendingWriteQueue _queue;
  final Future<String> Function() _deviceCode;
  final DateTime Function() _now;

  FeedbackRepository({
    PendingWriteQueue? queue,
    Future<String> Function()? deviceCode,
    DateTime Function()? now,
  })  : _queue = queue ?? PendingWriteQueue.instance,
        _deviceCode = deviceCode ?? DeviceUtils.getDeviceCode,
        _now = now ?? DateTime.now;

  static const String table = 'feedback_comments';
  static const int maxLength = 500;

  // rating_context: where the comment was written.
  static const String afterSus = 'sus';
  static const String afterArrival = 'arrival';
  static const String fromProfile = 'profile';

  /// Trips whose comment card was answered or skipped in this app run.
  final Set<String> _closedTrips = {};

  /// [text] trimmed and limited to [maxLength], counted the way Postgres
  /// counts, so a cut never splits an emoji.
  static String cleanComment(String text) {
    final trimmed = text.trim();
    if (trimmed.runes.length <= maxLength) return trimmed;
    return String.fromCharCodes(trimmed.runes.take(maxLength)).trimRight();
  }

  /// Stores the comment on the device, then tries to send it.
  ///
  /// Returns true when it reached the server, false when it is queued and
  /// will be sent automatically once the connection returns. Throws if there
  /// is nothing to send, or if the device storage itself fails (nothing was
  /// saved).
  Future<bool> submitComment({
    required String comment,
    required String ratingContext,
    required FeedbackPerson person,
  }) async {
    final text = cleanComment(comment);
    if (text.isEmpty) throw ArgumentError.value(comment, 'comment', 'is empty');

    String? deviceCode;
    try {
      deviceCode = await _deviceCode();
    } catch (e) {
      debugPrint('Device code unavailable: $e');
    }
    // Saved on the device first, and never given up on: a comment has no
    // second chance, the person won't type it again.
    final id = await _queue.enqueue(
      table,
      {
        'comment': text,
        'rating_context': ratingContext,
        'role': person.role,
        'device_code': ?deviceCode,
        'user_id': person.userId,
        'created_at': _now().toUtc().toIso8601String(),
      },
      keepForever: true,
    );
    try {
      await _queue.flush();
    } catch (_) {}
    return !await _queue.isPending(id);
  }

  /// No more comment prompts for this trip. A null id is a trip with no log.
  void closeTrip(String? tripId) {
    if (tripId != null) _closedTrips.add(tripId);
  }

  bool isTripClosed(String? tripId) => _closedTrips.contains(tripId);
}
