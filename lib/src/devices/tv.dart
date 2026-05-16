import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import '../common.dart';
import '../watch_stream.dart';

// This is written for the Bravia K-77XR80 Simple IP Control protocol.
// Documentation: https://pro-bravia.sony.net/remote-display-control/simple-ip-control/

const bool _verbose = false;

class TelevisionException implements Exception {
  const TelevisionException(this.message, this.response, this.television);
  final Television television;
  final String response;
  final String message;
  @override
  String toString() {
    if (response != null)
      return '$message: "$response"';
    return '$message';
  }
}

enum TelevisionSource { hdmi1, hdmi2, hdmi3, hdmi4, none, off }

class _ResponseHandler {
  const _ResponseHandler({ this.ignore, this.completer });
  final bool ignore;
  final Completer<String> completer;
}

class Television {
  Television({
    this.host,
    this.port: 20060,
    this.onLog,
  }) {
    assert(port != null);
    _connectionStream = new AlwaysOnWatchStream<bool>();
    _connectionStream.add(false);
    _powerStream = new AlwaysOnWatchStream<bool>();
    _inputStream = new AlwaysOnWatchStream<TelevisionSource>();
    _volumeStream = new AlwaysOnWatchStream<int>();
    _audioMuteStream = new AlwaysOnWatchStream<bool>();
    _pictureMuteStream = new AlwaysOnWatchStream<bool>();
    _dpssStream = new AlwaysOnWatchStream<int>();
    _watchSettingsTimer = Timer.periodic(const Duration(seconds: 5), _checkSettings);
    _watchDPSSTimer = Timer.periodic(const Duration(minutes: 5), _checkDPSS);
    _connect();
  }

  final InternetAddress host;
  final int port;
  final LogCallback onLog;

  WatchStream<bool> get connected => _connectionStream;
  AlwaysOnWatchStream<bool> _connectionStream;
  
  WatchStream<bool> get power => _powerStream;
  AlwaysOnWatchStream<bool> _powerStream;
  
  WatchStream<TelevisionSource> get input => _inputStream;
  AlwaysOnWatchStream<TelevisionSource> _inputStream;
  
  WatchStream<int> get volume => _volumeStream;
  AlwaysOnWatchStream<int> _volumeStream;
  
  WatchStream<bool> get audioMute => _audioMuteStream;
  AlwaysOnWatchStream<bool> _audioMuteStream;
  
  WatchStream<bool> get pictureMute => _pictureMuteStream;
  AlwaysOnWatchStream<bool> _pictureMuteStream;
  
  WatchStream<int> get dpss => _dpssStream;
  AlwaysOnWatchStream<int> _dpssStream;

  bool _power;
  bool _audioMuted, _pictureMuted;
  TelevisionSource _currentInput;
  int _volume;
  int _dpss;

  Socket _socket;
  Timer _watchSettingsTimer;
  Timer _watchDPSSTimer;
  Timer _logStatus;
  Stopwatch _statusAge = Stopwatch()..start();

  // Completers waiting for an response from the TV, keyed by the command string; FIFO.
  final Map<String, Queue<_ResponseHandler>> _pendingResponses =
      <String, Queue<_ResponseHandler>>{};

  bool _active = true;

  void dispose() {
    _active = false;
    _socket?.destroy();
    _watchSettingsTimer?.cancel();
    _watchDPSSTimer?.cancel();
    _logStatus?.cancel();
  }

