import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'common.dart';
import 'url_watch_stream.dart';

const Duration _sunPowerPeriod = const Duration(seconds: 5);

class SunPowerMonitor {
  SunPowerMonitor({ this.customerId, this.onError, Duration period: _sunPowerPeriod }) {
    _client = new HttpClient();
    _powerStream = new UrlWatchStream<double>(_client, 'https://monitor.us.sunpower.com/CustomerPortal/CurrentPower/CurrentPower.svc/GetCurrentPower?id=$customerId', _sunPowerPeriod, _decodePower, onError);
  }

  HttpClient _client;
  
  final String customerId;
  final ErrorHandler onError;

  Stream<double> get power => _powerStream;
  UrlWatchStream<double> _powerStream;

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
