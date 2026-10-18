// lib/models/firestore_fields.dart
//
// Defensive reading of Firestore documents.
//
// Why this exists
// ---------------
// Firestore has no schema. The app's own writes are checked by
// firestore.rules, but the Laravel dashboard and the seed scripts use a
// service account that bypasses the rules, so a document can arrive with a
// missing field, a string where a number belongs, or a pain level of 15.
// The old models cast blindly (`d['x'] as int`), so ONE bad document threw
// and the whole list (sessions, prescriptions, messages) failed to load.
//
// The rules used here
// -------------------
//   - A field the screen cannot work without (a session's start time, a
//     prescription's exercise type) is "required": when it is missing or the
//     wrong type, the reader throws a [FormatException] and the caller skips
//     that one document.
//   - Any other field falls back to a sensible default. When the field WAS
//     present but unusable (wrong type, out of range, too long), its name is
//     added to [FieldReader.repaired], so the caller can log which documents
//     needed repair. A field that is simply absent is normal (most are
//     optional) and is not reported.
//   - Error messages and `repaired` hold field NAMES only, never values, so
//     they are safe to put in the diagnostic log (no health data or PII).
//
// Everything here is pure Dart (Timestamp is a plain value class), so it
// works in unit tests and on background isolates.

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

/// Reads typed values out of one Firestore document map, tolerating bad data.
class FieldReader {
  FieldReader(this.data);

  /// The raw document data.
  final Map<String, dynamic> data;

  /// Names of fields that were present but unusable and had to be replaced
  /// by a default, clamped into range or clipped. In the order found.
  final List<String> repaired = [];

  void _markRepaired(String key) {
    if (!repaired.contains(key)) repaired.add(key);
  }

  /// A non-blank string; throws [FormatException] otherwise.
  String requireString(String key) {
    final value = data[key];
    if (value is String && value.trim().isNotEmpty) return value;
    throw FormatException('Missing or invalid required field "$key"');
  }

  /// A string, or null when absent or not a string. Strings longer than
  /// [maxLength] are clipped (and reported as repaired).
  String? string(String key, {int? maxLength}) {
    final value = data[key];
    if (value == null) return null;
    if (value is! String) {
      _markRepaired(key);
      return null;
    }
    if (maxLength != null && value.length > maxLength) {
      _markRepaired(key);
      return clipText(value, maxLength);
    }
    return value;
  }

  /// An integer clamped into [min]..[max], or null when absent or not a
  /// number. Whole doubles (10.0, as JavaScript/PHP clients may write) are
  /// accepted; fractional ones are truncated and reported as repaired.
  int? integer(String key, {int? min, int? max}) {
    final value = data[key];
    if (value == null) return null;
    int result;
    if (value is int) {
      result = value;
    } else if (value is double && value.isFinite) {
      result = value.truncate();
      if (result != value) _markRepaired(key);
    } else {
      _markRepaired(key);
      return null;
    }
    if (min != null && result < min) {
      _markRepaired(key);
      result = min;
    }
    if (max != null && result > max) {
      _markRepaired(key);
      result = max;
    }
    return result;
  }

  /// A finite double clamped into [min]..[max], or null when absent or not
  /// a number (NaN and infinity count as "not a number").
  double? decimal(String key, {double? min, double? max}) {
    final value = data[key];
    if (value == null) return null;
    if (value is! num || !value.isFinite) {
      _markRepaired(key);
      return null;
    }
    return clampToRange(
      value.toDouble(),
      min: min,
      max: max,
      onClamp: () {
        _markRepaired(key);
      },
    );
  }

  /// A bool, or [fallback] when absent or not a bool. Strings such as
  /// "true" are NOT accepted: the rules and every writer use real bools.
  bool boolean(String key, {bool fallback = false}) {
    final value = data[key];
    if (value is bool) return value;
    if (value != null) _markRepaired(key);
    return fallback;
  }

