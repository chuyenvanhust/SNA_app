import 'package:flutter/services.dart';

/// Result of a TAS SDK authentication (VTNet Number Verification step 1).
class TasAuthResult {
  final String? code;
  final String? state;
  final Map<String, String> metadata;

  /// TAS ExceptionCode name (e.g. CellularDisable, ConsentDenied) or a local
  /// code such as MissingPlugin / SdkException. Null on success.
  final String? error;
  final String? errorDescription;

  TasAuthResult({
    this.code,
    this.state,
    this.metadata = const {},
    this.error,
    this.errorDescription,
  });

  bool get isSuccess => error == null && code != null && code!.isNotEmpty;
}

/// Calls the native TAS SDK over a MethodChannel (Android: MainActivity.kt,
/// iOS: AppDelegate.swift). Both platforms reply with the same map.
///
/// On both platforms the SDK sends the authorize request over mobile data,
/// bypassing WiFi, and returns the authorization code delivered on the
/// registered redirect URL. Android opens the consent page in a Custom Tab when
/// needed; iOS runs the authorize flow in ASWebAuthenticationSession.
class TasSdkService {
  static const MethodChannel _channel = MethodChannel('com.example.appv1/tas');

  Future<TasAuthResult> authenticate(String authorizeUrl) async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'authenticate',
        {'authorizeUrl': authorizeUrl},
      );

      if (result == null) {
        return TasAuthResult(
          error: 'SdkError',
          errorDescription: 'No response from native code',
        );
      }

      final error = result['error']?.toString();
      if (error != null && error.isNotEmpty) {
        return TasAuthResult(
          error: error,
          errorDescription: result['error_description']?.toString(),
        );
      }

      final rawMetadata = result['metadata'];
      return TasAuthResult(
        code: result['code']?.toString(),
        state: result['state']?.toString(),
        metadata: rawMetadata is Map
            ? rawMetadata.map((k, v) => MapEntry(k.toString(), v.toString()))
            : const {},
      );
    } on MissingPluginException {
      return TasAuthResult(
        error: 'MissingPlugin',
        errorDescription: 'TAS SDK is only integrated on Android and iOS',
      );
    } on PlatformException catch (e) {
      return TasAuthResult(error: e.code, errorDescription: e.message);
    }
  }

  /// Human readable message for a TAS ExceptionCode.
  static String describeError(String error, String? description) {
    final detail = (description == null || description.isEmpty)
        ? ''
        : ' ($description)';
    switch (error) {
      case 'CellularDisable':
        return 'Mobile data (3G/4G/5G) is off. Please enable it and try again.';
      case 'ConsentDenied':
        return 'You denied the consent request.';
      case 'UserNotFound':
        return 'Subscriber not found. Please use a Viettel SIM on mobile data.';
      case 'NetworkError':
        return 'Network error during authentication$detail';
      case 'CloseBrowserWithoutResult':
        return 'The browser was closed before authentication finished.';
      case 'CannotOpenBrowser':
        return 'Cannot open a browser on this device.';
      case 'InvalidUrl':
        return 'The authorization URL is invalid$detail';
      case 'SendAuthorizeCodeFailed':
        return 'Failed to hand the authorization code to the app.';
      default:
        return 'TAS authentication failed: $error$detail';
    }
  }
}
