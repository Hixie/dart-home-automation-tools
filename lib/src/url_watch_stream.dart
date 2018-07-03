import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'common.dart';
import 'watch_stream.dart';

typedef T ConversionHandler<String, T>(String value);

class UrlWatchStream<T> extends WatchStream<T> {
  UrlWatchStream(this.client, String url, this.period, this.parser, this.onError) : url = Uri.parse(url);

  final HttpClient client;
  final Uri url;
  final Duration period;
  final ConversionHandler<String, T> parser;
  final ErrorHandler onError;

  Timer _timer;

  @override
  void handleStart() {
    assert(_timer == null);
    _timer = new Timer.periodic(period, tick);
    tick(_timer);
  }

  bool _active = false;

  Future<Null> tick(Timer timer) async {
    assert(_timer != null);
    if (!_active) {
      try {
        _active = true;
        final HttpClientRequest request = await client.getUrl(url);
        final HttpClientResponse response = await request.close();
        switch (response.statusCode) {
          case 200:
            break;
          default:
            await response.drain();
            throw new Exception('unexpected error from SunPower servers (${response.statusCode} ${response.reasonPhrase})');
        }
        add(parser(await response.transform(UTF8.decoder).join('')));
      } catch (exception) {
        add(null);
        if (onError != null)
          await onError('$exception');
        else
          rethrow;
      }
      _active = false;
    }
  }

  @override
  void handleEnd() {
    assert(_timer != null);
    _timer.cancel();
    _timer = null;
  }
}
