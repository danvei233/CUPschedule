import 'dart:io';

Stream<String> recordingEvents(String url, String key) async* {
  final socket = await WebSocket.connect(
    url,
    headers: {'X-API-Key': key},
  ).timeout(const Duration(seconds: 15));
  socket.pingInterval = const Duration(seconds: 20);
  try {
    await for (final event in socket) {
      if (event is String) yield event;
    }
  } finally {
    await socket.close();
  }
}
