import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'watch_stream.dart';

// This is written for the Sharp LC-70UD27U TV.

const Duration _reconnectDelay = const Duration(milliseconds: 750); // how quickly to reconnect
const Duration _connectTimeout = const Duration(seconds: 10); // how long to try to connect for
const Duration _inactivityTimeout = const Duration(seconds: 2); // how long to wait before disconnecting when idle
const Duration _responseTimeout = const Duration(seconds: 10); // how long to wait for a response before giving up
const Duration _retryDelay = const Duration(milliseconds: 150); // how quickly to resend when retrying for an expected response
const Duration _retryTimeout = const Duration(seconds: 40); // how long to keep retrying for the expected response

const bool _debugDumpTraffic = false;

String get _timestamp => new DateTime.now().toIso8601String().padRight(26, '0');

typedef void AbortWatcher(String message);

class TelevisionException implements Exception {
  const TelevisionException(this.message, this.response, this.television);
  final Television television;
  final String response;
  final String message;
  @override
  String toString() {
    if (response != null)
      return '$message: "$response"';
    return '$message.';
  }
}

class TelevisionTimeout extends TelevisionException {
  const TelevisionTimeout(String message, String response, Television television)
    : super(message, response, television);
}

class TelevisionErrorResponse extends TelevisionException {
  const TelevisionErrorResponse(String message, String response, Television television)
    : super(message, response, television);
}

/// Created by [Television.openTransaction].
class TelevisionTransaction {
  TelevisionTransaction._(this.television) {
    assert(television != null);
    assert(television._currentTransaction == null);
    television._currentTransaction = this;
    _done.future.catchError((dynamic error) { }); // so that this future can be ignored without reporting uncaught errors
  }

  final Television television;

  final Completer<Null> _done = new Completer<Null>();
  Future<Null> get done => _done.future;
  TelevisionException _error;

  void sendLine(String message) {
    if (_error != null)
      throw _error;
    assert(television._currentTransaction == this);
    assert(!_done.isCompleted);
    if (_debugDumpTraffic)
      print('$_timestamp ==> $message');
    television._socket.write('$message\x0d');
  }

  Future<String> readLine() async {
    if (_error != null)
      throw _error;
    assert(television._currentTransaction == this);
    assert(!_done.isCompleted);
    television.resetTimeout(_responseTimeout, 'Timed out awaiting response');
    await television._responses.moveNext();
    if (_debugDumpTraffic)
      print('$_timestamp <== ${television._responses.current}');
    return television._responses.current;
  }

  void close() {
    if (_error != null)
      throw _error;
    assert(television._currentTransaction == this);
    assert(!_done.isCompleted);
    _done.complete();
    television._currentTransaction = null;
    television.resetTimeout(_inactivityTimeout, 'Idle timeout after transaction.');
    if (television._transactionQueue != null && television._transactionQueue.isNotEmpty)
      television._transactionQueue.removeFirst().complete();
  }

  void _closeWithError(TelevisionException error) {
    assert(television._currentTransaction == this);
    assert(!_done.isCompleted);
    assert(_error == null);
    _error = error;
    _done.completeError(error);
    if (television._transactionQueue != null) {
      while (television._transactionQueue.isNotEmpty)
        television._transactionQueue.removeFirst().completeError(error);
    }
  }
}

enum TelevisionRemote {
  key0, key1, key2, key3, key4, key5, key6, key7, key8, key9, keyDot,
  keyEnt, keyPower, keyDisplay, keyPowerSource, keyRW, keyPlay, keyFF,
  keyPause, keyPrev, keyStop, keyNext, keyRecord, keyOption, keySleep,
  keyRecordStop, keyPowerSaving, keyClosedCaptions, keyAvMode,
  keyViewMode, keyFlashback, keyMute, keyVolDown, keyVolUp,
  keyChannelUp, keyChannelDown, keyInput, keyReserved37, keyMenu,
  keySmartCentral, keyEnter, keyUp, keyDown, keyLeft, keyRight,
  keyReturn, keyExit, keyCh, keyReserved48, keyReserved49, keyA, keyB,
  keyC, keyD, keyFreeze, keyApp1, keyApp2, keyApp3, key2D3D,
  keyNetFlix, keyAAL, keyManual,
}

enum TelevisionOffTimer {
  disabled, min30, min60, min90, min120,
}

