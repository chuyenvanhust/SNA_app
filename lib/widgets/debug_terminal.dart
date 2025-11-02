import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/debug_log_service.dart';

/// Debug terminal widget that displays API logs
class DebugTerminal extends StatefulWidget {
  const DebugTerminal({super.key});

  @override
  State<DebugTerminal> createState() => _DebugTerminalState();
}

class _DebugTerminalState extends State<DebugTerminal> {
  final DebugLogService _logService = DebugLogService();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Color _getLogColor(DebugLogType type) {
    switch (type) {
      case DebugLogType.request:
        return Colors.blue;
      case DebugLogType.response:
        return Colors.green;
      case DebugLogType.error:
        return Colors.red;
      case DebugLogType.success:
        return Colors.teal;
      case DebugLogType.info:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E), // Dark background like a real terminal
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Terminal Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D2D),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              border: Border(bottom: BorderSide(color: Colors.grey.shade800)),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal, color: Colors.greenAccent, size: 24),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Debug Terminal',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Clear logs button
                IconButton(
                  icon: const Icon(Icons.clear_all, color: Colors.orange),
                  onPressed: () {
                    setState(() {
                      _logService.clearLogs();
                    });
                  },
                  tooltip: 'Clear logs',
                ),
                // Copy all logs button
                // IconButton(
                //   icon: const Icon(Icons.copy, color: Colors.blueAccent),
                //   onPressed: () {
                //     final allLogs = _logService.logs
                //         .map((log) => '[${log.formattedTime}] ${log.message}')
                //         .join('\n\n');
                //     Clipboard.setData(ClipboardData(text: allLogs));
                //     ScaffoldMessenger.of(context).showSnackBar(
                //       const SnackBar(
                //         content: Text('Logs copied to clipboard'),
                //         duration: Duration(seconds: 2),
                //       ),
                //     );
                //   },
                //   tooltip: 'Copy all logs',
                // ),
                // Close button
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),

          // Terminal Content
          Expanded(
            child: ValueListenableBuilder<List<DebugLog>>(
              valueListenable: _logService.logsNotifier,
              builder: (context, logs, _) {
                // Auto-scroll to bottom when new logs arrive
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToBottom();
                });

                if (logs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No logs yet...\nAPI requests and responses will appear here.',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Timestamp
                          Text(
                            '[${log.formattedTime}]',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Log message
                          Expanded(
                            child: SelectableText(
                              log.message,
                              style: TextStyle(
                                color: _getLogColor(log.type),
                                fontSize: 13,
                                fontFamily: 'monospace',
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Terminal Footer (info bar)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D2D),
              border: Border(top: BorderSide(color: Colors.grey.shade800)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.grey, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: ValueListenableBuilder<List<DebugLog>>(
                    valueListenable: _logService.logsNotifier,
                    builder: (context, logs, _) {
                      return Text(
                        '${logs.length} log entries',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper function to show debug terminal from anywhere
void showDebugTerminal(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const DebugTerminal(),
  );
}