  Future<Null> _connect() async {
    while (_active) {
      InternetAddress host = this.host;
      if (host == null) {
        try {
          final List<InternetAddress> hosts = await InternetAddress.lookup('tv.');
          if (hosts.isEmpty)
            throw new TelevisionException('Could not resolve TV in DNS.', null, this);
          host = hosts.first;
        } on SocketException {
          throw new TelevisionException('Could not resolve TV in DNS.', null, this);
        }
      }
      try {
        assert(_socket == null);
        _socket = await Socket.connect(host, port);
        _socket.encoding = utf8;
        _socket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).listen(
          _handleMessage,
          onDone: () {
            _connectionStream.add(false);
            _failPendingResponses();
          },
          onError: (dynamic e) {
            _connectionStream.add(false);
            _failPendingResponses();
          },
          cancelOnError: true,
        );
        _connectionStream.add(true);
        onLog('connected to $host:$port');
        _checkSettings();
        _checkDPSS();
        await _socket.done.whenComplete(() {
          _connectionStream.add(false);
          _failPendingResponses();
        });
      } catch (e) {
        if (onLog != null)
          onLog(e.toString());
        await new Future<Null>.delayed(const Duration(seconds: 3));
      }
      await new Future<Null>.delayed(const Duration(milliseconds: 100));
      _socket = null;
    }
  }

  void _failPendingResponses() {
    // Snapshot to avoid concurrent-modification issues.
    final Map<String, Queue<_ResponseHandler>> snapshot =
        new Map<String, Queue<_ResponseHandler>>.from(_pendingResponses);
    _pendingResponses.clear();
    for (final Queue<_ResponseHandler> queue in snapshot.values) {
      for (final _ResponseHandler handler in queue) {
        if (!handler.completer.isCompleted)
          handler.completer.completeError(new TelevisionException('disconnected', null, this));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Message parsing
  // ---------------------------------------------------------------------------

  // 24-byte wire format:  *S <type> <4cc> <16-byte param> \n
  // After LineSplitter strips the trailing LF, messages are 23 characters.
  static const int _wireLength = 24;
  static const String _errorParam    = 'FFFFFFFFFFFFFFFF';
  static const String _noInputParam  = '0000000000000000';
  static const String _enquiryParam  = '################';

  void _handleMessage(String message) {
    if (message.length < _wireLength - 1) { // 23 after LF stripped
      onLog('received message with invalid length: $message');
      return;
    }
    if (!message.startsWith('*S')) {
      onLog('received message with invalid prefix: $message');
      return;
    }
    if (_verbose)
      onLog('received "$message"');

    final String type      = message[2];
    final String command   = message.substring(3, 7);
    final String parameter = message.substring(7, 23);

    switch (type) {
      case 'A': // Answer (response to command)
        final Queue<_ResponseHandler> queue = _pendingResponses[command];
        bool ignore = false;
        if (queue != null && queue.isNotEmpty) {
          final _ResponseHandler handler = queue.removeFirst();
          final Completer<String> completer = handler.completer;
          if (queue.isEmpty)
            _pendingResponses.remove(command);
          completer.complete(parameter);
          if (handler.ignore)
            ignore = true;
        }
        if (!ignore) {
          _processStateUpdate(command, parameter);
        }
        break;

      case 'N': // Notify (unsolicited state change from TV)
        if (parameter != _errorParam)
          _processStateUpdate(command, parameter, notification: true);
        break;
    }
  }

  String _lastLoggedStatus = '';
  String _nextStatus = '';

  void _processStateUpdate(String command, String parameter, { bool notification = false }) {
    switch (command) {
      case 'POWR':
        final bool on = _parseBool(parameter);
        _power = on;
        _powerStream.add(on);
        if (on == true) {
          if (notification)
            _checkSettings();
        } else if (on == false) {
          _currentInput = TelevisionSource.off;
          _inputStream.add(TelevisionSource.off);
        }
        break;

      case 'INPT':
        final TelevisionSource source = _parseInputParameter(parameter);
        _currentInput = source;
        _inputStream.add(source);
        break;

      case 'VOLU':
        // Volume is a decimal integer left-padded with '0' to 16 chars.
        final int v = int.tryParse(parameter) ?? _volume;
        _volume = v;
        _volumeStream.add(v);
        break;

      case 'AMUT':
        final bool muted = _parseBool(parameter) ?? _audioMuted;
        _audioMuteStream.add(muted);
        _audioMuted = muted;
        break;

      case 'PMUT':
        final bool muted = _parseBool(parameter) ?? _pictureMuted;
        _pictureMuteStream.add(muted);
        _pictureMuted = muted;
        break;

      case 'DPSS':
        final int dpss = int.tryParse(parameter) ?? _dpss;
        _dpss = dpss;
        _dpssStream.add(dpss);
        break;
    }
    String dpss = ' DPSS $_dpss (0x${_dpss?.toRadixString(16)?.padLeft(8, '0')}).';
    if (_power) {
      String input = '';
      switch (_currentInput) {
        case TelevisionSource.hdmi1: input = 'HDMI1. '; break;
        case TelevisionSource.hdmi2: input = 'HDMI2. '; break;
        case TelevisionSource.hdmi3: input = 'HDMI3. '; break;
        case TelevisionSource.hdmi4: input = 'HDMI4. '; break;
        default: break;
      }
      String volume = 'Volume ${_volume ?? "??"}%';
      String muted = '${_audioMuted == true ? " MUTED" : ""}${_pictureMuted == true ? " BLANKED" : ""}';
      _nextStatus = '$input$volume$muted.$dpss';
    } else {
      _nextStatus = 'Power off.$dpss';
    }
    if (_nextStatus != _lastLoggedStatus) {
      if (_statusAge.elapsed > const Duration(seconds: 10)) {
        _updateStatus();
      } else {
        _logStatus?.cancel();
        _logStatus = Timer(const Duration(seconds: 1), _updateStatus);
      }
    }
  }

  void _updateStatus() {
    _logStatus = null;
    if (_nextStatus != _lastLoggedStatus) {
      onLog(_nextStatus);
      _lastLoggedStatus = _nextStatus;
      _statusAge.reset();
    }
  }

  bool _parseBool(String parameter) {
    if (parameter == '0000000000000001')
      return true;
    if (parameter == '0000000000000000')
      return false;
    return null;
  }

  // INPT parameter layout (16 bytes):
  //   [0-6]  = '0000000'           (padding)
  //   [7]    = input type          ('1'=HDMI, '3'=Composite, '4'=Component, '5'=ScreenMirroring)
  //   [8-11] = '0000'              (padding)
  //   [12-15]= port number         (e.g. '0001'..'0004')
  // We ignore everything other than HDMI1-4.
  TelevisionSource _parseInputParameter(String parameter) {
    if (!_power)
      return TelevisionSource.off;
    final String typeChar = parameter[7];
    final int portNum = int.tryParse(parameter.substring(12, 16)) ?? 0;
    if (typeChar == '1') {
      switch (portNum) {
        case 1: return TelevisionSource.hdmi1;
        case 2: return TelevisionSource.hdmi2;
        case 3: return TelevisionSource.hdmi3;
        case 4: return TelevisionSource.hdmi4;
      }
    }
    return TelevisionSource.none;
  }

  String _inputToParameter(TelevisionSource source) {
    int portNum;
    switch (source) {
      case TelevisionSource.hdmi1: portNum = 1; break;
      case TelevisionSource.hdmi2: portNum = 2; break;
      case TelevisionSource.hdmi3: portNum = 3; break;
      case TelevisionSource.hdmi4: portNum = 4; break;
      default:
        throw new ArgumentError('Cannot set input to $source');
    }
    // type=1 (HDMI), port left-padded to 4 digits
    return '00000001${portNum.toString().padLeft(8, '0')}';
  }

  // ---------------------------------------------------------------------------
  // Low-level send helpers
  // ---------------------------------------------------------------------------

  Future<String> _sendCommand(String command, String parameter) {
    return _sendMessage('C', command, parameter, ignoreResponse: true);
  }

  Future<String> _sendEnquiry(String command, String parameter) {
    return _sendMessage('E', command, parameter, ignoreResponse: false);
  }

  Future<String> _sendMessage(String type, String command, String parameter, { bool ignoreResponse = false }) {
    if (_socket == null) {
      onLog('not connected; could not send $type $command $parameter');
      return new Future<Null>.value(null);
    }
    assert(type.length == 1);
    assert(command.length == 4);
    assert(parameter.length == 16);
    final String message = '*S$type$command$parameter\n';
    assert(message.length == _wireLength);
    final Completer<String> completer = new Completer<String>();
    _socket.write(message);
    _pendingResponses
        .putIfAbsent(command, () => new Queue<_ResponseHandler>())
        .add(_ResponseHandler(completer: completer, ignore: ignoreResponse));
    return completer.future;
  }

  Future<Null> _checkSettings([Timer timer]) async {
    _sendEnquiry('POWR', _enquiryParam);
    _sendEnquiry('INPT', _enquiryParam);
    _sendEnquiry('VOLU', _enquiryParam);
    _sendEnquiry('AMUT', _enquiryParam);
    _sendEnquiry('PMUT', _enquiryParam);
  }

  Future<Null> _checkDPSS([Timer timer]) async {
    _sendEnquiry('DPSS', _enquiryParam);
  }

  Future<Null> showMessage(String message) async {
    // no-op :-(
  }

  Future<Null> setPower(bool on) async {
    await _sendCommand('POWR', '000000000000000${on ? 1 : 0}');
    await _checkSettings();
  }

  Future<Null> setInput(TelevisionSource source) async {
    // When the TV is on but stuck at the home/menu screen ("none"), navigate
    // to the home screen first so that HDMI inputs become accessible.
    // (Whether this is really needed or not is unclear.)
    if (_currentInput == TelevisionSource.none) {
      await sendIR(irHome);
      await new Future<Null>.delayed(const Duration(milliseconds: 500));
    }
    await _sendCommand('INPT', _inputToParameter(source));
    await _sendEnquiry('INPT', _enquiryParam);
  }

  Future<Null> setVolume(int level) async {
    await _sendCommand('VOLU', level.toString().padLeft(16, '0'));
    await _sendEnquiry('VOLU', _enquiryParam);
  }

  Future<Null> setAudioMute(bool muted) async {
    await _sendCommand('AMUT', '000000000000000${muted ? 1 : 0}');
    await _sendEnquiry('AMUT', _enquiryParam);
  }

  Future<Null> setPictureMute(bool muted) async {
    await _sendCommand('PMUT', '000000000000000${muted ? 1 : 0}');
    await _sendEnquiry('PMUT', _enquiryParam);
  }

  Future<Null> togglePictureMute() async {
    await _sendCommand('TPMU', _enquiryParam);
    await _sendEnquiry('PMUT', _enquiryParam);
  }

  Future<String> get macAddress async {
    final String result = await _sendEnquiry('MADR', 'eth0############');
    return result.replaceAll('#', '');
  }

  Future<String> get broadcastAddress async {
    final String result = await _sendEnquiry('BADR', 'eth0############');
    return result.replaceAll('#', '');
  }

  // TODO: add more codes from https://github.com/forty2/bravia-simple-ip-control/blob/master/src/commands.js#L371 (need checking)
  static const int irDisplay      = 5;
  static const int irHome         = 6;
  static const int irOptions      = 7;
  static const int irReturn       = 8;
  static const int irUp           = 9;
  static const int irDown         = 10;
  static const int irRight        = 11;
  static const int irLeft         = 12;
  static const int irConfirm      = 13;
  static const int irRed          = 14;
  static const int irGreen        = 15;
  static const int irYellow       = 16;
  static const int irBlue         = 17;
  static const int irNum1         = 18;
  static const int irNum2         = 19;
  static const int irNum3         = 20;
  static const int irNum4         = 21;
  static const int irNum5         = 22;
  static const int irNum6         = 23;
  static const int irNum7         = 24;
  static const int irNum8         = 25;
  static const int irNum9         = 26;
  static const int irNum0         = 27;
  static const int irVolumeUp     = 30;
  static const int irVolumeDown   = 31;
  static const int irMute         = 32;
  static const int irChannelUp    = 33;
  static const int irChannelDown  = 34;
  static const int irSubtitle     = 35;
  static const int irDot          = 38;
  static const int irPictureOff   = 50;
  static const int irWide         = 61;
  static const int irJump         = 62;
  static const int irSyncMenu     = 76;
  static const int irForward      = 77;
  static const int irPlay         = 78;
  static const int irRewind       = 79;
  static const int irPrev         = 80;
  static const int irStop         = 81;
  static const int irNext         = 82;
  static const int irPause        = 84;
  static const int irFlashPlus    = 86;
  static const int irFlashMinus   = 87;
  static const int irTvPower      = 98;
  static const int irAudio        = 99;
  static const int irInput        = 101;
  static const int irSleep        = 104;
  static const int irSleepTimer   = 105;
  static const int irVideo2       = 108;
  static const int irPictureMode  = 110;
  static const int irDemoSurround = 121;
  static const int irHdmi1        = 124;
  static const int irHdmi2        = 125;
  static const int irHdmi3        = 126;
  static const int irHdmi4        = 127;
  static const int irActionMenu   = 129;
  static const int irHelp         = 130;

  Future<Null> sendIR(int ircode) async {
    await _sendCommand('IRCC', ircode.toString().padLeft(16, '0'));
    await _checkSettings();
  }

  Future<Null> showTimeAndInput() => sendIR(irDisplay);
}
