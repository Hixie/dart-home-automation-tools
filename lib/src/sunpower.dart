import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'common.dart';
import 'url_watch_stream.dart';
import 'json.dart';

const Duration _sunPowerPeriod = const Duration(seconds: 10);
const Duration _sunPowerMargin = const Duration(seconds: 5);

class SunPowerMonitor {
  SunPowerMonitor({
    String customerUsername,
    String customerPassword,
    this.onLog,
    Duration period: _sunPowerPeriod,
  }) : _customerUsername = customerUsername,
       _customerPassword = customerPassword {
    assert(period > _sunPowerMargin, 'period must be longer than $_sunPowerMargin');
    _client = new HttpClient();
    _powerStream = new UrlWatchStream<double>(_client, _sunPowerPeriod, _decodePower, onLog);
    _login();
  }

  HttpClient _client;
  
  final String _customerUsername;
  final String _customerPassword;
  final LogCallback onLog;

  Stream<double> get power => _powerStream;
  UrlWatchStream<double> _powerStream;

  Duration get period => _powerStream.period;

  String _customerId;
  Timer _loginTimer;

  Future<Null> _login() async {
    HttpClientRequest request;
    HttpClientResponse response;
    String data;
    try {
      _powerStream.url = null;
      request = await _client.postUrl(Uri.parse('https://monitor.us.sunpower.com/CustomerPortal/Auth/Auth.svc/Authenticate'));
      request.headers.contentType = new ContentType("application", "json", charset: "utf-8");
      request.write(JSON.encode(<String, dynamic>{
        'username': _customerUsername,
        'password': _customerPassword,
        'isPersistent': false,
      }));
      response = await request.close();
      data = await response.transform(UTF8.decoder).join();
      try {
        Json result = Json.parse(data);
        _customerId = result.Payload.TokenID.toString();
        int expiryInMinutes = result.Payload.ExpiresInMinutes.toInt();
        Duration expiry;
        if (expiryInMinutes > 5) {
          expiry = new Duration(minutes: expiryInMinutes - 5);
        } else {
          expiry = period - _sunPowerMargin;
        }
        _loginTimer = new Timer(expiry, _login);
        _powerStream.url = _url;
        onLog('logged in; will refresh credentials in ${prettyDuration(expiry)}');
      } catch (error, stack) {
        if (onLog != null)
          onLog('Could not log into SunPower portal ($error); portal returned: $data\n$stack');
      }
    } catch (error, stack) {
      if (onLog != null)
        onLog('Could not log into SunPower portal: $error\n$stack');
    }
  }

  String get _url => 'https://monitor.us.sunpower.com/CustomerPortal/CurrentPower/CurrentPower.svc/GetCurrentPower?id=$_customerId';

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
    _loginTimer.cancel();
    _client.close(force: true);
  }
}