enum TelevisionSource {
  analog, // reported by TV, never sent to TV
  analogAir,
  analogCable,
  digitalAir,
  digitalCableOnePart, // sent to TV, never reported by TV
  digitalCableTwoPart, // reported by TV, never sent to TV
  hdmi1,
  hdmi2,
  hdmi3,
  hdmi4, // HDCP 2.2
  input5, // composite or component
  composite,
  component,
  ethernet, // home network, not reliably reported by TV
  storage, // SD card or USB input, not reliably reported by TV
  miracast, // not reliably reported by TV
  bluetooth, // not reliably reported by TV
  manual, // documentation manual screen, not reliably reported by TV
  unknown, // reported by TV for options marked unreliable above, never sent to TV
  switching, // reported by TV, never sent to TV
  off,
}

class TelevisionChannel {
  TelevisionChannel.raw({
    this.source,
    this.POWR,
    this.RDIN,
    this.IDIN,
    this.DCCH,
    this.DA2P,
    this.DC2U,
    this.DC2L,
    this.DC10,
    this.DC11,
    this.IAVD,
    this.INP5,
    this.ITGD,
  });
  
  factory TelevisionChannel.fromValues({
    String POWR,
    String RDIN,
    String IDIN,
    String DCCH,
    String DA2P,
    String DC2U,
    String DC2L,
    String DC10,
    String DC11,
    String IAVD,
    String INP5,
  }) {
    TelevisionSource source;
    if (POWR == '0') {
      if (RDIN == 'ERR' && IDIN == 'ERR' && IAVD == 'ERR') {
        source = TelevisionSource.off;
      } else {
        source = TelevisionSource.unknown;
      }
    } else if (POWR == '1') {
      if (RDIN == 'ERR' && IDIN == 'ERR' && IAVD == 'ERR') {
        source = TelevisionSource.switching;
      } else if (RDIN == '5000' && IDIN == '50' && IAVD == '1') {
        source = TelevisionSource.hdmi1;
      } else if (RDIN == '5100' && IDIN == '51' && IAVD == '2') {
        source = TelevisionSource.hdmi2;
      } else if (RDIN == '5200' && IDIN == '52' && IAVD == '3') {
        source = TelevisionSource.hdmi3;
      } else if (RDIN == '5300' && IDIN == '53' && IAVD == '4') {
        source = TelevisionSource.hdmi4;
      } else if (RDIN == '1100' && IDIN == '11' && IAVD == '5' && INP5 == '0') {
        source = TelevisionSource.input5;
      } else if (RDIN == '1100' && IDIN == '11' && IAVD == '5' && INP5 == '1') {
        source = TelevisionSource.composite;
      } else if (RDIN == '1100' && IDIN == '11' && IAVD == '5' && INP5 == '2') {
        source = TelevisionSource.component;
      } else if (RDIN == '0100' && IDIN == '1') {
        source = TelevisionSource.analog;
      } else if (RDIN == '0300' && IDIN == '3') {
        source = TelevisionSource.digitalAir;
      } else if (RDIN == '0400' && IDIN == '3') {
        source = TelevisionSource.digitalCableTwoPart;
      } else if (RDIN == '-100' && IDIN == 'ERR') {
        // Could be miracast, bluetooth, the manual, NetFlix...
        source = TelevisionSource.unknown;
      } else if (IDIN == '11') {
        // Either storage, usb, or ethernet.
        // RDIN value will be bogus.
        // (That's according to my notes from when I reverse-engineered the
        // protocol. It doesn't seem to still be the case. Now it seems IDIN
        // is ERR in the same cases as RDIN.)
        source = TelevisionSource.unknown;
      } else {
        // It seems likely that there are combinations here that might be returned
        // that aren't reflected in the list above, especially around cable/air
        // analog/digital channels.
        source = TelevisionSource.unknown;
      }
    } else {
      // POWR is in a weird state.
      source = TelevisionSource.unknown;
    }
    assert(source != null);
    return new TelevisionChannel.raw(
      source: source,
      POWR: POWR,
      RDIN: RDIN,
      IDIN: IDIN,
      DCCH: DCCH,
      DA2P: DA2P,
      DC2U: DC2U,
      DC2L: DC2L,
      DC10: DC10,
      DC11: DC11,
      IAVD: IAVD,
      INP5: INP5,
    );
  }
  
