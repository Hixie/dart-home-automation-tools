import 'dart:async';
import 'dart:io';

import '../common.dart';
import '../watch_stream.dart';

class DnsMasqMonitor {
  DnsMasqMonitor({
    this.maxUpdateDelay = const Duration(minutes: 5),
    String dnsMasqLeases = _filename,
    this.onLog,
  }) : _file = File(dnsMasqLeases) {
    _update();
    _start();
  }

  final Duration maxUpdateDelay;
  final LogCallback onLog;

  static const String _filename = '/var/lib/misc/dnsmasq.leases';

  final File _file;
  Stream<FileSystemEvent> _stream;
  StreamSubscription<FileSystemEvent> _subscription;
  Timer _timer;
  final Map<String, WatchStream<bool>> _outputs = <String, WatchStream<bool>>{};
  Set<String> _lastHosts = <String>{};

  WatchStream<bool> operator [](String name) {
    return _outputs.putIfAbsent(name, () => AlwaysOnWatchStream<bool>()..add(_lastHosts.contains(name)));
  }

  void _start() {
    log('starting monitoring of $_filename');
    _stream = _file.watch();
    _subscription = _stream.listen(_handler, onDone: _start, cancelOnError: true);
  }

  void _handler([FileSystemEvent data]) {
    log('detected change in $_filename');
    _update();
  }

  bool _parsing = false;
  Future<void> _update() async {
    if (_parsing)
      return;
    _parsing = true;
    log('updating...');
    try {
      final String data = await _file.readAsString();
      // 1618444641 b8:f6:b1:15:0a:61 10.10.10.30 laptop-chiron 01:b8:f6:b1:15:0a:61
      Set<String> hosts = <String>{};
      DateTime earliestExpiry = DateTime.now().add(maxUpdateDelay);
      for (String line in data.split('\n')) {
        if (line.isNotEmpty) {
          final List<String> fields = line.split(' ');
          // Fields are:
          //   - expiry (seconds since epoch)
          //   - mac address
          //   - ip address
          //   - host-reported name
          //   - host-reported client identifier (used to determine ip address)
          if (fields[0] != '0') {
            final DateTime expiry = DateTime.fromMillisecondsSinceEpoch(int.parse(fields[0]) * 1000);
            if (expiry.isBefore(earliestExpiry))
              earliestExpiry = expiry;
          }
          final InternetAddress ip = InternetAddress(fields[2] /*, type: InternetAddressType.IPv4 */);
          final InternetAddress dnsResult = await ip.reverse().catchError((Object error) => ip);
          if (dnsResult.host != dnsResult.address) {
            hosts.add(dnsResult.host);
          } else {
            hosts.add(dnsResult.address);
          }
        }
      }
      if (_lastHosts != null) {
        _lastHosts = hosts;
        for (String name in _outputs.keys)
          _outputs[name].add(_lastHosts.contains(name));
      }
      _timer?.cancel();
      _timer = Timer(earliestExpiry.difference(DateTime.now()), _update);
    } catch (error) {
      log('$error');
    } finally {
      _parsing = false;
      log('update done');
    }
  }

  void log(String message) {
    if (onLog != null)
      onLog(message);
  }

  void dispose() {
    for (WatchStream<bool> output in _outputs.values)
      output.close();
    _outputs.clear();
    _subscription.cancel();
    _timer?.cancel();
    _timer = null;
    _stream = null;
    _lastHosts = null;
  }
}
