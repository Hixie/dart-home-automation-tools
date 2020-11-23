import 'dart:math' as math;
import 'dart:typed_data';

import '../table_record.dart';

enum DishwasherMode { dirty, active, clean, unknown }

enum DishwasherDelay { hours0, hours2, hours4, hours8 }
enum DishwasherUserCycleSelection { autosense, heavy, normal, light }
enum DishwasherWashTemperature { normal, boost, sanitize }
enum DishwasherOperatingMode { lowPower, powerUp, standBy, delayStart, pause, active, endOfCycle, downloadMode, sensorCheckMode, loadActivationMode, machineControlOnly }
enum DishwasherCycleState { none, preWash, sensing, mainWash, drying, sanitizing, turbidityCalibration, diverterCalibration, pause, rinsing }
enum DishwasherCycleMode { none, autosense, heavy, normal, light }

class Status {
  const Status(
    this.delay,
    this.mode,
    this.steam,
    this.rinseAidEnabled,
    this.washTemperature,
    this.heatedDry,
    this.muted,
    this.uiLocked,
    this.sabbathMode,
    this.demoMode,
    this.leakDetectionEnabled,
    this.operatingMode,
    this.cycleState,
    this.cycleMode,
    this.cycleStep,
    this.cycleSubstep,
    this.duration,
    this.stepsExecuted,
    this.stepsEstimated,
    this.lastErrorId,
    this.minimumTeperature,
    this.maximumTemperature,
    this.lastTemperature,
    this.minimumTurbidity,
    this.maximumTurbidity,
    this.cyclesStarted,
    this.cyclesCompleted,
    this.doorCount,
    this.powerOnCount,
    this.record,
  );

  factory Status.fromDatabaseRecord(TableRecord record) {
    ByteData bytes = record.data.buffer.asByteData(record.data.offsetInBytes, record.data.lengthInBytes);
    int byte0 = bytes.getUint8(0);
    int byte1 = bytes.getUint8(1);
    int byte2 = bytes.getUint8(2);
    int byte3 = bytes.getUint8(3);
    return Status(
      DishwasherDelay.values[byte0 & 0x03],
      DishwasherUserCycleSelection.values[(byte0 & 0x0C) >> 2],
      byte0 & 0x10 > 0,
      byte0 & 0x20 > 0,
      DishwasherWashTemperature.values[(byte0 & 0xC0) >> 6],
      byte1 & 0x01 > 0,
      byte1 & 0x02 > 0,
      byte1 & 0x04 > 0,
      byte1 & 0x08 > 0,
      byte1 & 0x10 > 0,
      byte1 & 0x20 > 0,
      _nullOrEnum(DishwasherOperatingMode.values, byte2 & 0x0F),
      _nullOrEnum(DishwasherCycleState.values, (byte2 & 0xF0) >> 4),
      _nullOrEnum(DishwasherCycleMode.values, byte3 & 0x07),
      _nullOrByte(bytes.getUint8(4)),
      _nullOrByte(bytes.getUint8(5)),
      _nullOrDurationInMinutes(bytes.getUint16(6)),
      _nullOrByte(bytes.getUint8(8)),
      _nullOrByte(bytes.getUint8(9)),
      _nullOrByte(bytes.getUint8(10)),
      _nullOrFahrenheitToCelsius(bytes.getUint8(12)),
      _nullOrFahrenheitToCelsius(bytes.getUint8(13)),
      _nullOrFahrenheitToCelsius(bytes.getUint8(14)),
      _nullOrDouble(bytes.getUint16(16)),
      _nullOrDouble(bytes.getUint16(18)),
      _nullOrWord(bytes.getUint16(20)),
      _nullOrWord(bytes.getUint16(22)),
      _nullOrWord(bytes.getUint16(24)),
      _nullOrWord(bytes.getUint16(26)),
      record,
    );
  }

  static const Status none = Status(
    DishwasherDelay.hours0,
    DishwasherUserCycleSelection.autosense,
    false,
    false,
    DishwasherWashTemperature.normal,
    false,
    false,
    false,
    false,
    false,
    false,
    null,
    null,
    null,
    null,
    null,
    null,
    0,
    0,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
  );

  static int _nullOrByte(int value) => value == 0xFF ? null : value;
  static int _nullOrWord(int value) => value == 0xFFFF ? null : value;
  static double _nullOrDouble(int value) => value == 0xFFFF ? null : value.toDouble();
  static T _nullOrEnum<T>(List<T> values, int value) => value >= values.length ? null : values[value];
  static Duration _nullOrDurationInMinutes(int value) => value == 0xFFFF ? null : Duration(minutes: value);
  static double _nullOrFahrenheitToCelsius(int f) => f == 0xFF ? null : (f - 32.0) * 5.0 / 9.0;

