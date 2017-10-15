// Copyright 2015 The Chromium Authors. All rights reserved.
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

class _HashEnd { const _HashEnd(); }
const _HashEnd _hashEnd = const _HashEnd();

/// Jenkins hash function, optimized for small integers.
//
// Borrowed from the dart sdk: sdk/lib/math/jenkins_smi_hash.dart.
class _Jenkins {
  static int combine(int hash, Object o) {
    assert(o is! Iterable);
    hash = 0x1fffffff & (hash + o.hashCode);
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// Combine up to twenty objects' hash codes into one value.
///
/// If you only need to handle one object's hash code, then just refer to its
/// [Object.hashCode] getter directly.
///
/// If you need to combine an arbitrary number of objects from a [List] or other
/// [Iterable], use [hashList]. The output of [hashList] can be used as one of
/// the arguments to this function.
///
/// For example:
///
/// ```dart
/// int hashCode => hashValues(foo, bar, hashList(quux), baz);
/// ```
int hashValues(
  Object arg01,            Object arg02,          [ Object arg03 = _hashEnd,
  Object arg04 = _hashEnd, Object arg05 = _hashEnd, Object arg06 = _hashEnd,
  Object arg07 = _hashEnd, Object arg08 = _hashEnd, Object arg09 = _hashEnd,
  Object arg10 = _hashEnd, Object arg11 = _hashEnd, Object arg12 = _hashEnd,
  Object arg13 = _hashEnd, Object arg14 = _hashEnd, Object arg15 = _hashEnd,
  Object arg16 = _hashEnd, Object arg17 = _hashEnd, Object arg18 = _hashEnd,
  Object arg19 = _hashEnd, Object arg20 = _hashEnd ]) {
  int result = 0;
  result = _Jenkins.combine(result, arg01);
  result = _Jenkins.combine(result, arg02);
  if (arg03 != _hashEnd) {
    result = _Jenkins.combine(result, arg03);
    if (arg04 != _hashEnd) {
      result = _Jenkins.combine(result, arg04);
      if (arg05 != _hashEnd) {
        result = _Jenkins.combine(result, arg05);
        if (arg06 != _hashEnd) {
          result = _Jenkins.combine(result, arg06);
          if (arg07 != _hashEnd) {
            result = _Jenkins.combine(result, arg07);
            if (arg08 != _hashEnd) {
              result = _Jenkins.combine(result, arg08);
              if (arg09 != _hashEnd) {
                result = _Jenkins.combine(result, arg09);
                if (arg10 != _hashEnd) {
                  result = _Jenkins.combine(result, arg10);
                  if (arg11 != _hashEnd) {
                    result = _Jenkins.combine(result, arg11);
                    if (arg12 != _hashEnd) {
                      result = _Jenkins.combine(result, arg12);
                      if (arg13 != _hashEnd) {
                        result = _Jenkins.combine(result, arg13);
                        if (arg14 != _hashEnd) {
                          result = _Jenkins.combine(result, arg14);
                          if (arg15 != _hashEnd) {
                            result = _Jenkins.combine(result, arg15);
                            if (arg16 != _hashEnd) {
                              result = _Jenkins.combine(result, arg16);
                              if (arg17 != _hashEnd) {
                                result = _Jenkins.combine(result, arg17);
                                if (arg18 != _hashEnd) {
                                  result = _Jenkins.combine(result, arg18);
                                  if (arg19 != _hashEnd) {
                                    result = _Jenkins.combine(result, arg19);
                                    if (arg20 != _hashEnd) {
                                      result = _Jenkins.combine(result, arg20);
                                      // I can see my house from here!
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
  return _Jenkins.finish(result);
}

/// Combine the [Object.hashCode] values of an arbitrary number of objects from
/// an [Iterable] into one value. This function will return the same value if
/// given null as if given an empty list.
int hashList(Iterable<Object> arguments) {
  int result = 0;
  if (arguments != null) {
    for (Object argument in arguments)
      result = _Jenkins.combine(result, argument);
  }
  return _Jenkins.finish(result);
}
