//lib\services\vtnet_number_verification_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import 'debug_log_service.dart';
import 'tas_sdk_service.dart';
import 'jwt_signer_service.dart';

/// Result of the VTNet Number Verification flow run through the TAS SDK.
class TasVerificationResult {
  final bool success;
  final String message;

  /// Device phone number returned by VTNet, E.164 (e.g. +84368682926).
  final String? devicePhoneNumber;

  TasVerificationResult({
    required this.success,
    required this.message,
    this.devicePhoneNumber,
  });
}

/// DEMO: VTNet CAMARA Number Verification (device-phone-number) with TAS SDK.
///
/// Step 1: TAS SDK calls GET /oauth/authorize over mobile data -> auth code
/// Step 2: POST /oauth/token -> access token
/// Step 3: POST /number-verification/v1/verify -> device phone number
///
/// Steps 2 and 3 belong on the Application Server in production (the token
/// request should carry a client_assertion signed with the server's private
/// key). They run in the app here only to test the TAS SDK integration.
class VtnetNumberVerificationService {
  final DebugLogService _debugLog = DebugLogService();
  final TasSdkService _tasService = TasSdkService();

  // VTNet Open Gateway configuration
  // TODO: replace with the CLIENT_ID registered on VTNet Open Gateway if it
  // differs from the one used by the existing SNA flow.
  static const String clientId = 'UhsOT9JBoz2TJxeSwHDqNNDCgot7Nhyhbi5m3-no3P8';

  /// Must be registered for [clientId] on the Gateway. Shared by both platforms:
  /// matches com.vcs.tas_sdk.REDIRECT_URL in AndroidManifest.xml and, by its
  /// scheme, TasScheme in ios/Runner/Info.plist.
  static const String redirectUri = 'https://google.com';
  static const String scope =
      'openid dpv:FraudPreventionAndDetection number-verification:verify '
      'number-verification:device-phone-number';

  static const String authorizeEndpoint =
      'https://developers-private.viettel.vn/security-domain/oauth/authorize';
  static const String tokenEndpoint =
      'https://developers-access.viettel.vn/security-domain/oauth/token';

  /// Audience claim for the signed JAR request object. Same value
  /// ronaldo.py's __main__ example passes to sign_jar_request().
  static const String jarAudience =
      'https://developers-private.viettel.vn/security-domain';

  /// PEM file with the RSA private key used to sign the JAR `request`
  /// object (ronaldo.py's private_key_2.pem). Declared as a Flutter asset
  /// in pubspec.yaml:
  ///   flutter:
  ///     assets:
  ///       - assets/keys/private_key_2.pem
  /// with the file placed at <project root>/assets/keys/private_key_2.pem
  /// (a sibling of lib/, android/, pubspec.yaml - not inside lib/).
  // TODO: this is a test-only key path for interop testing. Do not ship a
  // production signing key inside the app - see the class-level note about
  // steps 2/3.
  static const String _privateKeyAssetPath = 'assets/keys/private_key_2.pem';

  RSAPrivateKey? _cachedPrivateKey;

  /// Path from section 4.3.8 / appendix III of the VTNet document. Section V.2.5
  /// uses /camara/number-verification/v1/device-phone-number instead; switch
  /// here if the Gateway answers 404.
  static const String devicePhoneNumberEndpoint =
      'https://developers-api.viettel.vn/afp/number-verification/v1/verify';

  static const Duration _httpTimeout = Duration(seconds: 15);

  Future<RSAPrivateKey> _loadPrivateKey() async {
    return _cachedPrivateKey ??=
        await JwtSignerService.loadPrivateKeyFromAsset(_privateKeyAssetPath);
  }

  /// Builds the Authorization Request URL. `jarRequest` is the signed JAR
  /// JWT for the `request` parameter (see [_signRequestObjects]).
  String buildAuthorizationUrl(String state, String jarRequest) {
    return Uri.parse(authorizeEndpoint)
        .replace(
          queryParameters: {
            'response_type': 'code',
            'client_id': clientId,
            'request': jarRequest,
            'redirect_uri': redirectUri,
            'scope': scope,
            'state': state,
          },
        )
        .toString();
  }