  factory TelevisionChannel.fromSource(TelevisionSource source) {
    switch (source) {
      case TelevisionSource.analogAir:
        return new TelevisionChannel.raw(
          source: source,
          POWR: '1',
          IDIN: '1',
        );
      case TelevisionSource.analogCable:
        return new TelevisionChannel.raw(
          source: source,
          POWR: '1',
          IDIN: '0',
        );
      case TelevisionSource.digitalAir:
        return new TelevisionChannel.raw(
          source: source,
          POWR: '1',
          IDIN: '3',
        );
      case TelevisionSource.digitalCableTwoPart:
        return new TelevisionChannel.raw(
          source: source,
          POWR: '1',
          IDIN: '2',
        );
      case TelevisionSource.digitalCableOnePart:
        return new TelevisionChannel.raw(
          source: source,
          POWR: '1',
          IDIN: '4',
        );
      case TelevisionSource.hdmi1:
        return new TelevisionChannel.raw(
          source: source,
          POWR: '1',
          IAVD: '1',
          // we could use IDIN 11 or IDIN 50, but those return ERR if you're already on that input
        );
      case TelevisionSource.hdmi2:
        return new TelevisionChannel.raw(
          source: source,
          POWR: '1',
          IAVD: '2',
          // we could use IDIN 12 or IDIN 51, but those return ERR if you're already on that input
        );
      case TelevisionSource.hdmi3:
        return new TelevisionChannel.raw(
          source: source,
          POWR: '1',
          IAVD: '3',
          // we could use IDIN 13 or IDIN 52, but those return ERR if you're already on that input
        );
      case TelevisionSource.hdmi4:
        return new TelevisionChannel.raw(
          source: source,
          POWR: '1',
          IAVD: '4',
          // we could use IDIN 14 or IDIN 53, but those return ERR if you're already on that input
        );
      case TelevisionSource.input5: // composite or component
        return new TelevisionChannel.raw(
          source: source,
          POWR: '1',
          IAVD: '5',
          // we could also use IDIN 15
          // we could also set INP5 to 0, which might mean "automatic selection"
        );
      case TelevisionSource.composite:
        return new TelevisionChannel.raw(
          source: source,
          POWR: '1',
          INP5: '1',
        );
      case TelevisionSource.component:
        return new TelevisionChannel.raw(
          source: source,
          POWR: '1',
          INP5: '2',
        );
      case TelevisionSource.ethernet: // home network
        return new TelevisionChannel.raw(
          source: source,
          POWR: '1',
          IDIN: '81',
        );
      case TelevisionSource.storage: // SD card or USB input
        return new TelevisionChannel.raw(
          source: source,
          POWR: '1',
          IDIN: '82',
        );
      case TelevisionSource.miracast:
        return new TelevisionChannel.raw(
          source: source,
          POWR: '1',
          IDIN: '82',
          ITGD: 1,
        );
      case TelevisionSource.bluetooth:
        return new TelevisionChannel.raw(
          source: source,
          POWR: '1',
          IDIN: '82',
          ITGD: 2,
        );
      case TelevisionSource.manual: // documentation manual screen
        return new TelevisionChannel.raw(
          source: source,
          POWR: '1',
          // client must special-case "manual" to mean "hit the manual key on the remote"
        );
      case TelevisionSource.off:
        return new TelevisionChannel.raw(
          source: source,
          POWR: '0',
        );
      case TelevisionSource.analog:
      case TelevisionSource.unknown:
      case TelevisionSource.switching:
        break; // must be last in switch statement
    }
    throw new TelevisionException('Selected source is too ambiguous', source.toString(), null);
  }

  // Create a source object to represent a specific TV channel.
  //
  // For analog channels, zero-pad (two for air, three for cable).
  //
  // For digital channels, give the full code (zero-padded if necessary) in the
  // form ##.## (air) or ###.### or ##### (cable).
  factory TelevisionChannel.tv(String channel) {
    assert(!channel.contains(new RegExp(r'[^0-9.]')));
    final String format = channel.replaceAll(new RegExp(r'[0-9]'), '#');
    switch (format) {
      case '##': // 02-69
        return new TelevisionChannel.raw(
          source: TelevisionSource.analogAir,
          IDIN: '1',
          DCCH: int.parse(channel, radix: 10).toString(),
        );
      case '###': // 001-135
        return new TelevisionChannel.raw(
          source: TelevisionSource.analogCable,
          IDIN: '0',
          DCCH: int.parse(channel, radix: 10).toString(),
        );
      case '##.##': // 01-99 . 00-99
        return new TelevisionChannel.raw(
          source: TelevisionSource.digitalAir,
          DA2P: '${channel[0]}${channel[1]}${channel[3]}${channel[4]}',
        );
      case '###.###': // 001-999 . 000-999
        return new TelevisionChannel.raw(
          source: TelevisionSource.digitalCableTwoPart,
          DC2U: '${channel[0]}${channel[1]}${channel[2]}',
          DC2L: '${channel[3]}${channel[4]}${channel[5]}',
        );
      case '0####': // 00000-09999
        return new TelevisionChannel.raw(
          source: TelevisionSource.digitalCableOnePart,
          DC10: '${channel[1]}${channel[2]}${channel[3]}${channel[4]}',
        );
      case '1####': // 10000-16383
        return new TelevisionChannel.raw(
          source: TelevisionSource.digitalCableOnePart,
          DC11: '${channel[1]}${channel[2]}${channel[3]}${channel[4]}',
        );
      default:
        throw new TelevisionException('Unknown TV channel format', format, null);
    }
  }

