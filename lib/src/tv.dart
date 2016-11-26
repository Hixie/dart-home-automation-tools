import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'common.dart';
import 'watch_stream.dart';

// This is written for the Sharp LC-70UD27U TV.

const Duration _retryDelay = const Duration(milliseconds: 100);
const Duration _inactivityTimeout = const Duration(seconds: 2);
const Duration _connectTimeout = const Duration(seconds: 5);
const Duration _responseTimeout = const Duration(seconds: 40);

class TelevisionException implements Exception {
  const TelevisionException(this.message, this.response, this.television);
  final Television television;
  final String response;
  final String message;
  @override
  String toString() {
    if (response != null)
      return '$message: "$response"';
    return message;
  }
}

/// Created by [Television.openTransaction].
class TelevisionTransaction {
  TelevisionTransaction._(this.television) {
    assert(television != null);
    assert(television._currentTransaction == null);
    television._currentTransaction = this;
    //print('=== TRANSACTION OPEN');
  }

  final Television television;

  final Completer<Null> _done = new Completer<Null>();
  Future<Null> get done => _done.future;
  TelevisionException _error;

  void sendLine(String message) {
    assert(television._currentTransaction == this);
    if (_error != null)
      throw _error;
    assert(!_done.isCompleted);
    television.resetTimeout();
    television._socket.write('$message\x0d');
    //print('==> $message');
  }

  Future<String> readLine() async {
    assert(television._currentTransaction == this);
    if (_error != null)
      throw _error;
    assert(!_done.isCompleted);
    television.resetTimeout();
    await television._responses.moveNext();
    //print('<== ${television._responses.current}');
    return television._responses.current;
  }

  void close() {
    assert(television._currentTransaction == this);
    //print('=== TRANSACTION CLOSED');
    _done.complete();
    television._currentTransaction = null;
    if (television._transactionQueue != null && television._transactionQueue.isNotEmpty)
      television._transactionQueue.removeFirst().complete();
  }