  final DishwasherDelay delay;
  final DishwasherUserCycleSelection mode;
  final bool steam;
  final bool rinseAidEnabled;
  final DishwasherWashTemperature washTemperature;
  final bool heatedDry;
  final bool muted;
  final bool uiLocked;
  final bool sabbathMode;
  final bool demoMode;
  final bool leakDetectionEnabled;
  final DishwasherOperatingMode operatingMode;
  final DishwasherCycleState cycleState;
  final DishwasherCycleMode cycleMode;
  final int cycleStep;
  final int cycleSubstep;
  final Duration duration;
  final int stepsExecuted;
  final int stepsEstimated;
  final int lastErrorId;
  final double minimumTeperature;
  final double maximumTemperature;
  final double lastTemperature;
  final double minimumTurbidity;
  final double maximumTurbidity;
  final int cyclesStarted;
  final int cyclesCompleted;
  final int doorCount;
  final int powerOnCount;
  final TableRecord record;

  double get progress => stepsEstimated > 0 ? math.min(stepsExecuted / stepsEstimated, 1.0) : 1.0;

  bool get delayed => operatingMode == DishwasherOperatingMode.delayStart && delay != DishwasherDelay.hours0;
  bool get paused => operatingMode == DishwasherOperatingMode.pause || cycleState == DishwasherCycleState.pause;

  String get idleCycleDescription {
    StringBuffer result = StringBuffer();
    switch (operatingMode) {
      case DishwasherOperatingMode.lowPower:
        result.write('LOW POWER');
        break;
      case DishwasherOperatingMode.powerUp:
        result.write('POWER UP');
        break;
      case DishwasherOperatingMode.standBy:
        result.write('STAND BY');
        break;
      case DishwasherOperatingMode.delayStart:
        result.write('DELAY START');
        switch (delay) {
          case DishwasherDelay.hours0:
            result.write(' 0H');
            break;
          case DishwasherDelay.hours2:
            result.write(' 2H');
            break;
          case DishwasherDelay.hours4:
            result.write(' 4H');
            break;
          case DishwasherDelay.hours8:
            result.write(' 8H');
            break;
        }
        break;
      case DishwasherOperatingMode.endOfCycle:
        result.write('END OF CYCLE');
        break;
      case DishwasherOperatingMode.downloadMode:
        result.write('DOWNLOAD MODE');
        break;
      case DishwasherOperatingMode.sensorCheckMode:
        result.write('SENSOR CHECK MODE');
        break;
      case DishwasherOperatingMode.loadActivationMode:
        result.write('LOAD ACTIVATION MODE');
        break;
      case DishwasherOperatingMode.machineControlOnly:
        result.write('MACHINE CONTROL ONLY');
        break;
      default:
        return '';
    }
    return result.toString();
  }

  String get activeCycleDescription {
    StringBuffer result = StringBuffer();
    switch (operatingMode) {
      case DishwasherOperatingMode.pause:
        result.write('PAUSED');
        break;
      case DishwasherOperatingMode.active:
        switch (cycleMode) {
          case DishwasherCycleMode.autosense:
            result.write('AUTOSENSE');
            break;
          case DishwasherCycleMode.heavy:
            result.write('HEAVY');
            break;
          case DishwasherCycleMode.normal:
            result.write('NORMAL');
            break;
          case DishwasherCycleMode.light:
            result.write('LIGHT');
            break;
          default:
            result.write('ACTIVE');
        }
        break;
      case DishwasherOperatingMode.endOfCycle:
        result.write('END OF CYCLE');
        break;
      default:
        return '';
    }
    switch (cycleState) {
      case DishwasherCycleState.preWash:
        result.write(' - PREWASH');
        break;
      case DishwasherCycleState.sensing:
        result.write(' - SENSING');
        break;
      case DishwasherCycleState.mainWash:
        result.write(' - MAIN WASH');
        break;
      case DishwasherCycleState.drying:
        result.write(' - DRYING');
        break;
      case DishwasherCycleState.sanitizing:
        result.write(' - SANITIZING');
        break;
      case DishwasherCycleState.turbidityCalibration:
        result.write(' - CALIBRATING TURBIDITY SENSOR');
        break;
      case DishwasherCycleState.diverterCalibration:
        result.write(' - CALIBRATING DIVERTER');
        break;
      case DishwasherCycleState.pause:
        if (operatingMode != DishwasherOperatingMode.pause)
          result.write(' - PAUSED');
        break;
      case DishwasherCycleState.rinsing:
        result.write(' - RINSING');
        break;
      case DishwasherCycleState.none:
        break;
    }
    if (cycleStep != null && cycleSubstep != null)
      result.write(' - ${cycleStep}:$cycleSubstep');
    return result.toString();
  }

