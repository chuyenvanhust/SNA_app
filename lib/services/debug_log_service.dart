import 'package:flutter/foundation.dart';

class DebugLogService {
  static final DebugLogService _instance = DebugLogService._internal();
  factory DebugLogService() => _instance;
  DebugLogService._internal();

  final List<DebugLog> _logs = [];
  final _logController = ValueNotifier<List<DebugLog>>([]);

  /// Stream of logs for UI updates
  ValueNotifier<List<DebugLog>> get logsNotifier => _logController;

  /// Get all logs
  List<DebugLog> get logs => List.unmodifiable(_logs);

  /// Add a log entry
  void addLog(String message, {DebugLogType type = DebugLogType.info}) {
    final log = DebugLog(
      message: message,
      timestamp: DateTime.now(),
      type: type,
    );
    _logs.add(log);
    _logController.value = List.from(_logs);

    // Also print to console for development
    if (kDebugMode) {
      print('[${log.typeString}] ${log.formattedTime}: $message');
    }
  }

  /// Log API request
  void logRequest(
    String endpoint,
    Map<String, dynamic>? headers,
    dynamic body,
  ) {
    addLog(
      'REQUEST: $endpoint\nHeaders: ${headers ?? {}}\nBody: ${body ?? 'none'}',
      type: DebugLogType.request,
    );
  }

  /// Log API response
  void logResponse(String endpoint, int statusCode, dynamic body) {
    addLog(
      'RESPONSE: $endpoint\nStatus: $statusCode\nBody: $body',
      type: DebugLogType.response,
    );
  }

  /// Log error
  void logError(String message, [dynamic error]) {
    addLog(
      'ERROR: $message${error != null ? '\n$error' : ''}',
      type: DebugLogType.error,
    );
  }

  /// Log success
  void logSuccess(String message) {
    addLog('SUCCESS: $message', type: DebugLogType.success);
  }

  /// Log info
  void logInfo(String message) {
    addLog('INFO: $message', type: DebugLogType.info);
  }

  /// Clear all logs
  void clearLogs() {
    _logs.clear();
    _logController.value = [];
  }

  /// Dispose resources
  void dispose() {
    _logController.dispose();
  }
}

/// Type of debug log
enum DebugLogType { request, response, error, success, info }

/// Individual log entry
class DebugLog {
  final String message;
  final DateTime timestamp;
  final DebugLogType type;

  DebugLog({
    required this.message,
    required this.timestamp,
    required this.type,
  });

  String get formattedTime {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}.'
        '${timestamp.millisecond.toString().padLeft(3, '0')}';
  }

  String get typeString {
    switch (type) {
      case DebugLogType.request:
        return 'REQUEST';
      case DebugLogType.response:
        return 'RESPONSE';
      case DebugLogType.error:
        return 'ERROR';
      case DebugLogType.success:
        return 'SUCCESS';
      case DebugLogType.info:
        return 'INFO';
    }
  }
}