  final TelevisionSource source;

  final String POWR; // reported by TV, never sent by .fromSource or .tv constructors
  final String RDIN; // reported by TV, never sent to TV
  final String IDIN;
  final String DCCH;
  final String DA2P;
  final String DC2U;
  final String DC2L;
  final String DC10;
  final String DC11;
  final String IAVD;
  final String INP5;
  final int ITGD; // number of times to send it; sent to TV, never reported by TV

  String _fieldsToString() {
    List<String> buffer = <String>[];
    if (POWR != null)
      buffer.add('POWR="$POWR"');
    if (RDIN != null)
      buffer.add('RDIN="$RDIN"');
    if (IDIN != null)
      buffer.add('IDIN="$IDIN"');
    if (DCCH != null)
      buffer.add('DCCH="$DCCH"');
    if (DA2P != null)
      buffer.add('DA2P="$DA2P"');
    if (DC2U != null)
      buffer.add('DC2U="$DC2U"');
    if (DC2L != null)
      buffer.add('DC2L="$DC2L"');
    if (DC10 != null)
      buffer.add('DC10="$DC10"');
    if (DC11 != null)
      buffer.add('DC11="$DC11"');
    if (IAVD != null)
      buffer.add('IAVD="$IAVD"');
    if (INP5 != null)
      buffer.add('INP5="$INP5"');
    if (buffer.isEmpty)
      buffer.add('no data');
    return buffer.join(' ');
  }

  @override
  String toString({ bool detailed: false }) {
    if (detailed)
      return '$source (${_fieldsToString()})';
    switch (source) {
      case TelevisionSource.analogAir:
        if (DCCH != null)
          return 'analog air channel ${DCCH.padLeft(2, "0")}';
        return 'last analog air channel';
      case TelevisionSource.analogCable:
        if (DCCH != null)
          return 'analog cable channel ${DCCH.padLeft(3, "0")}';
        return 'last analog cable channel';
      case TelevisionSource.digitalAir:
        if (DA2P != null)
          return 'digital air channel ${DA2P.substring(0, 2).padLeft(2, "0")}.${DA2P.substring(2, 4).padLeft(2, "0")}';
        return 'last digital air channel';
      case TelevisionSource.digitalCableOnePart:
        if (DC10 != null && DC11 != null)
          return 'digital cable channel, either 0${DC10.padLeft(4, "0")} or 1${DC11.padLeft(4, "0")}';
        if (DC10 != null)
          return 'digital cable channel 0${DC10.padLeft(4, "0")}';
        if (DC11 != null)
          return 'digital cable channel 1${DC11.padLeft(4, "0")}';
        return 'last one-part digital cable channel';
      case TelevisionSource.digitalCableTwoPart:
        if (DC2U != null && DC2L != null)
          return 'digital cable channel ${DC2U.padLeft(3, "0")}.${DC2L.padLeft(3, "0")}';
        if (DC2U != null)
          return 'digital cable channel ${DC2U.padLeft(3, "0")}.???';
        if (DC2L != null)
          return 'digital cable channel ???.${DC2L.padLeft(3, "0")}';
        return 'last two-part digital cable channel';
      case TelevisionSource.hdmi1:
        return 'HDMI1';
      case TelevisionSource.hdmi2:
        return 'HDMI2';
      case TelevisionSource.hdmi3:
        return 'HDMI3';
      case TelevisionSource.hdmi4:
        return 'HDMI4';
      case TelevisionSource.input5:
        return 'input 5'; // component or composite
      case TelevisionSource.composite:
        return 'composite';
      case TelevisionSource.component:
        return 'component';
      case TelevisionSource.ethernet:
        return 'ethernet';
      case TelevisionSource.storage:
        return 'storage';
      case TelevisionSource.miracast:
        return 'miracast';
      case TelevisionSource.bluetooth:
        return 'bluetooth';
      case TelevisionSource.manual:
        return 'the manual';
      case TelevisionSource.switching:
        return 'switching...';
      case TelevisionSource.analog:
        if (DCCH != null)
          return 'analog channel $DCCH';
        return 'last analog channel';
      case TelevisionSource.unknown:
        return 'unknown';
        break;
      case TelevisionSource.off:
        return 'off';
        break;
    }
    return null;
  }
}

