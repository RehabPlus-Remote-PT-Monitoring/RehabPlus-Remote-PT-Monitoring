// lib/services/replay_storage.dart
//
// Firestore documents for a movement replay, as pure functions so they can be
// unit-tested without Firebase (test/replay_storage_test.dart). The thin
// write itself is SessionStorage.saveReplay.
//
// Layout (API_CONTRACT.md, firestore.rules validReplayMeta/validReplayChunk):
//   patients/{uid}/sessions/{sessionId}/replay/meta
//   patients/{uid}/sessions/{sessionId}/replay/c000 ... c019

import 'package:cloud_firestore/cloud_firestore.dart' show Blob, FieldValue;

import 'replay_recorder.dart';

/// The (document id, data) pairs to write under `replay/`: `meta` first,
/// then one doc per chunk. `meta.createdAt` is the server time (the rules
/// require `createdAt == request.time`) and chunk data is a Firestore
/// [Blob] (the rules require `data is bytes`).
List<(String docId, Map<String, Object?> data)> replayWrites(
  ReplayPayload payload,
) => [
  ('meta', {...payload.meta, 'createdAt': FieldValue.serverTimestamp()}),
  for (final chunk in payload.chunks)
    (
      chunk.docId,
      {
        'index': chunk.index,
        'firstFrame': chunk.firstFrame,
        'frames': chunk.frames,
        'data': Blob(chunk.data),
      },
    ),
];

/// What in [payload] the security rules would refuse, by name; empty means
/// it can be written. Checked before writing so a bug in the encoder shows
/// up as one clear log line instead of a silently rejected batch.
List<String> replayProblems(ReplayPayload payload) {
  final meta = payload.meta;
  final chunks = payload.chunks;
  final problems = <String>[];

  bool intIn(String key, int min, int max) {
    final v = meta[key];
    return v is int && v >= min && v <= max;
  }

  if (meta['version'] != ReplayRecorder.formatVersion) problems.add('version');
  if (!intIn('fps', 1, ReplayRecorder.maxFps)) problems.add('fps');
  if (!intIn('frameCount', 0, ReplayRecorder.maxFrames)) {
    problems.add('frameCount');
  }
  if (!intIn('chunkCount', 1, ReplayRecorder.maxChunks) ||
      meta['chunkCount'] != chunks.length) {
    problems.add('chunkCount');
  }
  if (!intIn('durationMs', 0, 4 * 60 * 60 * 1000)) problems.add('durationMs');
  if (meta['truncated'] is! bool) problems.add('truncated');
  final aspect = meta['aspect'];
  if (aspect is! num ||
      aspect < ReplayRecorder.minAspect ||
      aspect > ReplayRecorder.maxAspect) {
    problems.add('aspect');
  }
  if (meta['mirrored'] is! bool) problems.add('mirrored');
  final label = meta['angleLabel'];
  if (label != null &&
      (label is! String || label.length > ReplayRecorder.maxAngleLabelLength)) {
    problems.add('angleLabel');
  }
  final events = meta['events'];
  if (events is! List ||
      events.length > ReplayRecorder.maxEvents ||
      events.any(
        (e) =>
            e is! Map ||
            e['t'] is! int ||
            !ReplayEventKind.all.contains(e['kind']) ||
            e['note'] is! String ||
            (e['note'] as String).length > ReplayRecorder.maxNoteLength,
      )) {
    problems.add('events');
  }

  var frames = 0;
  for (var i = 0; i < chunks.length; i++) {
    final c = chunks[i];
    if (c.index != i ||
        c.index >= ReplayRecorder.maxChunks ||
        c.firstFrame != c.index * ReplayRecorder.framesPerChunk ||
        c.frames < 1 ||
        c.frames > ReplayRecorder.framesPerChunk ||
        c.data.length != c.frames * ReplayRecorder.frameBytes) {
      problems.add('chunk ${c.docId}');
    }
    frames += c.frames;
  }
  if (meta['frameCount'] != frames) problems.add('frameCount != chunk frames');
  return problems;
}
