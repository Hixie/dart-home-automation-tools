
abstract class Temperature implements Comparable<Temperature> {
  const Temperature();

  double get celsius;
  double get fahrenheit;

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

  @override
  String toString() => '${celsius.toStringAsFixed(1)}';

  String toStringAsCelsius() => '${celsius.toStringAsFixed(1)}℃';

  String toStringAsFahrenheit() => '${celsius.toStringAsFixed(1)}℉';
}
