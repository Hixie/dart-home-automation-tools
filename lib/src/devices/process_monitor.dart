import 'dart:async';
import 'dart:io';

import '../common.dart';
import '../watch_stream.dart';

class ProcessMonitor {
  ProcessMonitor({
    this.executable,
    this.onLog,
    this.onError,
  }) {
    _output = new HandlerWatchStream<int>(_start, _end);
  }

  final String executable;
  final LogCallback onLog;
  final ErrorHandler onError;

  WatchStream<int> _output;
  WatchStream<int> get output => _output;

  bool _active = true;
  Completer<void> _activeChange = Completer<void>();

  void _start(Sink<int> sink) async {
    while (_active) {
      Process process;
      try {
        process = await Process.start(executable, <String>[]);
        onLog('Started "$executable".');
        final StreamSubscription<List<int>> sub = process.stdout.listen((List<int> data) {
          data.forEach(sink.add);
        });
        await _activeChange.future;
        sub.cancel();
        process.kill();
      } catch (e) {
        await fail(e);
      }
    }
  }

  void _end() {
    _active = false;
    _activeChange.complete();
    _activeChange = Completer<void>();
  }

  Future<Null> fail(dynamic error) async {
    if (onError != null)
      await onError(error);
  }

  void dispose() {
    _output.close(); // calls _end if necessary
  }
}
