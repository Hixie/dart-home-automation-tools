import 'package:meta/meta.dart';

import 'metrics.dart';

abstract class Temperature extends Measurement implements Comparable<Temperature> {
  Temperature({
    @required MeasurementStation station,
    @required DateTime timestamp,
  }) : super(station: station, timestamp: timestamp);

  double get celsius;
  double get fahrenheit;

  @override
  Metric get metric => Metric.temperature;

  @override
  double get value => celsius;

  @override
  MetricUnits get units => MetricUnits.celsius;

  @override
  int compareTo(Temperature other) {
    return celsius.compareTo(other.celsius);
  }

  bool operator <(Temperature other) {
    return celsius < other.celsius;
  }

  bool operator <=(Temperature other) {
    return celsius <= other.celsius;
  }

  bool operator >(Temperature other) {
    return celsius > other.celsius;
  }

  bool operator >=(Temperature other) {
    return celsius >= other.celsius;
  }

  @override
  bool operator ==(dynamic other) {
    if (other is! Temperature)
      return false;
    return celsius == other.celsius;
  }

  @override
  int get hashCode => celsius.hashCode;

  String toStringAsCelsius() => '${celsius.toStringAsFixed(1)}℃';

  String toStringAsFahrenheit() => '${celsius.toStringAsFixed(1)}℉';
}

class RawTemperature extends Temperature {
  RawTemperature(this.celsius, {
    @required MeasurementStation station,
    @required DateTime timestamp,
  }) : super(station: station, timestamp: timestamp);

  @override
  double get fahrenheit => celsius * 9.0 / 5.0 + 32.0;

  @override
  final double celsius;
}