class Television {
  Television({
    this.host,
    this.port: 10002,
    this.username,
    this.password,
  }) {
    assert(port != null);
    _connectionStream = new AlwaysOnWatchStream<bool>();
    _connectionStream.add(false);
  }

  final InternetAddress host;
  final int port;
  final String username;
  final String password;

  WatchStream<bool> _connectionStream;

  Stream<bool> get connected => _connectionStream;

  // NETWORK

  Socket _socket;
  StreamIterator<String> _responses;
  TelevisionTransaction _currentTransaction;
  Timer _inactivityTimer;

  Future<Null> _connecting;

  Future<Null> _connect({
    Duration delay: _reconnectDelay,
    Duration timeout: _connectTimeout,
  }) async {
    if (_socket != null) {
      assert(_responses != null);
      if (_currentTransaction == null)
        resetTimeout(_inactivityTimeout, 'Idle timeout after redundant connection request.');
      return null;
    }
    if (_connecting != null)
      return _connecting;
    Completer<Null> connectingCompleter = new Completer<Null>();
    _connecting = connectingCompleter.future;
    try {
      assert(_responses == null);
      assert(_currentTransaction == null);
      assert(_inactivityTimer == null);
      InternetAddress host = this.host;
      if (host == null) {
        try {
          final List<InternetAddress> hosts = await InternetAddress.lookup('tv.');
          if (hosts.isEmpty)
            throw new TelevisionException('Could not resolve TV in DNS', null, this);
          host = hosts.first;
        } on SocketException {
          throw new TelevisionException('Could not resolve TV in DNS', null, this);
        }
      }
      Socket socket;
      StreamIterator<String> responses;
      List<dynamic> errors;
      bool canceled = false;
      Timer timeoutTimer = new Timer(timeout, () {
        canceled = true;
      });
      try {
        do {
          try {
            if (_debugDumpTraffic)
              print('$_timestamp ---- CONNECTING ----');
            socket = await Socket.connect(host, port);
            socket.encoding = UTF8;
            socket.write('$username\x0d$password\x0d');
            await socket.flush();
            responses = new StreamIterator<String>(socket.transform(UTF8.decoder).transform(const LineSplitter()));
            await responses.moveNext();
            if (responses.current != 'Login:')
              throw new TelevisionException('Did not get login prompt from television', responses.current, this);
            await responses.moveNext();
            if (responses.current != 'Password:')
              throw new TelevisionException('Did not get password prompt from television', responses.current, this);
          } catch (error) {
            if ((error is TelevisionException) ||
                ((error is SocketException) && (error.osError.errorCode == 32))) { // broken pipe - they accepted the connection then closed it on us
              errors ??= <dynamic>[];
              errors.add(error);
              socket?.destroy();
              socket = null;
              await new Future<Null>.delayed(delay); // too fast and it won't even open the socket
            } else {
              rethrow;
            }
          }
        } while (socket == null && !canceled);
      } finally {
        timeoutTimer.cancel();
      }
      if (socket == null) {
        assert(errors.isNotEmpty);
        throw new TelevisionTimeout(
          'timed out trying to connect; '
          'had ${errors.length} failure${ errors.length == 1 ? "" : "s" }, '
          'first was: ${errors.first}',
          null,
          this,
        );
      }
      _connectionStream.add(true);
      _socket = socket;
      _responses = responses;
      _currentTransaction = null;
      resetTimeout(_inactivityTimeout, 'Idle timeout after connection.');
      _socket.done.whenComplete(() {
        if (_socket == socket) {
          assert(_responses == responses);
          abort('Connection lost.');
        }
      });
    } finally {
      connectingCompleter.complete();
      _connecting = null;
    }
  }

