import 'dart:async';

typedef Future<Null> ErrorHandler(dynamic error);

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
