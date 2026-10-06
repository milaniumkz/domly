class Timestamp {
  const Timestamp(this.seconds, this.nanoseconds);

  final int seconds;
  final int nanoseconds;

  factory Timestamp.now() => Timestamp.fromDate(DateTime.now());

  factory Timestamp.fromDate(DateTime date) {
    final millis = date.millisecondsSinceEpoch;
    return Timestamp(millis ~/ 1000, (millis % 1000) * 1000000);
  }

  factory Timestamp.fromMillisecondsSinceEpoch(int milliseconds) {
    return Timestamp.fromDate(
      DateTime.fromMillisecondsSinceEpoch(milliseconds),
    );
  }

  DateTime toDate() => DateTime.fromMillisecondsSinceEpoch(
        seconds * 1000 + nanoseconds ~/ 1000000,
      );

  int get millisecondsSinceEpoch => seconds * 1000 + nanoseconds ~/ 1000000;
}

class FieldValue {
  const FieldValue._(this.kind);

  final String kind;

  static FieldValue serverTimestamp() => const FieldValue._('serverTimestamp');

  static FieldValue delete() => const FieldValue._('delete');
}

class SetOptions {
  const SetOptions({this.merge});

  final bool? merge;
}
