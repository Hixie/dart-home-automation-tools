import 'dart:async';

typedef void VoidCallback();
typedef void LogCallback(String message);
typedef void StreamHandler<T>(T event);
typedef Future<Null> ErrorHandler(dynamic error);
typedef void DeviceLogCallback(String deviceId, String message);

enum LogLevel { error, info, verbose }

T min<T extends Comparable<T>>(T a, T b) {
  if (a == null)
    return b;
  if (b == null)
    return a;
  return a.compareTo(b) > 0 ? b : a;
}

T max<T extends Comparable<T>>(T a, T b) {
  if (a == null)
    return b;
  if (b == null)
    return a;
  return a.compareTo(b) < 0 ? b : a;
}

abstract class StreamTransformerInstance<From, To> {
  bool handleData(From event, StreamSink<To> output);
  bool handleError(dynamic exception, StackTrace stack, StreamSink<To> output) {
    output.addError(exception, stack);
    return false;
  }
  void handleDone(StreamSink<To> output);
}

typedef StreamTransformerInstance<From, To> StreamTransformerInstanceConstructor<From, To>();

class StreamTransformerBase<From, To> implements StreamTransformer<From, To> {
  StreamTransformerBase(this.constructor) {
    assert(constructor != null);
  }

  final StreamTransformerInstanceConstructor<From, To> constructor;

  @override
  Stream<To> bind(Stream<From> stream) {
    StreamController<To> output;
    StreamSubscription<From> input;
    StreamTransformerInstance<From, To> instance = constructor();
    output = new StreamController<To>(
      onListen: () {
        input = stream.listen(
          (From event) {
            if (instance.handleData(event, output.sink)) {
              input.cancel();
              output.close();
            }
          },
          onError: (dynamic exception, StackTrace stack) {
            if (instance.handleError(exception, stack, output.sink)) {
              input.cancel();
              output.close();
            }
          },
          onDone: () {
            instance.handleDone(output.sink);
            output.close();
          },
        );
      },
      onPause: () {
        input.pause();
      },
      onResume: () {
        input.resume();
      },
      onCancel: () {
        input.cancel();
      },
    );
    return output.stream;
  }

  @override
  StreamTransformer<RS, TS> cast<RS, TS>() {
    throw Error(); // not implemented
  }
}

StreamTransformer<bool, bool> debouncer(Duration debounceDuration) {
  return new StreamTransformer<bool, bool>(
    (Stream<bool> input, bool cancelOnError) {
      StreamController<bool> controller;
      StreamSubscription<bool> subscription;
      Timer timer;
      bool lastSentValue;
      bool lastReceivedValue;
      controller = new StreamController<bool>(
        onListen: () {
          subscription = input.listen(
            (bool value) {
              if (value != lastReceivedValue) {
                lastReceivedValue = value;
                timer?.cancel();
                if (value != lastSentValue) {
                  timer = new Timer(debounceDuration, () {
                    timer = null;
                    // TODO(ianh): handle paused
                    lastSentValue = lastReceivedValue;
                    controller.add(lastReceivedValue);
                  });
                }
              }
            },
            onError: controller.addError,
            onDone: controller.close,
            cancelOnError: cancelOnError,
          );
        },
        onPause: () { subscription.pause(); },
        onResume: () { subscription.resume(); },
        onCancel: () {
          timer?.cancel();
          return subscription.cancel();
        }
      );
      return controller.stream.listen(null);
    }
  );
}

final StreamTransformer<bool, bool> inverter = _inverter();
StreamTransformer<bool, bool> _inverter() {
  return new StreamTransformer<bool, bool>(
    (Stream<bool> input, bool cancelOnError) {
      StreamController<bool> controller;
      StreamSubscription<bool> subscription;
      controller = new StreamController<bool>(
        onListen: () {
          subscription = input.listen(
            (bool value) {
              controller.add(!value);
            },
            onError: controller.addError,
            onDone: controller.close,
            cancelOnError: cancelOnError,
          );
        },
        onPause: () { subscription.pause(); },
        onResume: () { subscription.resume(); },
        onCancel: () => subscription.cancel(),
      );
      return controller.stream.listen(null);
    }
  );
}

String prettyDuration(Duration duration) {
  int microseconds = duration.inMicroseconds;
  int weeks = microseconds ~/ (1000 * 1000 * 60 * 60 * 24 * 7);
  microseconds -= weeks * (1000 * 1000 * 60 * 60 * 24 * 7);
  int days = microseconds ~/ (1000 * 1000 * 60 * 60 * 24);
  microseconds -= days * (1000 * 1000 * 60 * 60 * 24);
  int hours = microseconds ~/ (1000 * 1000 * 60 * 60);
  microseconds -= hours * (1000 * 1000 * 60 * 60);
  int minutes = microseconds ~/ (1000 * 1000 * 60);
  microseconds -= minutes * (1000 * 1000 * 60);
  int seconds = microseconds ~/ (1000 * 1000);
  microseconds -= seconds * (1000 * 1000);
  int milliseconds = microseconds ~/ (1000);
  microseconds -= milliseconds * (1000);

  if (weeks > 1 && days == 0 && hours == 0)
    return '$weeks weeks';
  if (weeks == 1 && days == 0 && hours == 0)
    return 'one week';

  if (days > 1 && hours == 0 && minutes == 0)
    return '$days days';
  if (days == 1 && hours == 0 && minutes == 0)
    return 'one day';

  if (hours > 1 && minutes == 0 && seconds == 0)
    return '$hours hours';
  if (hours == 1 && minutes == 0 && seconds == 0)
    return 'one hour';

  StringBuffer result = new StringBuffer();
  int fields = 0x00;
  if (weeks > 0) {
    result.write('${weeks}w ');
    fields |= 0x80;
  }
  if (days > 0) {
    result.write('${days}d ');
    fields |= 0x40;
  }
  if (hours > 0 && fields < 0x80) {
    result.write('${hours}h ');
    fields |= 0x20;
  }
  if (minutes > 0 && fields < 0x40) {
    result.write('${minutes}m ');
    fields |= 0x10;
  }
  if (seconds > 0 && fields < 0x20) {
    result.write('${seconds}s ');
    fields |= 0x08;
  }
  if (milliseconds > 0 && fields < 0x10) {
    result.write('${milliseconds}ms ');
    fields |= 0x04;
  }
  if (microseconds > 0 && fields < 0x08) {
    result.write('${microseconds}µs ');
    fields |= 0x02;
  }

  return result.toString().trimRight();
}