  String get washTemperatureDescription {
    switch (washTemperature) {
      case DishwasherWashTemperature.normal:
        return '';
      case DishwasherWashTemperature.boost:
        return 'BOOST';
      case DishwasherWashTemperature.sanitize:
        return 'SANITIZE';
      default:
        return 'WASH TEMPERATURE UNKNOWN';
    }
  }

  String get durationDescription {
    if (duration == null)
      return 'unknown';
    if (duration.inHours > 0)
      return '${duration.inHours}h ${duration.inMinutes - duration.inHours * 60}m';
    return '${duration.inMinutes}m';
  }

  Status copyWith({
    DishwasherDelay delay,
    DishwasherUserCycleSelection mode,
    bool steam,
    bool rinseAidEnabled,
    DishwasherWashTemperature washTemperature,
    bool heatedDry,
    bool muted,
    bool uiLocked,
    bool sabbathMode,
    bool demoMode,
    bool leakDetectionEnabled,
    DishwasherOperatingMode operatingMode,
    DishwasherCycleState cycleState,
    DishwasherCycleMode cycleMode,
    int cycleStep,
    int cycleSubstep,
    Duration duration,
    int stepsExecuted,
    int stepsEstimated,
    int lastErrorId,
    double minimumTeperature,
    double maximumTemperature,
    double lastTemperature,
    double minimumTurbidity,
    double maximumTurbidity,
    int cyclesStarted,
    int cyclesCompleted,
    int doorCount,
    int powerOnCount,
    TableRecord record,
  }) {
    return Status(
      delay ?? this.delay,
      mode ?? this.mode,
      steam ?? this.steam,
      rinseAidEnabled ?? this.rinseAidEnabled,
      washTemperature ?? this.washTemperature,
      heatedDry ?? this.heatedDry,
      muted ?? this.muted,
      uiLocked ?? this.uiLocked,
      sabbathMode ?? this.sabbathMode,
      demoMode ?? this.demoMode,
      leakDetectionEnabled ?? this.leakDetectionEnabled,
      operatingMode ?? this.operatingMode,
      cycleState ?? this.cycleState,
      cycleMode ?? this.cycleMode,
      cycleStep ?? this.cycleStep,
      cycleSubstep ?? this.cycleSubstep,
      duration ?? this.duration,
      stepsExecuted ?? this.stepsExecuted,
      stepsEstimated ?? this.stepsEstimated,
      lastErrorId ?? this.lastErrorId,
      minimumTeperature ?? this.minimumTeperature,
      maximumTemperature ?? this.maximumTemperature,
      lastTemperature ?? this.lastTemperature,
      minimumTurbidity ?? this.minimumTurbidity,
      maximumTurbidity ?? this.maximumTurbidity,
      cyclesStarted ?? this.cyclesStarted,
      cyclesCompleted ?? this.cyclesCompleted,
      doorCount ?? this.doorCount,
      powerOnCount ?? this.powerOnCount,
      record ?? this.record,
    );
  }

  void dump() {
    print('delay: $delay');
    print('mode: $mode');
    print('steam: $steam');
    print('rinseAidEnabled: $rinseAidEnabled');
    print('washTemperature: $washTemperature');
    print('heatedDry: $heatedDry');
    print('muted: $muted');
    print('uiLocked: $uiLocked');
    print('sabbathMode: $sabbathMode');
    print('demoMode: $demoMode');
    print('leakDetectionEnabled: $leakDetectionEnabled');
    print('operatingMode: $operatingMode');
    print('cycleState: $cycleState');
    print('cycleMode: $cycleMode');
    print('cycleStep: $cycleStep');
    print('cycleSubstep: $cycleSubstep');
    print('duration: $duration');
    print('stepsExecuted: $stepsExecuted');
    print('stepsEstimated: $stepsEstimated');
    print('lastErrorId: $lastErrorId');
    print('minimumTeperature: $minimumTeperature');
    print('maximumTemperature: $maximumTemperature');
    print('lastTemperature: $lastTemperature');
    print('minimumTurbidity: $minimumTurbidity');
    print('maximumTurbidity: $maximumTurbidity');
    print('cyclesStarted: $cyclesStarted');
    print('cyclesCompleted: $cyclesCompleted');
    print('doorCount: $doorCount');
    print('powerOnCount: $powerOnCount');
    print('record: $record');
  }
}
