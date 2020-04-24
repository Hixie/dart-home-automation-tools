import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import '../common.dart';
import '../metrics.dart';
import '../temperature.dart';
import '../watch_stream.dart';

// This is written for the RP32-IP Network Thermostat, V2.40.
// DIP switches are expected to be 0,1,1,0,1,0,1,0.
// Scale is expected to be CELSIUS.
// Min and max set points should be at default values.

enum ThermostatStatus { heating, cooling, fan, idle }

final bool verbose = false;

class _PendingCommand {
  _PendingCommand(this.message);

  final String message;

  final Completer<String> _completer = new Completer<String>();

  Future<String> get result => _completer.future;
}

class Thermostat {
  Thermostat({
    this.host,
    this.port: 10001,
    this.username,
    this.password,
    this.period = const Duration(seconds: 5),
    this.onError,
    this.onLog,
  }) {
    _temperature = new HandlerWatchStream<Temperature>(_startPollingTemperature, _endPollingTemperature);
    _status = new HandlerWatchStream<ThermostatStatus>(_startPollingStatus, _endPollingStatus);
    _initialize();
  }

  final InternetAddress host;
  final int port;
  final String username;
  final String password;
  final Duration period;

  final ErrorHandler onError;
  final LogCallback onLog;

  WatchStream<Temperature> _temperature;
  WatchStream<Temperature> get temperature => _temperature;
  
  WatchStream<ThermostatStatus> _status;
  WatchStream<ThermostatStatus> get status => _status;

  MeasurementStation _station;

  void _processStatus(String message) {
    assert(_station != null);
    final DateTime timestamp = new DateTime.now();
    if (!message.startsWith('RAS1:'))
      throw 'Invalid status message from thermostat: $message';
    List<String> fields = message.substring(5, message.length).split(',');
    if (fields.length != 10)
      throw 'Incorrect number of fields in status message from thermostat: $message';
    final double temperatureValue = double.tryParse(fields[0]);
    ThermostatStatus statusValue;
    if (fields[9] == '1') {
      if (fields[8] == 'COOL') {
        statusValue = ThermostatStatus.cooling;
      } else if (fields[8] == 'HEAT') {
        statusValue = ThermostatStatus.heating;
      } else {
        throw 'Unknown thermostat mode "${fields[8]}" in status message: $message';
      }
    } else if (fields[9] == '0') {
      if (fields[3] == 'FAN ON') {
        statusValue = ThermostatStatus.fan;
      } else if (fields[3] == 'FAN AUTO') {
        statusValue = ThermostatStatus.idle;
      } else {
        throw 'Unknown thermostat fan mode "${fields[3]}" in status message: $message';
      }
    } else {
      throw 'Unknown thermostat stage "${fields[9]}" in status message: $message';
    }
    temperature.add(temperatureValue != null ? new ThermostatTemperature.C(temperatureValue, station: _station, timestamp: timestamp) : null);
    status.add(statusValue);
  }

  Completer<Null> _signal = new Completer<Null>();
  void _triggerSignal() {
    _signal.complete();
    _signal = new Completer<Null>();
  }

  bool _active = true;
  bool _temperatureSubscriptionActive = false;
  bool _statusSubscriptionActive = false;

  void _startPollingTemperature(Sink<Temperature> sink) {
    assert(!_temperatureSubscriptionActive);
    _temperatureSubscriptionActive = true;
    _triggerSignal();
  }

  void _endPollingTemperature() {
    assert(_temperatureSubscriptionActive);
    _temperatureSubscriptionActive = false;
    _triggerSignal();
  }

  void _startPollingStatus(Sink<ThermostatStatus> sink) {
    assert(!_statusSubscriptionActive);
    _statusSubscriptionActive = true;
    _triggerSignal();
  }

  void _endPollingStatus() {
    assert(_statusSubscriptionActive);
    _statusSubscriptionActive = false;
    _triggerSignal();
  }

  Future<Null> _ledThrottle = new Future<Null>.value();

  /// LEDs cannot be updated more often than about once every 1000ms
  /// without the updates being faster than the thermostat actually
  /// reads the state and updates the physical LEDs.
  Future<Null> setLeds({ bool red, bool green, bool yellow }) async {
    await _ledThrottle;
    await Future.wait<Null>(<Future<Null>>[
      _sendLed('R', value: red),
      _sendLed('G', value: green),
      _sendLed('Y', value: yellow),
    ]);
    _ledThrottle = new Future<Null>.delayed(const Duration(milliseconds: 1000));
  }

