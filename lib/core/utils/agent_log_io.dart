import 'dart:convert';
import 'dart:io';

void agentLog({
  required String runId,
  required String hypothesisId,
  required String location,
  required String message,
  Map<String, Object?>? data,
}) {
  // Never throw from logging; logs are best-effort.
  try {
    final payload = <String, Object?>{
      'sessionId': 'debug-session',
      'runId': runId,
      'hypothesisId': hypothesisId,
      'location': location,
      'message': message,
      'data': data ?? const <String, Object?>{},
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    // Android emulator needs host loopback via 10.0.2.2. iOS simulator can use 127.0.0.1.
    const paths = [
      'http://10.0.2.2:7242/ingest/980ed780-a6b2-4d4d-a690-5b68d3d6e67b',
      'http://127.0.0.1:7242/ingest/980ed780-a6b2-4d4d-a690-5b68d3d6e67b',
    ];

    () async {
      for (final url in paths) {
        try {
          final client = HttpClient();
          final req = await client.postUrl(Uri.parse(url));
          req.headers.contentType = ContentType.json;
          req.write(jsonEncode(payload));
          await req.close();
          client.close(force: true);
          break;
        } catch (_) {
          // try next endpoint
        }
      }
    }();
  } catch (_) {
    // swallow
  }
}
