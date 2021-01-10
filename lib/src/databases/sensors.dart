import 'dart:typed_data';

import 'package:home_automation_tools/all.dart';

const int dbFamilyRoomSensors = 0x0000000000001001;
const int dbFamilyRoomSensorsLength = 8*8;
const int dbOutsideSensors = 0x0000000000001000;
const int dbOutsideSensorsLength = 10*8;

MeasurementPacket parseFamilyRoomSensorsRecord(TableRecord record) {
  final ByteData bytes = record.data.buffer.asByteData(record.data.offsetInBytes, record.data.lengthInBytes);
  final MeasurementStation station = new MeasurementStation(siteName: 'family room uRADMonitor');
  return MeasurementPacket(<Measurement>[
    new URadMonitorRadiation.fromDoseRate(
      station: station,
      timestamp: record.timestamp,
      doseRate: bytes.getFloat64(0 * 8),
    ),
    new RawTemperature(bytes.getFloat64(1 * 8), station: station, timestamp: record.timestamp),
    new AirQualityParameter.humidity(bytes.getFloat64(2 * 8), station: station, timestamp: record.timestamp),
    new AirQualityParameter.pressure(bytes.getFloat64(3 * 8), station: station, timestamp: record.timestamp),
    new AirQualityParameter.volatileOrganicCompounds(bytes.getFloat64(4 * 8), station: station, timestamp: record.timestamp),
    new AirQualityParameter.carbonDioxide(bytes.getFloat64(5 * 8), station: station, timestamp: record.timestamp),
    new AirQualityParameter.noise(bytes.getFloat64(6 * 8), station: station, timestamp: record.timestamp),
    new AirQualityParameter.pm2_5(bytes.getFloat64(7 * 8), station: station, timestamp: record.timestamp),
  ]);
}

MeasurementPacket parseOutsideSensorsRecord(TableRecord record) {
  final ByteData bytes = record.data.buffer.asByteData(record.data.offsetInBytes, record.data.lengthInBytes);
  final MeasurementStation station = new MeasurementStation(siteName: 'outside uRADMonitor', outside: true);
  return MeasurementPacket(<Measurement>[
    new RawTemperature(bytes.getFloat64(0 * 8), station: station, timestamp: record.timestamp),
    new AirQualityParameter.humidity(bytes.getFloat64(1 * 8), station: station, timestamp: record.timestamp),
    new AirQualityParameter.pressure(bytes.getFloat64(2 * 8), station: station, timestamp: record.timestamp),
    new AirQualityParameter.volatileOrganicCompounds(bytes.getFloat64(3 * 8), station: station, timestamp: record.timestamp),
    new AirQualityParameter.carbonDioxide(bytes.getFloat64(4 * 8), station: station, timestamp: record.timestamp),
    new AirQualityParameter.noise(bytes.getFloat64(5 * 8), station: station, timestamp: record.timestamp),
    new AirQualityParameter.pm1_0(bytes.getFloat64(6 * 8), station: station, timestamp: record.timestamp),
    new AirQualityParameter.pm2_5(bytes.getFloat64(7 * 8), station: station, timestamp: record.timestamp),
    new AirQualityParameter.pm10(bytes.getFloat64(8 * 8), station: station, timestamp: record.timestamp),
    new AirQualityParameter.ozone(bytes.getFloat64(9 * 8), station: station, timestamp: record.timestamp),
  ]);
}