  void resetTimeout(Duration duration, String message) {
    _inactivityTimer?.cancel();
    _inactivityTimer = new Timer(duration, () { abort(message, timeout: true); });
  }

  Set<AbortWatcher> _abortWatchers = new Set<AbortWatcher>();

  void abort(String message, { bool timeout: false }) {
    if (_debugDumpTraffic)
      print('$_timestamp ---- DISCONNECTING - $message ----');
    TelevisionException error;
    if (timeout) {
      error = new TelevisionTimeout(message, null, this);
    } else {
      error = new TelevisionException(message, null, this);
    }
    _currentTransaction?._closeWithError(error);
    _currentTransaction = null;
    _socket.destroy();
    _socket = null;
    _responses.cancel();
    _responses = null;
    _inactivityTimer.cancel();
    _inactivityTimer = null;
    _connectionStream.add(false);
    for (AbortWatcher callback in _abortWatchers.toList())
      callback(message);
  }

  void dispose() {
    abort('Shutting down...');
    _connectionStream.close();
  }

  Queue<Completer<Null>> _transactionQueue;

  Future<TelevisionTransaction> openTransaction() async {
    if (_currentTransaction != null) {
      _transactionQueue ??= new Queue<Completer<Null>>();
      Completer<Null> completer = new Completer<Null>();
      _transactionQueue.addLast(completer);
      await completer.future;
      assert(_currentTransaction == null);
    }
    // It is critical that there be no asynchronous anything between the check
    // where _currentTransaction == null above and the call to the
    // TelevisionTransaction constructor below.
    assert(_currentTransaction == null);
    final TelevisionTransaction transaction = new TelevisionTransaction._(this);
    assert(_currentTransaction == transaction);
    return transaction;
  }

  // PROTOCOL

  Future<TelevisionTransaction> sendMessage(String command, String argument) async {
    assert(command != null);
    assert(command.length == 4);
    assert(argument != null);
    final String message = '$command${argument.padRight(4, ' ')}';
    await _connect();
    final TelevisionTransaction result = await openTransaction();
    result.sendLine(message);
    return result;
  }

  /// Open a transaction to send the given command.
  ///
  /// Returns true on success. If `errorIsOk` is true, returns false on an `ERR`
  /// response. Otherwise, throws on error.
  Future<bool> sendCommand(String message, { String argument = '', bool errorIsOk: false }) async {
    try {
      final TelevisionTransaction transaction = await sendMessage(message, argument);
      final String response = await transaction.readLine();
      transaction.close();
      if (errorIsOk && response == 'ERR')
        return false;
      if (response != 'OK')
        throw new TelevisionErrorResponse('Response to "$message$argument" was unexpectedly not "OK"', response, this);
    } on TelevisionException {
      if (errorIsOk)
        return false;
      rethrow;
    }
    return true;
  }

  Future<String> readRawValue(String message, [ String argument = '?' ] ) async {
    final TelevisionTransaction transaction = await sendMessage(message, argument);
    final String response = await transaction.readLine();
    transaction.close();
    return response;
  }

  Future<Null> matchingResponse(String message, {
    String argument: '?',
    String desiredResponse: 'OK',
    Duration delay: _retryDelay,
    Duration timeout: _retryTimeout,
  }) async {
    String canceled;
    Timer timeoutTimer = new Timer(timeout, () {
      abort('Timed out awaiting desired response to "$message"', timeout: true);
    });
    AbortWatcher handleAbort = (String message) { canceled = message; };
    _abortWatchers.add(handleAbort);
    try {
      while (canceled == null) {
        try {
          if (await readRawValue(message, argument) == desiredResponse)
            break;
        } on TelevisionException {
          // retry
        }
        await new Future<Null>.delayed(delay);
      }
    } finally {
      timeoutTimer.cancel();
      _abortWatchers.remove(handleAbort);
    }
    if (canceled != null)
      throw new TelevisionTimeout(canceled, null, this);
  }

  Future<Null> nonErrorResponse(String message, {
    String argument: '?',
    Duration delay: _retryDelay,
    Duration timeout: _retryTimeout,
    bool skipOk: false,
  }) async {
    String canceled;
    Timer timeoutTimer = new Timer(timeout, () {
      abort('Timed out awaiting successful response to "$message"', timeout: true);
    });
    AbortWatcher handleAbort = (String message) { canceled = message; };
    _abortWatchers.add(handleAbort);
    try {
      while (canceled == null) {
        try {
          final TelevisionTransaction transaction = await sendMessage(message, argument);
          String response = await transaction.readLine();
          if (skipOk && response == 'OK')
            response = await transaction.readLine();
          transaction.close();
          if (response != 'ERR')
            break;
        } on TelevisionException {
          // retry
        }
        await new Future<Null>.delayed(delay);
      }
    } finally {
      timeoutTimer.cancel();
      _abortWatchers.remove(handleAbort);
    }
    if (canceled != null)
      throw new TelevisionTimeout(canceled, null, this);
  }

