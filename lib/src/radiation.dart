import 'package:meta/meta.dart';

import 'metrics.dart';

abstract class Radiation extends Measurement implements Comparable<Radiation> {
  Radiation({
    @required MeasurementStation station,
    @required DateTime timestamp,
  }) : super(station: station, timestamp: timestamp);

  double get doseRate; // in μSv/h -- see https://en.wikipedia.org/wiki/Sievert#Dose_rate_examples

  @override
  Metric get metric => Metric.radiation;

  @override
  double get value => doseRate;

  @override
  MetricUnits get units => MetricUnits.microsievertsPerHour;

  @override
  int compareTo(Radiation other) {
    return doseRate.compareTo(other.doseRate);
  }

  bool operator <(Radiation other) {
    return doseRate < other.doseRate;
  }

  bool operator <=(Radiation other) {
    return doseRate <= other.doseRate;
  }

  bool operator >(Radiation other) {
    return doseRate > other.doseRate;
  }

  bool operator >=(Radiation other) {
    return doseRate >= other.doseRate;
  }

  @override
  bool operator ==(dynamic other) {
    if (other is! Radiation)
      return false;
    return doseRate == other.doseRate;
  }

  @override
  int get hashCode => doseRate.hashCode;

  String toStringAsDoseRate() => '${doseRate.toStringAsFixed(1)}μSv/h';
}