  void _closeWithError(TelevisionException error) {
    assert(television._currentTransaction == this);
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
          IDIN: '1',
        );
      case TelevisionSource.analogCable:
        return new TelevisionChannel.raw(
          source: source,
          IDIN: '0',
        );
      case TelevisionSource.digitalAir:
        return new TelevisionChannel.raw(
          source: source,
          IDIN: '3',
        );
      case TelevisionSource.digitalCableTwoPart:
        return new TelevisionChannel.raw(
          source: source,
          IDIN: '2',
        );
      case TelevisionSource.digitalCableOnePart:
        return new TelevisionChannel.raw(
          source: source,
          IDIN: '4',
        );
      case TelevisionSource.hdmi1:
        return new TelevisionChannel.raw(
          source: source,
          IAVD: '1',
          // we could use IDIN 11 or IDIN 50, but those return ERR if you're already on that input
        );
      case TelevisionSource.hdmi2:
        return new TelevisionChannel.raw(
          source: source,
          IAVD: '2',
          // we could use IDIN 12 or IDIN 51, but those return ERR if you're already on that input
        );
      case TelevisionSource.hdmi3:
        return new TelevisionChannel.raw(
          source: source,
          IAVD: '3',
          // we could use IDIN 13 or IDIN 52, but those return ERR if you're already on that input
        );
      case TelevisionSource.hdmi4:
        return new TelevisionChannel.raw(
          source: source,
          IAVD: '4',
          // we could use IDIN 14 or IDIN 53, but those return ERR if you're already on that input
        );
      case TelevisionSource.input5: // composite or component
        return new TelevisionChannel.raw(
          source: source,
          IAVD: '5',
          // we could also use IDIN 15
          // we could also set INP5 to 0, which might mean "automatic selection"
        );
      case TelevisionSource.composite:
        return new TelevisionChannel.raw(
          source: source,
          INP5: '1',
        );
      case TelevisionSource.component:
        return new TelevisionChannel.raw(
          source: source,
          INP5: '2',
        );
      case TelevisionSource.ethernet: // home network
        return new TelevisionChannel.raw(
          source: source,
          IDIN: '81',
        );
      case TelevisionSource.storage: // SD card or USB input
        return new TelevisionChannel.raw(
          source: source,
          IDIN: '82',
        );
      case TelevisionSource.miracast:
        return new TelevisionChannel.raw(
          source: source,
          IDIN: '82',
          ITGD: 1,
        );
      case TelevisionSource.bluetooth:
        return new TelevisionChannel.raw(
          source: source,
          IDIN: '82',
          ITGD: 2,
        );
      case TelevisionSource.manual: // documentation manual screen
        return new TelevisionChannel.raw(
          source: source,
          // client must special-case "manual" to mean "hit the manual key on the remote"
        );
      case TelevisionSource.analog:
      case TelevisionSource.unknown:
      case TelevisionSource.switching:
      case TelevisionSource.off:
        break; // must be last in switch statement
    }
    throw new TelevisionException('selected source is too ambiguous', source.toString(), null);
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
        throw new TelevisionException('unknown tv channel format', format, null);
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
        return 'component or composite';
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
        return 'switching inputs';
      case TelevisionSource.analog:
        if (DCCH != null)
          return 'analog channel $DCCH';
        return 'last analog channel';
      case TelevisionSource.unknown:
        return 'unknown (${_fieldsToString()})';
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

  // 
  Socket _socket;
  StreamIterator<String> _responses;
  TelevisionTransaction _currentTransaction;
  Timer _inactivityTimer;

  Future<Null> _connect({
    Duration delay: _retryDelay,
    Duration timeout: _connectTimeout,
  }) async {
    if (_socket != null) {
      assert(_responses != null);
      resetTimeout();
      return null;
    }
    assert(_responses == null);
    assert(_currentTransaction == null);
    assert(_inactivityTimer == null);
    InternetAddress host = this.host;
    if (host == null) {
      final List<InternetAddress> hosts = await InternetAddress.lookup('tv.');
      if (hosts.isEmpty)
        throw new TelevisionException('could not resolve TV in DNS', null, this);
      host = hosts.first;
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
          socket = await Socket.connect(host, port);
          socket.encoding = UTF8;
          socket.write('$username\x0d$password\x0d');
          await socket.flush();
          responses = new StreamIterator<String>(socket.transform(UTF8.decoder).transform(const LineSplitter()));
          await responses.moveNext();
          if (responses.current != 'Login:')
            throw new TelevisionException('did not get login prompt', responses.current, this);
          await responses.moveNext();
          if (responses.current != 'Password:')
            throw new TelevisionException('did not get password prompt', responses.current, this);
        } on TelevisionException catch (error) {
          errors ??= <dynamic>[];
          errors.add(error);
          socket?.destroy();
          socket = null;
          await new Future<Null>.delayed(delay); // too fast and it won't even open the socket
        }
      } while (socket == null && !canceled);
    } finally {
      timeoutTimer.cancel();
    }
    if (socket == null) {
      assert(errors.isNotEmpty);
      throw new TelevisionException(
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
    resetTimeout();
    _socket.done.whenComplete(() {
      if (_socket == socket) {
        assert(_responses == responses);
        abort('connection lost');
      }
    });
  }

  void resetTimeout() {
    _inactivityTimer?.cancel();
    _inactivityTimer = new Timer(_inactivityTimeout, aborter('connection timed out'));
  }

  void abort(String message) {
    _currentTransaction?._closeWithError(new TelevisionException(message, null, this));
    _currentTransaction = null;
    _socket.destroy();
    _socket = null;
    _responses.cancel();
    _responses = null;
    _inactivityTimer.cancel();
    _inactivityTimer = null;
    _connectionStream.add(false);
  }

  VoidCallback aborter(String message) {
    return () { abort(message); };
  }

  void close() {
    assert(_currentTransaction == null);
    _socket?.destroy();
    _socket = null;
    _responses?.cancel();
    _responses = null;
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
  }

  void dispose() {
    close();
    _connectionStream.close();
  }

  Queue<Completer<Null>> _transactionQueue;

  Future<TelevisionTransaction> openTransaction() async {
    await _connect();
    if (_currentTransaction != null) {
      _transactionQueue ??= new Queue<Completer<Null>>();
      Completer<Null> completer = new Completer<Null>();
      _transactionQueue.addLast(completer);
      await completer.future;
    }
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
    final TelevisionTransaction result = await openTransaction();
    result.sendLine(message);
    return result;
  }

  Future<Null> sendCommand(String message, [ String argument = '' ] ) async {
    final TelevisionTransaction transaction = await sendMessage(message, argument);
    final String response = await transaction.readLine();
    transaction.close();
    if (response != 'OK')
      throw new TelevisionException('response to "$message" (argument "$argument") was not OK', response, this);
    return null;
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
    Duration timeout: _responseTimeout,
  }) async {
    bool canceled = false;
    Timer timeoutTimer = new Timer(timeout, () {
      canceled = true;
      abort('timed out awaiting desired response to "$message"');
    });
    try {
      while (!canceled && await readRawValue(message, argument) != desiredResponse)
        await new Future<Null>.delayed(delay);
    } finally {
      timeoutTimer.cancel();
    }
    if (canceled)
      throw new TelevisionException('timed out awaiting desired response to "$message"', null, this);
  }

  Future<Null> nonErrorResponse(String message, {
    String argument: '?',
    Duration delay: _retryDelay,
    Duration timeout: _responseTimeout,
  }) async {
    bool canceled = false;
    Timer timeoutTimer = new Timer(timeout, () {
      canceled = true;
      abort('timed out awaiting successful response to "$message"');
    });
    try {
      while (!canceled && await readRawValue(message, argument) == 'ERR')
        await new Future<Null>.delayed(delay);
    } finally {
      timeoutTimer.cancel();
    }
    if (canceled)
      throw new TelevisionException('timed out awaiting successful response to "$message"', null, this);
  }

  Future<String> readValue(String message, [ String argument = '?' ] ) async {
    final String response = await readRawValue(message, argument);
    if (response == 'ERR')
      throw new TelevisionException('failure response to "$message" (argument "$argument")', response, this);
    return response;
  }

  // MESSAGES

  Future<Null> get inputStable => nonErrorResponse('RDIN');

  Future<bool> get power async {
    final String response = await readValue('POWR');
    switch (response) {
     case '0':
       return false;
     case '1':
       return true;
    }
    throw new TelevisionException('unknown response to "POWR" message', response, this);
  }

  Future<Null> setPower(bool value) async {
    final String argument = value ? '1' : '0';
    await sendCommand('POWR', argument);
    await matchingResponse('POWR', desiredResponse: argument);
    if (value)
      await inputStable;
  }

  Future<Null> sendRemote(TelevisionRemote key) => sendCommand('RCKY', key.index.toString());

  Future<Null> showMessage(String message) => sendCommand('KLCD', message);

  Future<Null> nextInput() async {
    await sendCommand('ITGD');
    await inputStable;
  }

  Future<Null> lastChannel() async {
    await sendCommand('ITVD');
    await inputStable;
  }

  Future<TelevisionChannel> get input async {
    final String POWR = await readRawValue('POWR');
    final String RDIN = await readRawValue('RDIN');
    final String IDIN = await readRawValue('IDIN');
    final String IAVD = await readRawValue('IAVD');
    final String INP5 = await readRawValue('INP5');
    if (RDIN[0] == '0' || IDIN.length == 1) {
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
    assert(value.POWR == null);
    TelevisionChannel current = await input;
    if (current.source != value.source) {
      // The order here is important.
      // In particular:
      //  - POWR before everything.
      //  - IDIN < DC2U < DC2L.
      //  - everything before ITGD.
      //  - IAVD < INP5.
      if (current.POWR != '1')
        await setPower(true);
      if (value.IDIN != null)
        await sendCommand('IDIN', value.IDIN);
      if (value.DCCH != null)
        await sendCommand('DCCH', value.DCCH);
      if (value.DA2P != null)
        await sendCommand('DA2P', value.DA2P);
      if (value.DC2U != null)
        await sendCommand('DC2U', value.DC2U);
      if (value.DC2L != null)
        await sendCommand('DC2L', value.DC2L);
      if (value.DC10 != null)
        await sendCommand('DC10', value.DC10);
      if (value.DC11 != null)
        await sendCommand('DC11', value.DC11);
      if (value.IAVD != null)
        await sendCommand('IAVD', value.IAVD);
      if (value.INP5 != null)
        await sendCommand('INP5', value.INP5);
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

}
