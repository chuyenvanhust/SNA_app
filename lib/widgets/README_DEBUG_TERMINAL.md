# Debug Terminal Feature

## Overview
The Debug Terminal is a developer tool that provides real-time logging and debugging capabilities for API requests and responses in the application.

## Features

### 🔍 Real-time Logging
- Captures all API requests with headers and body
- Displays API responses with status codes
- Tracks errors and exceptions
- Shows step-by-step verification process

### 🎨 User Interface
- **Dark terminal-style UI** - Professional console appearance
- **Color-coded logs** - Different colors for different log types:
  - 🔵 Blue: API Requests
  - 🟢 Green: API Responses
  - 🔴 Red: Errors
  - ✅ Teal: Success messages
  - ℹ️ Gray: Info messages
- **Timestamps** - Precise timing for each log entry (HH:MM:SS.mmm)
- **Auto-scroll** - Automatically scrolls to newest logs

### 🛠️ Actions
- **Clear Logs** - Remove all logs from the terminal
- **Copy Logs** - Copy all logs to clipboard for sharing
- **Close Terminal** - Dismiss the terminal panel

## Usage

### Accessing the Terminal
Both the Phone Verification Screen and Welcome Screen have a **Terminal button** (📟) in the top-right corner of the AppBar.

1. Tap the terminal icon to open the debug terminal
2. The terminal slides up from the bottom of the screen
3. All API activity is logged automatically

### Log Types

#### Request Logs
```
🔵 REQUEST: https://api.example.com/endpoint
Headers: {Content-Type: application/json}
Body: {"phoneNumber": "84123456789"}
```

#### Response Logs
```
🟢 RESPONSE: https://api.example.com/endpoint
Status: 200
Body: {"success": true, "data": {...}}
```

#### Error Logs
```
🔴 ERROR: Connection failed
Details: SocketException: Failed to connect
```

#### Step Progress
```
ℹ️ INFO: 🚀 Starting phone verification for: 84123456789
ℹ️ INFO: 📝 STEP 1: Getting authorization code...
✅ SUCCESS: STEP 1 COMPLETED: Authorization code received
ℹ️ INFO: 🔑 STEP 2: Getting JWT token...
✅ SUCCESS: STEP 2 COMPLETED: JWT token received
ℹ️ INFO: ✔️ STEP 3: Verifying phone number...
✅ SUCCESS: STEP 3 COMPLETED: Phone number verified successfully! ✅
```

## Architecture

### Components

#### 1. `DebugLogService` (Singleton)
- **Location**: `lib/services/debug_log_service.dart`
- **Purpose**: Centralized logging service
- **Features**:
  - Singleton pattern for app-wide access
  - ValueNotifier for reactive updates
  - Type-safe log entries
  - Console printing in debug mode

#### 2. `DebugTerminal` (Widget)
- **Location**: `lib/widgets/debug_terminal.dart`
- **Purpose**: UI component for displaying logs
- **Features**:
  - Modal bottom sheet presentation
  - Auto-scrolling list view
  - Log filtering by type
  - Export functionality

#### 3. Integration with `ViettelApiService`
The API service automatically logs all:
- HTTP requests (URL, headers, body)
- HTTP responses (status, body)
- Errors and exceptions
- Step-by-step process updates

## Best Practices

### For Developers
1. **Use appropriate log types**:
   - `logRequest()` for API calls
   - `logResponse()` for API responses
   - `logError()` for errors
   - `logSuccess()` for successful operations
   - `logInfo()` for general information

2. **Keep logs concise but informative**
3. **Include context** (which step, which operation)
4. **Use emojis** for visual scanning (optional but helpful)

### For Testing
1. Open terminal before starting a test
2. Monitor real-time API flow
3. Copy logs for bug reports
4. Clear logs between test runs

## Security Considerations

⚠️ **Important**: The debug terminal shows sensitive information including:
- API endpoints
- Request headers (may include tokens)
- Phone numbers
- JWT tokens

**Recommendations**:
- This feature should only be available in **development/debug builds**
- Consider adding a flag to disable in production
- Sanitize sensitive data in production logs

## Future Enhancements

Potential improvements:
- [ ] Log filtering by type
- [ ] Search functionality
- [ ] Export to file
- [ ] Log level configuration
- [ ] Network traffic statistics
- [ ] Performance metrics
- [ ] Dark/Light theme toggle
- [ ] Log persistence across sessions

## Example Integration

```dart
// In your service
final DebugLogService _debugLog = DebugLogService();

// Log a request
_debugLog.logRequest('https://api.example.com/endpoint', headers, body);

// Log a response
_debugLog.logResponse('https://api.example.com/endpoint', 200, responseBody);

// Log custom info
_debugLog.logInfo('Starting process...');

// Log success
_debugLog.logSuccess('Process completed!');

// Log error
_debugLog.logError('Something went wrong', exception);
```

## Troubleshooting

### Terminal not showing logs
- Check that `DebugLogService` is initialized
- Verify `logRequest()` and `logResponse()` are called
- Ensure logs are being added before the UI is rendered

### Logs not updating
- The terminal uses `ValueNotifier` - ensure it's being observed
- Check that `_logController.value` is being updated

### Performance issues with many logs
- Use the "Clear Logs" button regularly
- Consider implementing log rotation
- Add a maximum log count limit

---

**Created for**: Viettel Number Verification App v1
**Last Updated**: 2025-10-27

