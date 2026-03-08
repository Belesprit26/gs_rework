import 'agent_log_stub.dart' if (dart.library.io) 'agent_log_io.dart';

/// Lightweight helper to reduce boilerplate when emitting agent logs.
///
/// Binds [runId] + [hypothesisId] once; call [log] with the fields that change.
class AgentLogScope {
  const AgentLogScope({
    required this.runId,
    required this.hypothesisId,
  });

  final String runId;
  final String hypothesisId;

  void log({
    required String location,
    required String message,
    Map<String, Object?>? data,
  }) {
    agentLog(
      runId: runId,
      hypothesisId: hypothesisId,
      location: location,
      message: message,
      data: data,
    );
  }
}