  Future<String> readValue(String message, { String argument: '?', bool errorIsNull: true }) async {
    try {
      final String response = await readRawValue(message, argument);
      if (response == 'ERR') {
        if (errorIsNull)
          return null;
        throw new TelevisionErrorResponse('Unexpected response to "$message$argument"', response, this);
      }
      return response;
    } on TelevisionException {
      if (errorIsNull)
        return null;
      rethrow;
    }
  }

  // MESSAGES

  Future<Null> get inputStable => nonErrorResponse('RDIN', skipOk: true);

  Future<bool> get power async {
    final String response = await readValue('POWR', errorIsNull: false);
    switch (response) {
     case '0':
       return false;
     case '1':
       return true;
    }
    throw new TelevisionErrorResponse('Unknown response to "POWR" message', response, this);
  }

  Future<Null> setPower(bool value) async {
    final String argument = value ? '1' : '0';
    await matchingResponse('POWR', argument: argument);
    await matchingResponse('POWR', desiredResponse: argument);
    if (value)
      await inputStable;
  }

  Future<Null> sendRemote(TelevisionRemote key) async {
    await sendCommand('RCKY', argument: key.index.toString());
  }

  Future<Null> showMessage(String message) async {
    await sendCommand('KLCD', argument: message);
  }

  Future<Null> nextInput() async {
    await sendCommand('ITGD');
    await inputStable;
  }

  Future<Null> lastChannel() async {
    await sendCommand('ITVD');
    await inputStable;
  }

  Future<Null> channelUp() async {
    await sendCommand('CHUP');
    await inputStable;
  }

  Future<Null> channelDown() async {
    await sendCommand('CHDW');
    await inputStable;
  }

  Future<TelevisionChannel> get input async {
    final String POWR = await readRawValue('POWR');
    final String RDIN = await readRawValue('RDIN');
    final String IDIN = await readRawValue('IDIN');
    final String IAVD = await readRawValue('IAVD');
    final String INP5 = await readRawValue('INP5');
    if ((RDIN.length != null && RDIN.length > 0 && RDIN[0] == '0') || (IDIN != null && IDIN.length == 1)) {
      return new TelevisionChannel.fromValues(
        POWR: POWR,
        RDIN: RDIN,
        IDIN: IDIN,
        DCCH: await readRawValue('DCCH'),
        DA2P: await readRawValue('DA2P'),
        DC2U: await readRawValue('DC2U'),
        DC2L: await readRawValue('DC2L'),
        DC10: await readRawValue('DC10'),
        DC11: await readRawValue('DC11'),
        IAVD: IAVD,
        INP5: INP5,
      );
    } else {
      return new TelevisionChannel.fromValues(
        POWR: POWR,
        RDIN: RDIN,
        IDIN: IDIN,
        IAVD: IAVD,
        INP5: INP5,
      );
    }
  }

  Future<Null> setInput(TelevisionChannel value) async {
    assert(value.RDIN == null);
    // The order here is important.
    // In particular:
    //  - POWR before everything.
    //  - IDIN < DC2U < DC2L.
    //  - everything before ITGD.
    //  - IAVD < INP5.
    await setPower(value.POWR != '0');
    if (value.POWR != '0') {
      await inputStable;
      if (value.IDIN != null)
        await sendCommand('IDIN', argument: value.IDIN);
      if (value.DCCH != null)
        await sendCommand('DCCH', argument: value.DCCH);
      if (value.DA2P != null)
        await sendCommand('DA2P', argument: value.DA2P);
      if (value.DC2U != null)
        await sendCommand('DC2U', argument: value.DC2U);
      if (value.DC2L != null)
        await sendCommand('DC2L', argument: value.DC2L);
      if (value.DC10 != null)
        await sendCommand('DC10', argument: value.DC10);
      if (value.DC11 != null)
        await sendCommand('DC11', argument: value.DC11);
      if (value.IAVD != null) {
        bool result = await sendCommand('IAVD', argument: value.IAVD, errorIsOk: true);
        if (!result) {
          String current = await readRawValue('IAVD');
          if (current != value.IAVD)
            throw new TelevisionErrorResponse('Received error response to message "IAVD${value.IAVD}" but current IAVD status is "$current"', null, this);
        }
      }
      if (value.INP5 != null)
        await sendCommand('INP5', argument: value.INP5);
      if (value.ITGD != null && value.ITGD > 0) {
        for (int index = 0; index < value.ITGD; index += 1) {
          await inputStable;
          await sendCommand('ITGD');
        }
      }
      await inputStable;
      if (value.source == TelevisionSource.manual) {
        await sendRemote(TelevisionRemote.keyManual);
        await inputStable;
      }
    }
  }

