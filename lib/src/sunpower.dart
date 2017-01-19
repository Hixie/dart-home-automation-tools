import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'common.dart';
import 'watch_stream.dart';

typedef T ConversionHandler<String, T>(String value);

const Duration _sunPowerPeriod = const Duration(seconds: 5);

class SunPowerMonitor {
  SunPowerMonitor({ this.customerId, this.onError, Duration period: _sunPowerPeriod }) {
    _client = new HttpClient();
    _powerStream = new _UrlWatchStream<double>(_client, 'https://monitor.us.sunpower.com/CustomerPortal/CurrentPower/CurrentPower.svc/GetCurrentPower?id=$customerId', _sunPowerPeriod, _decodePower, onError);
  }

  HttpClient _client;
  
  final String customerId;
  final ErrorHandler onError;

  Stream<double> get power => _powerStream;
  _UrlWatchStream<double> _powerStream;

  Duration get period => _powerStream?.period;

  double _decodePower(String value) {
    final dynamic payload = JSON.decode(value);
    if (payload is Map && payload['Payload'] is Map && payload['Payload']['CurrentProduction'] is double)
      return payload['Payload']['CurrentProduction'];
    if (payload is Map && payload['StatusCode'] == '201' && payload['ResponseMessage'] == 'Failure')
      throw new Exception('non-specific error received from SunPower servers');
    throw new Exception('unexpected data from SunPower servers: $value');
  }

  void dispose() {
    _powerStream.close();
    _powerStream = null;
    _client.close(force: true);
  }
}

class _UrlWatchStream<T> extends WatchStream<T> {
  _UrlWatchStream(this.client, String url, this.period, this.parser, this.onError) : url = Uri.parse(url);

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
            throw new Exception('unexpected error from SunPower servers (${response.statusCode} ${response.reasonPhrase})');
        }
        add(parser(await response.transform(UTF8.decoder).single));
      } catch (exception) {
        add(null);
        if (onError != null)
          await onError(exception);
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
