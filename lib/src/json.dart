// Copyright 2017 The Chromium Authors. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the names of its
// contributors may be used to endorse or promote products derived from
// this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

class Json {
  factory Json(dynamic input) {
    if (input is Json)
      return wrap(input._value);
    return wrap(input);
  }

  factory Json.list(List<dynamic> input) {
    return new Json.raw(input.map<Json>(wrap).toList());
  }

  // (This differs from "real" JSON in that we don't allow duplicate keys.)
  factory Json.map(Map<dynamic, dynamic> input) {
    final Map<String, Json> values = <String, Json>{};
    input.forEach((dynamic key, dynamic value) {
      key = key.toString();
      assert(!values.containsKey(key), 'Json.map keys must be unique strings');
      values[key] = wrap(value);
    });
    return new Json.raw(values);
  }

  const Json.raw(this._value);

  final dynamic _value;

  static Json wrap(dynamic value) {
    if (value == null) {
      return const Json.raw(null);
    } else if (value is num) {
      return new Json.raw(value.toDouble());
    } else if (value is List) {
      return new Json.list(value);
    } else if (value is Map) {
      return new Json.map(value);
    } else if (value == true) {
      return const Json.raw(true);
    } else if (value == false) {
      return const Json.raw(false);
    } else if (value is Json) {
      return value;
    }
    return new Json.raw(value.toString());
  }

  dynamic unwrap() {
    if (_value is Map) {
      final Map<String, dynamic> values = <String, dynamic>{};
      _value.forEach((String key, Json value) {
        values[key] = value.unwrap();
      });
      return values;
    } else if (_value is List) {
      return _value.map<dynamic>((Json value) => value.unwrap()).toList();
    } else {
      return _value;
    }
  }

  double toDouble() => _value as double;
  bool toBoolean() => _value as bool;
  @override
  String toString() => _value.toString();
  Type get valueType => _value.runtimeType;

  String toJson() {
    // insert JSON serializer here
    throw new Exception('not implemented');
  }

  dynamic operator [](dynamic key) {
    return _value[key];
  }

  void operator []=(dynamic key, dynamic value) {
    _value[key] = wrap(value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter)
      return this[_symbolName(invocation.memberName)];
    if (invocation.isSetter)
      return this[_symbolName(invocation.memberName)] = invocation.positionalArguments[0];
    return super.noSuchMethod(invocation);
  }

  // Workaround for https://github.com/dart-lang/sdk/issues/28372
  String _symbolName(Symbol symbol) {
    // WARNING: Assumes a fixed format for Symbol.toString which is *not*
    // guaranteed anywhere.
    final String s = '$symbol';
    return s.substring(8, s.length - 2);
  }

  bool operator <(dynamic other) {
    if (other.runtimeType != Json)
      return _value < other;
    return _value < other._value;
  }

  bool operator <=(dynamic other) {
    if (other.runtimeType != Json)
      return _value <= other;
    return _value <= other._value;
  }

  bool operator >(dynamic other) {
    if (other.runtimeType != Json)
      return _value > other;
    return _value > other._value;
  }

  bool operator >=(dynamic other) {
    if (other.runtimeType != Json)
      return _value >= other;
    return _value >= other._value;
  }

  dynamic operator -(dynamic other) {
    if (other.runtimeType != Json)
      return _value - other;
    return _value - other._value;
  }

  dynamic operator +(dynamic other) {
    if (other.runtimeType != Json)
      return _value + other;
    return _value + other._value;
  }

  dynamic operator /(dynamic other) {
    if (other.runtimeType != Json)
      return _value / other;
    return _value / other._value;
  }

  dynamic operator ~/(dynamic other) {
    if (other.runtimeType != Json)
      return _value ~/ other;
    return _value ~/ other._value;
  }

  dynamic operator *(dynamic other) {
    if (other.runtimeType != Json)
      return _value * other;
    return _value * other._value;
  }

  dynamic operator %(dynamic other) {
    if (other.runtimeType != Json)
      return _value % other;
    return _value % other._value;
  }

  dynamic operator |(dynamic other) {
    if (other.runtimeType != Json)
      return _value | other;
    return _value | other._value;
  }

  dynamic operator ^(dynamic other) {
    if (other.runtimeType != Json)
      return _value ^ other;
    return _value ^ other._value;
  }

  dynamic operator &(dynamic other) {
    if (other.runtimeType != Json)
      return _value & other;
    return _value & other._value;
  }

  dynamic operator <<(dynamic other) {
    if (other.runtimeType != Json)
      return _value << other;
    return _value << other._value;
  }

  dynamic operator >>(dynamic other) {
    if (other.runtimeType != Json)
      return _value >> other;
    return _value >> other._value;
  }

  @override
  bool operator ==(dynamic other) {
    if (other.runtimeType != Json)
      return _value == other;
    return _value == other._value;
  }

  @override
  int get hashCode => _value.hashCode;
}
