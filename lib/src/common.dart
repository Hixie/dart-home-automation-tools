import 'dart:async';

typedef void VoidCallback();
typedef void Logger(String message);
typedef void StreamHandler<T>(T event);
typedef Future<Null> ErrorHandler(dynamic error);

enum LogLevel { error, info, verbose }

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