  Future<int> get volume async {
    final String response = await readValue('VOLM');
    if (response == null)
      return null;
    try {
      return int.parse(response, radix: 10);
    } on FormatException {
      throw new TelevisionErrorResponse('Unknown response to "VOLM" message', response, this);
    }
  }

  Future<Null> setVolume(int value) async {
    assert(value >= 0);
    assert(value <= 100);
    await sendCommand('VOLM', argument: value.toString());
  }

  Future<bool> get muted async {
    final String response = await readValue('MUTE');
    if (response == null)
      return null;
    switch (response) {
     case '1':
       return true;
     case '2':
       return false;
    }
    throw new TelevisionErrorResponse('Unknown response to "MUTE" message', response, this);
  }

  Future<Null> setMuted(bool value) async {
    final String argument = value ? '1' : '2';
    await sendCommand('MUTE', argument: argument);
  }

  Future<Null> toggleMuted() async {
    await sendCommand('MUTE', argument: '0');
  }

  Future<int> get horizontalPosition async {
    final String response = await readValue('HPOS');
    if (response == null)
      return null;
    try {
      return int.parse(response, radix: 10);
    } on FormatException {
      throw new TelevisionErrorResponse('Unknown response to "HPOS" message', response, this);
    }
  }

  Future<Null> setHorizontalPosition(int value) async {
    assert(value >= -8);
    assert(value <= 8);
    await sendCommand('HPOS', argument: value.toString());
  }

  Future<int> get verticalPosition async {
    final String response = await readValue('VPOS');
    if (response == null)
      return null;
    try {
      return int.parse(response, radix: 10);
    } on FormatException {
      throw new TelevisionErrorResponse('Unknown response to "VPOS" message', response, this);
    }
  }

  Future<Null> setVerticalPosition(int value) async {
    assert(value >= -8);
    assert(value <= 8);
    await sendCommand('VPOS', argument: value.toString());
  }


  Future<int> get offTimer async {
    final String response = await readValue('OFTM');
    if (response == null)
      return null;
    try {
      int result = int.parse(response, radix: 10);
      if (result == 0)
        return null;
      return result;
    } on FormatException {
      throw new TelevisionErrorResponse('Unknown response to "OFTM" message', response, this);
    }
  }

  Future<Null> setOffTimer(TelevisionOffTimer value) async {
    assert(value != null);
    await sendCommand('OFTM', argument: value.index.toString());
  }

  Future<String> get name => readValue('TVNM', argument: '1');
  Future<String> get model => readValue('MNRD', argument: '1');
  Future<String> get softwareVersion => readValue('SWVN', argument: '1');

  Future<Null> displayMessage(String value) async {
    assert(value != null);
    await sendCommand('KLCD', argument: value);
  }

  Future<bool> get demoOverlay async {
    final String response = await readValue('DMSL');
    if (response == null)
      return null;
    switch (response) {
     case '0':
       return false;
     case '1':
       return true;
    }
    throw new TelevisionErrorResponse('Unknown response to "DMSL" message', response, this);
  }

  Future<Null> setDemoOverlay(bool value) async {
    final String argument = value ? '1' : '0';
    await sendCommand('DMSL', argument: argument);
  }

  // XXX AVMD - video mode
  // XXX ACSU - surround sound mode
  // XXX WIDE - stretch settings
  // XXX RSPW - ?
  // XXX ACHA - audio?
  // XXX CLCP - closed captions
  // XXX IPPV - ?
  // XXX CHWD - TV+Web mode -- very unstable, can require hard reboot
  // XXX GSEL - ?
  // XXX KLCC - ?
  // XXX RMDL - ?
  // XXX DX2U - ?
  // XXX SCPV - ?

}