  /// Loads the (cached, app-wide) private key once and signs both request
  /// objects from it together: the JAR for step 1's `request` field and
  /// the client_assertion for step 2's `client_assertion` field. Ported
  /// from ronaldo.py's sign_jar_request / create_client_assertion_jwt.
  Future<({String jarRequest, String clientAssertion})> _signRequestObjects(
    String state,
  ) async {
    final privateKey = await _loadPrivateKey();

    final jarRequest = JwtSignerService.signJarRequest(
      clientId: clientId,
      audience: jarAudience,
      scopes: [scope],
      redirectUri: redirectUri,
      state: state,
      privateKey: privateKey,
    );
    final clientAssertion = JwtSignerService.createClientAssertionJwt(
      clientId: clientId,
      privateKey: privateKey,
    );

    return (jarRequest: jarRequest, clientAssertion: clientAssertion);
  }

  /// Runs the 3-step flow. [enteredPhoneNumber] is only compared for logging.
  Future<TasVerificationResult> verify({String? enteredPhoneNumber}) async {
    _debugLog.logInfo('[TAS DEMO] Starting VTNet Number Verification');

    try {
      // Step 1: authorization code through TAS SDK
      final state = _generateState();
      // JAR and client_assertion are signed together, from the same
      // cached private key, before step 1 starts.
      final signed = await _signRequestObjects(state);
      final authorizeUrl = buildAuthorizationUrl(state, signed.jarRequest);
      _debugLog.logInfo('[TAS DEMO] STEP 1: TAS SDK authorize');
      _debugLog.logRequest(authorizeUrl, null, null);

      final auth = await _tasService.authenticate(authorizeUrl);
      if (!auth.isSuccess) {
        final error = auth.error ?? 'NoCode';
        _debugLog.logError(
          '[TAS DEMO] STEP 1 FAILED: $error',
          auth.errorDescription,
        );
        return TasVerificationResult(
          success: false,
          message: TasSdkService.describeError(error, auth.errorDescription),
        );
      }

      if (auth.state != null && auth.state != state) {
        _debugLog.logError(
          '[TAS DEMO] STEP 1 FAILED: state mismatch',
          'expected=$state got=${auth.state}',
        );
        return TasVerificationResult(
          success: false,
          message: 'State mismatch in authorization response',
        );
      }
      _debugLog.logSuccess(
        '[TAS DEMO] STEP 1 COMPLETED: code received (metadata=${auth.metadata})',
      );

      // Step 2: exchange code for access token
      _debugLog.logInfo('[TAS DEMO] STEP 2: Exchange code for access token');
      final accessToken = await _exchangeCodeForToken(
        auth.code!,
        signed.clientAssertion,
      );
      _debugLog.logSuccess('[TAS DEMO] STEP 2 COMPLETED: access token received');

      // Step 3: verify the entered phone number against the device SIM
      _debugLog.logInfo('[TAS DEMO] STEP 3: Verify phone number');
      final verified = await _verifyPhoneNumber(
        accessToken,
        enteredPhoneNumber ?? '',
      );
      _debugLog.logSuccess(
        '[TAS DEMO] STEP 3 COMPLETED: devicePhoneNumberVerified=$verified',
      );

      if (!verified) {
        return TasVerificationResult(
          success: false,
          message: 'Phone number does not match the SIM in this device',
        );
      }

      return TasVerificationResult(
        success: true,
        message: 'Device phone number verified',
        devicePhoneNumber: enteredPhoneNumber,
      );
    } on TimeoutException {
      _debugLog.logError('[TAS DEMO] HTTP request timed out');
      rethrow;
    } catch (e) {
      _debugLog.logError('[TAS DEMO] VERIFICATION FAILED', e);
      return TasVerificationResult(
        success: false,
        message: 'An error occurred: ${e.toString()}',
      );
    }
  }

