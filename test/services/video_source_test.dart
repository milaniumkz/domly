import 'package:domly/utils/video_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'uploaded signed videos play directly; external lesson embeds stay embeds',
      () {
    expect(
        isDirectVideoSource(
            'https://domly.kz/api/v1/files/media?key=training%2Flesson.mp4&signature=abc'),
        isTrue);
    expect(isDirectVideoSource('https://cdn.example/lesson.webm'), isTrue);
    expect(isDirectVideoSource('https://youtube.com/watch?v=lesson'), isFalse);
    expect(
        isDirectVideoSource(
            'https://domly.kz/api/v1/files/media?key=photo.jpg'),
        isFalse);
  });
}
