import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

Future<Null> wakeOnLan(List<int> macAddress) async {
  // Wake-On-Lan's magic packet is six 0xFF bytes followed by the target MAC
  // address sixteen times. MAC addresses have 6 bytes.
  Uint8List buffer = new Uint8List(6 + 6 * 16);
  buffer.fillRange(0, 6, 0xFF);
  for (int index = 6; index < buffer.length; index += 1)
    buffer[index] = macAddress[index % macAddress.length];
  RawDatagramSocket socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  socket.broadcastEnabled = true;
  socket.send(buffer, new InternetAddress('255.255.255.255'), 9); // 9 is the "discard" port
  socket.close();
}