  /// Step 2: POST /oauth/token, authenticated with private_key_jwt
  /// (client_assertion signed by JwtSignerService.createClientAssertionJwt).
  Future<String> _exchangeCodeForToken(
    String code,
    String clientAssertion,
  ) async {
    final body = {
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri,
      'client_id': clientId,
      'client_assertion_type':
          'urn:ietf:params:oauth:client-assertion-type:jwt-bearer',
      'client_assertion': clientAssertion,
      'scope': scope,
    };
    const headers = {'Content-Type': 'application/x-www-form-urlencoded'};
    _debugLog.logRequest(tokenEndpoint, headers, body);

    final response = await http
        .post(Uri.parse(tokenEndpoint), headers: headers, body: body)
        .timeout(_httpTimeout);
    _debugLog.logResponse(tokenEndpoint, response.statusCode, response.body);

    final json = _decode(response.body);
    if (response.statusCode != 200) {
      throw Exception(
        'Token API ${response.statusCode}: ${_describeOAuthError(json, response.body)}',
      );
    }

    final accessToken = json?['access_token']?.toString();
    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('Token API returned no access_token');
    }
    return accessToken;
  }

  /// Step 3: POST /number-verification/v1/verify with the Bearer token.
  /// Returns `devicePhoneNumberVerified` from the response.
  Future<bool> _verifyPhoneNumber(
    String accessToken,
    String phoneNumber,
  ) async {
    // Ensure phone number is in correct format (+84xxxxxxxxx)
    String formattedPhone = phoneNumber;
    if (phoneNumber.startsWith('+84')) {
      formattedPhone = phoneNumber;
    } else if (phoneNumber.startsWith('84')) {
      formattedPhone = '+$phoneNumber';
    } else if (phoneNumber.startsWith('0')) {
      formattedPhone = '+84${phoneNumber.substring(1)}';
    } else {
      formattedPhone = '+84$phoneNumber';
    }

    // jsonEncode: the local `json` below shadows dart:convert's `json`.
    final body = jsonEncode({'phoneNumber': formattedPhone});

    final headers = {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
    };
    _debugLog.logRequest(devicePhoneNumberEndpoint, {
      'Authorization': 'Bearer ${_mask(accessToken)}',
    }, body);

    final response = await http
        .post(
          Uri.parse(devicePhoneNumberEndpoint),
          headers: headers,
          body: body,
        )
        .timeout(_httpTimeout);
    _debugLog.logResponse(
      devicePhoneNumberEndpoint,
      response.statusCode,
      response.body,
    );

    final json = _decode(response.body);
    if (response.statusCode != 200) {
      throw Exception(
        'Number Verification API ${response.statusCode}: '
        '${_describeOAuthError(json, response.body)}',
      );
    }

    // Response: {"devicePhoneNumberVerified": true|false}
    final verified = json?['devicePhoneNumberVerified'];
    if (verified is! bool) {
      throw Exception('Invalid verification response: $json');
    }
    return verified;
  }

  /// Converts +84xxx / 84xxx / 0xxx to the local part shown after "+84 ".
  static String toLocalNumber(String phone) {
    var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('84')) {
      digits = digits.substring(2);
    } else if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return digits;
  }

  Map<String, dynamic>? _decode(String body) {
    try {
      final decoded = json.decode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String _describeOAuthError(Map<String, dynamic>? json, String rawBody) {
    if (json == null) return rawBody.isEmpty ? 'no response body' : rawBody;
    final error = json['error'];
    final description = json['error_description'];
    if (error != null) {
      return description != null ? '$error - $description' : '$error';
    }
    return json.toString();
  }

  String _generateState() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  String _mask(String token) =>
      token.length <= 10 ? '***' : '${token.substring(0, 10)}...';
}
