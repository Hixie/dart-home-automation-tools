import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'common.dart';
import 'watch_stream.dart';

typedef T ConversionHandler<String, T>(String value);

class UrlWatchStream<T> extends WatchStream<T> {
  UrlWatchStream(this.client, this.period, this.parser, this.onLog, {
    String url,
    this.authorization,
  }) {
    this.url = url;
  }

  final HttpClient client;
  final Duration period;
  final ConversionHandler<String, T> parser;
  final LogCallback onLog;

  bool _active = false;

  String get url => _url?.toString();
  Uri _url;
  set url(String value) {
    bool wasNull = _url == null;
    _url = value != null ? Uri.parse(value) : null;
    if (_active) {
      if (wasNull && _url != null) {
        _start();
      } else if (!wasNull && _url == null) {
        _stop();
      }
    }
  }

  String authorization;

  Timer _timer;

  @override
  void handleStart() {
    assert(_timer == null);
    assert(!_active);
    _active = true;
    if (_url != null)
      _start();
  }

  @override
  void handleEnd() {
    assert(_active);
    _active = false;
    if (_url != null)
      _stop();
  }

  void _start() {
    if (onLog != null)
      onLog('starting periodic timer');
    assert(_active && _url != null);
    assert(_timer == null);
    _timer = new Timer.periodic(period, tick);
    tick(_timer);
  }

  void _stop() {
    assert(_timer != null);
    assert(!_active || _url == null);
    _timer.cancel();
    _timer = null;
    if (onLog != null)
      onLog('stopped periodic timer');
  }

  bool _fetching = false;

  Future<Null> tick(Timer timer) async {
    assert(_timer != null);
    assert(_active);
    assert(_url != null);
    if (!_fetching) {
      try {
        _fetching = true;
        final HttpClientRequest request = await client.getUrl(_url);
        if (authorization != null)
          request.headers.add('Authorization', authorization);
        final HttpClientResponse response = await request.close();
        switch (response.statusCode) {
          case 200:
            break;
          default:
            await response.drain();
            throw new Exception('unexpected error from ${_url.host} (${response.statusCode} ${response.reasonPhrase})');
        }
        add(parser(await response.transform(utf8.decoder).join('')));
      } on Error catch (error) {
        rethrow;
      } catch (exception) {
        add(null);
        if (onLog != null)
          onLog('$exception');
        else
          rethrow;
      } finally {
        _fetching = false;
      }
    } else {
      if (onLog != null)
        onLog('skipping fetch; previous fetch has not yet completed');
    }
  }
}
