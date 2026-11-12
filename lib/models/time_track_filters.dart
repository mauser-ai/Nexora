import 'domain_models.dart';

/// The workspace already contains the authorized team's shared MySQL records.
List<TimeTrack> timeTracksForUser(
  Iterable<TimeTrack> tracks,
  String? userId, {
  String? legacyOwnerId,
}) {
  if (userId == null) return tracks.toList();
  return tracks.where((track) {
    final tracker = track.userId.isEmpty ? legacyOwnerId : track.userId;
    return tracker == userId;
  }).toList();
}