  Future<Null> _sendLed(String code, { @required bool value }) async {
    if (value == null)
      return;
    assert(code == 'R' || code == 'G' || code == 'Y');
    await _send('WL$code', 'WL${code}1D${value ? '1' : '0'}');
  }

  Future<Null> heat() async {
    // heat - WNMS1DH WNFM1DA WNCD1D42 WNHD1D31
    await Future.wait<String>(<Future<String>>[
      _send('WNMS', 'WNMS1DH'),
      _send('WNFM', 'WNFM1DA'),
      _send('WNCD', 'WNCD1D42'),
      _send('WNHD', 'WNHD1D31'),
    ]);
  }

  Future<Null> cool() async {
    // cool - WNMS1DC WNFM1DA WNCD1D16 WNHD1D3
    await Future.wait<String>(<Future<String>>[
      _send('WNMS', 'WNMS1DC'),
      _send('WNFM', 'WNFM1DA'),
      _send('WNCD', 'WNCD1D16'),
      _send('WNHD', 'WNHD1D3'),
    ]);
  }

  Future<Null> fan() async {
    // fan - WNMS1DO WNFM1DO
    await Future.wait<String>(<Future<String>>[
      _send('WNMS', 'WNMS1DO'),
      _send('WNFM', 'WNFM1DO'),
    ]);
  }

  Future<Null> off() async {
    // off - WNMS1DO WNFM1DA
    await Future.wait<String>(<Future<String>>[
      _send('WNMS', 'WNMS1DO'),
      _send('WNFM', 'WNFM1DA'),
    ]);
  }

  Future<Null> auto({ bool occupied: false }) async {
    assert(occupied != null);
    if (occupied) {
      await Future.wait<String>(<Future<String>>[
        _send('WNMS', 'WNMS1DA'),
        _send('WNFM', 'WNFM1DA'),
        _send('WNCD', 'WNCD1D27'),
        _send('WNHD', 'WNHD1D23'),
      ]);
    } else {
      await Future.wait<String>(<Future<String>>[
        _send('WNMS', 'WNMS1DA'),
        _send('WNFM', 'WNFM1DA'),
        _send('WNCD', 'WNCD1D32'),
        _send('WNHD', 'WNHD1D18'),
      ]);
    }
  }

  final Map<Object, _PendingCommand> _commands = <Object, _PendingCommand>{};

  Future<String> _send(Object key, String message) {
    _PendingCommand command = new _PendingCommand(message);
    if (_commands.containsKey(key)) {
      if (verbose)
        log('replacing old message with key "$key" with new message: $message');
      _commands.remove(key);
    } else {
      if (verbose)
        log('queuing new message with key "$key": $message');
    }
    _commands[key] = command;
    _triggerSignal();
    return command.result;
  }

  bool get _connectionRequired => _temperatureSubscriptionActive || _statusSubscriptionActive || _commands.isNotEmpty;

