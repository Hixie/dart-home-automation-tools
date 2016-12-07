import 'dart:async';

const Duration kDebounceDuration = const Duration(milliseconds: 500);

final StreamTransformer<bool, bool> debouncer = new StreamTransformer<bool, bool>(
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
                timer = new Timer(kDebounceDuration, () {
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
