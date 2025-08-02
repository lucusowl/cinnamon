import 'dart:async';

/// 비동기 세마포어
class AsyncSemaphore {
  AsyncSemaphore(this._maxConcurrent);

  final int _maxConcurrent;
  int _current = 0;
  final _queue = <Completer>[];

  Future<T> run<T>(Future<T> Function() task) async {
    if (_current >= _maxConcurrent) {
      final completer = Completer();
      _queue.add(completer);
      await completer.future;
    }

    _current++;
    try {
      return await task();
    } catch (_) {
      rethrow;
    } finally {
      _current--;
      if (_queue.isNotEmpty) {
        _queue.removeAt(0).complete();
      }
    }
  }
}

/// 입력받은 리스트를 지정한 사이즈의 청크리스트 반복자
// Iterable<List<T>> chunked<T>(List<T> list, int size) sync* {
//   for (int i = 0; i < list.length; i += size) {
//     yield list.sublist(i, i + size > list.length ? list.length : i + size);
//   }
// }