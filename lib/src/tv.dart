import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'common.dart';

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

class TelevisionTransaction {
  TelevisionTransaction(this.television);

  final Television television;

  final Completer<Null> _done = new Completer<Null>();
  Future<Null> get done => _done.future;
  TelevisionException _error;

  void sendLine(String message) {
    if (_error != null)
      throw _error;
    assert(!_done.isCompleted);
    television._socket.write('$message\x0d');
  }

  Future<String> readLine() async {
    if (_error != null)
      throw _error;
    assert(!_done.isCompleted);
    await television._responses.moveNext();
    return television._responses.current;
  }

  void close() {
    _done.complete();
  }

  void _closeWithError(TelevisionException error) {
    _error = error;
    _done.completeError(error);
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
  }

  final InternetAddress host;
  final int port;
  final String username;
  final String password;

  Socket _socket;
  StreamIterator<String> _responses;
  TelevisionTransaction _currentTransaction;

  Future<Null> _connect() async {
    if (_socket != null) {
      assert(_responses != null);
      return null;
    }
    assert(_responses == null);
    assert(_currentTransaction == null);
    Socket socket;
    StreamIterator<String> responses;
    try {
      InternetAddress host = this.host;
      if (host == null) {
        final List<InternetAddress> hosts = await InternetAddress.lookup('tv.');
        if (hosts.isEmpty)
          throw new TelevisionException('could not resolve TV in DNS', null, this);
        host = hosts.first;
      }
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
    } catch (error) {
      socket?.destroy();
      rethrow;
    }
    _socket = socket;
    _responses = responses;
    _currentTransaction = null;
    _socket.done.whenComplete(() {
      if (_socket == socket) {
        assert(_responses == responses);
        _currentTransaction?._closeWithError(new TelevisionException('connection lost', null, this));
        _currentTransaction = null;
        _socket.destroy();
        _socket = null;
        _responses.cancel();
        _responses = null;
      }
    });
  }

  void close() {
    assert(_currentTransaction == null);
    _socket?.destroy();
    _socket = null;
    _responses?.cancel();
    _responses = null;
  }

  Future<TelevisionTransaction> openTransaction() async {
    await _connect();
    if (_currentTransaction != null)
      await _currentTransaction.done;
    TelevisionTransaction result = new TelevisionTransaction(this);
    result.done.whenComplete(() {
      _currentTransaction = null;
    });
    return result;
  }

  Future<TelevisionTransaction> sendCommand(String command, String arguments) async {
    assert(command != null);
    assert(command.length == 4);
    assert(arguments != null);
    final String message = '$command${arguments.padRight(4, ' ')}';
    final TelevisionTransaction result = await openTransaction();
    result.sendLine(message);
    return result;
  }

  Future<bool> get power async {
    final TelevisionTransaction transaction = await sendCommand('POWR', '?');
    final String response = await transaction.readLine();
    transaction.close();
    switch (response) {
     case '0':
       return false;
     case '1':
       return true;
    }
    throw new TelevisionException('error getting power', response, this);
  }

  Future<Null> setPower(bool value) async {
    final TelevisionTransaction transaction = await sendCommand('POWR', value ? '1' : '0');
    final String response = await transaction.readLine();
    transaction.close();
    if (response != 'OK')
      throw new TelevisionException('error setting power', response, this);
  }
}


// ## TV

// Connect with InternetAddress, username, password
// Stream power and channel events
// Set power
// Set channel
// Send message