  Future<Null> _initialize() async {
    while (_active) {
      while (_connectionRequired) {
        Socket connection;
        try {
          connection = await Socket.connect(host, port);
          connection.encoding = utf8;
          final StreamBuffer<String> buffer = new StreamBuffer<String>(
            connection.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()),
          );
          await _verify(connection, buffer, 'WML1D$username,$password', <String, String>{
            'OK,USER,NO': null,
            'OK,USER,YES': 'Insufficient access rights for thermostat.',
            'INVALID LOGIN': 'Invalid thermostat credentials.',
            'BAD COMMAND': 'Thermostat did not recognize authentication command.',
            null: 'Could not connect to thermostat.'
          });
          const String brandName = 'RP32-IP';
          await _verify(connection, buffer, 'REV1', <String, String>{
            'REV1:$brandName,V2.40': null,
            null: 'Thermostat firmware revision not supported.',
          });
          await _verify(connection, buffer, 'RDS1', <String, String>{
            // No idea what this is, but given that the NetX software
            // will literally attempt to reboot the thermostat
            // ("WMRN1DREBOOT") if this doesn't get returned correctly,
            // I'm guessing we don't want to mess around sending other
            // commands if it's not right.
            'RDS1:VALID': null,
            null: 'Thermostat appears to be in an invalid state.',
          });
          await _verify(connection, buffer, 'RDC1', <String, String>{
            'RDC1:0,1,1,0,1,0,1,0': null,
            null: 'Thermostat DIP switches are not in the expected configuration.',
          });
          await _verify(connection, buffer, 'RTS1', <String, String>{
            'RTS1:CELSIUS': null,
            null: 'Thermostat must be configured to use Celsius units.',
          });
          final String thermostatName = await _readValue(connection, buffer, 'RMTN1', expectPrefix: true);
          log('connected to thermostat "$thermostatName" at ${host.host}:$port.');
          _station = new MeasurementStation(siteName: thermostatName, agencyName: brandName);
          if (verbose)
            log('message queue has ${_commands.length} commands.');
          while (_connectionRequired) {
            if (_commands.isNotEmpty) {
              Object key = _commands.keys.first;
              _PendingCommand command = _commands[key];
              String result = await _rawSend(connection, buffer, command.message);
              _commands.remove(key);
              command._completer.complete(result);
            }
            if (_temperatureSubscriptionActive || _statusSubscriptionActive) {
              String result = await _rawSend(connection, buffer, 'RAS1');
              _processStatus(result);
              if (_commands.isEmpty)
                await Future.any(<Future<Null>>[_signal.future, new Future<Null>.delayed(period)]);
            }
          }
        } catch (error) {
          await Future.wait(<Future<Null>>[
            fail(error),
            new Future<Null>.delayed(const Duration(seconds: 10)),
          ]);
        } finally {
          try {
            connection?.destroy();
          } catch (error) {
            await fail(error);
          } 
        }
      }
      await _signal.future;
    }
  }

  Future<Null> _verify(Socket connection, StreamBuffer<String> buffer, String command, Map<String, String> responses) async {
    assert(responses.containsKey(null));
    String result = await _rawSend(connection, buffer, command);
    String response;
    if (responses.containsKey(result)) {
      response = responses[result];
      if (response == null)
        return;
    } else {
      response = responses[null];
    }
    throw '$response ("$command" received "$result")';
  }

  Future<String> _readValue(Socket connection, StreamBuffer<String> buffer, String command, { @required bool expectPrefix }) async {
    assert(expectPrefix != null);
    String result = await _rawSend(connection, buffer, command);
    if (result == 'BAD COMMAND')
      throw 'Thermostat did not recognize "$command" command.';
    if (!expectPrefix)
      return result;
    if (!result.startsWith('$command:'))
      throw 'Thermostat responded unexpectedly to "$command": $result';
    return result.substring(command.length + 1, result.length);
  }

  Future<String> _rawSend(Socket connection, StreamBuffer<String> buffer, String command) async {
    if (verbose)
      log('>> $command');
    connection.writeln(command);
    // We throttle the traffic to avoid overloading the thermostat.
    await new Future<Null>.delayed(const Duration(milliseconds: 50));
    String result = await buffer.readValue();
    if (verbose)
      log('<< $result');
    return result;
  }

  Future<Null> fail(dynamic error) async {
    if (onError != null)
      await onError(error);
  }

  void log(String message) {
    if (onLog != null)
      onLog(message);
  }

  void dispose() {
    assert(_active);
    _active = false;
    _triggerSignal();
  }
}

enum TemperatureScale { fahrenheit, celsius }

class ThermostatTemperature extends Temperature {
  factory ThermostatTemperature(TemperatureScale scale, double temperature, {
    @required MeasurementStation station,
    @required DateTime timestamp,
  }) {
    assert(scale != null);
    assert(temperature != null);
    switch (scale) {
      case TemperatureScale.fahrenheit: return new ThermostatTemperature.F(temperature, station: station, timestamp: timestamp);
      case TemperatureScale.celsius: return new ThermostatTemperature.C(temperature, station: station, timestamp: timestamp);
    }
    return null;
  }

  ThermostatTemperature.F(this._value, {
    @required MeasurementStation station,
    @required DateTime timestamp,
  }) : _valueIsF = true,
       super(station: station, timestamp: timestamp);

  ThermostatTemperature.C(this._value, {
    @required MeasurementStation station,
    @required DateTime timestamp,
  }) : _valueIsF = false,
       super(station: station, timestamp: timestamp);

  final double _value;
  final bool _valueIsF;

  @override
  double get fahrenheit => _valueIsF ? _value : celsius * 9.0 / 5.0 + 32.0;
  
  @override
  double get celsius => _valueIsF ? (fahrenheit - 32.0) * 5.0 / 9.0 : _value;
}

class StreamBuffer<T> {
  StreamBuffer(Stream<T> stream) {
    stream.listen((T value) {
      _values.add(value);
      if (_signals.isNotEmpty)
        _signals.removeAt(0).complete();
    });
  }

  List<T> _values = <T>[];

  List<Completer<Null>> _signals = <Completer<Null>>[];

  Future<T> readValue() async {
    if (_values.isEmpty || _signals.isNotEmpty) {
      Completer<Null> completer = new Completer<Null>();
      _signals.add(completer);
      await completer.future;
    }
    return _values.removeAt(0);
  }
}