  /// A point in time from a Firestore [Timestamp], a [DateTime], or an
  /// ISO-8601 string (the shape used by [toJson] methods). Null when absent
  /// or unusable.
  DateTime? dateTime(String key) {
    final value = data[key];
    if (value == null) return null;
    final parsed = parseDateTime(value);
    if (parsed == null) _markRepaired(key);
    return parsed;
  }

  /// Like [dateTime] but throws [FormatException] when absent or unusable.
  DateTime requireDateTime(String key) {
    final parsed = parseDateTime(data[key]);
    if (parsed != null) return parsed;
    throw FormatException('Missing or invalid required field "$key"');
  }

  /// A nested map with string keys, or null when absent or not a map.
  Map<String, dynamic>? map(String key) {
    final value = data[key];
    if (value == null) return null;
    if (value is! Map) {
      _markRepaired(key);
      return null;
    }
    return value.map((k, v) => MapEntry(k.toString(), v));
  }

  /// A list, or null when absent or not a list.
  List<Object?>? list(String key) {
    final value = data[key];
    if (value == null) return null;
    if (value is! List) {
      _markRepaired(key);
      return null;
    }
    return value;
  }

  /// Records that [key] was repaired by the caller (for checks that need
  /// more than one field, e.g. an end time before the start time).
  void markRepaired(String key) => _markRepaired(key);
}

/// Converts a Firestore/JSON time value to [DateTime], or null.
DateTime? parseDateTime(Object? value) => switch (value) {
  Timestamp t => t.toDate(),
  DateTime d => d,
  String s => DateTime.tryParse(s),
  _ => null,
};

/// Clamps [value] into [min]..[max] (either may be null), calling [onClamp]
/// when it had to move.
double clampToRange(
  double value, {
  double? min,
  double? max,
  void Function()? onClamp,
}) {
  if (min != null && value < min) {
    onClamp?.call();
    return min;
  }
  if (max != null && value > max) {
    onClamp?.call();
    return max;
  }
  return value;
}

/// Cuts [text] to at most [maxLength] UTF-16 code units without splitting an
/// emoji (a surrogate pair) in half. Firestore rules count characters, which
/// is never more than code units, so the result always fits a
/// `size() <= maxLength` rule.
String clipText(String text, int maxLength) {
  if (text.length <= maxLength) return text;
  var end = maxLength;
  if (end > 0) {
    final last = text.codeUnitAt(end - 1);
    final isHighSurrogate = last >= 0xD800 && last <= 0xDBFF;
    if (isHighSurrogate) end--;
  }
  return text.substring(0, end);
}

/// The outcome of defensively parsing one document.
///
/// Exactly one of [value] / [error] is set. [error] is a short, value-free
/// description (e.g. 'Missing or invalid required field "startTime"') that
/// is safe to log. [repaired] lists fields that were present but replaced
/// by defaults; the document is still usable.
class Parsed<T> {
  const Parsed.ok(T this.value, {this.repaired = const []}) : error = null;
  const Parsed.failed(String this.error) : value = null, repaired = const [];

  final T? value;
  final String? error;
  final List<String> repaired;

  bool get isOk => value != null;

  /// Runs [parse] and converts any exception into [Parsed.failed], so one
  /// malformed document never throws out of a list-mapping loop.
  static Parsed<T> guard<T>(
    T Function(FieldReader reader) parse,
    Map<String, dynamic> data,
  ) {
    final reader = FieldReader(data);
    try {
      final value = parse(reader);
      return Parsed.ok(value, repaired: List.unmodifiable(reader.repaired));
    } on FormatException catch (e) {
      return Parsed.failed(e.message);
    } catch (e) {
      // A TypeError or similar from an unexpected shape. Only the type is
      // kept: the error text could quote a field value.
      return Parsed.failed('Unexpected ${e.runtimeType} while parsing');
    }
  }
}
