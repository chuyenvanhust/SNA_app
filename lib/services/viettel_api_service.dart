import 'dart:convert';
import 'dart:io';
import '../models/api_responses.dart';
import 'debug_log_service.dart';
import 'vonage_cellular_service.dart';

/// Service to handle Viettel Number Verification API calls
/// Now using Vonage Client Library for cellular network requests
class ViettelApiService {
  final DebugLogService _debugLog = DebugLogService();
  final VonageCellularService _vonageService = VonageCellularService();
  static const String baseUrl = 'https://developers-api.viettel.vn';

  // API Configuration
  static const String clientId = 'netmind-clientId-24102025';
  static const String redirectUri = 'https://developers-api.viettel.vn/abc/';
  static const String provisionKey = 'Oauth-Token-Dispenser-Key';
  static const String customerName = 'Bank1';
  static const String correlator = '123-456-789';

  /// Make a POST request using Vonage cellular network for number verification
  Future<Map<String, dynamic>> _makePostRequest(
    String urlString,
    Map<String, String> headers,
    String body,
  ) async {
    // Log request
    _debugLog.logRequest(urlString, headers, body.isEmpty ? null : body);

    try {
      // Use Vonage POST method via reflection to access internal API
      final response = await _vonageService.makeCellularPostRequest(
        url: urlString,
        headers: headers,
        body: body,
        debug: false,
      );

      print('Vonage Response: $response');

      // Check if request was successful
      if (_vonageService.isSuccessResponse(response)) {
        final httpStatus = response['http_status'] as int;
        final responseBody = _vonageService.parseResponseBody(response);

        print('Response status: $httpStatus');
        print('Response body: $responseBody');

        // Log response
        _debugLog.logResponse(
          urlString,
          httpStatus,
          responseBody?.toString() ?? '',
        );

        if (httpStatus == 200 || httpStatus == 201) {
          return responseBody ?? {};
        } else {
          _debugLog.logError('API Error: $httpStatus', responseBody);
          throw Exception('API Error: $httpStatus - $responseBody');
        }
      } else {
        // Handle Vonage SDK errors
        final errorMessage = _vonageService.getErrorMessage(response);
        print('Vonage Error: $errorMessage');
        _debugLog.logError('Cellular request failed', errorMessage);

        // Try fallback to regular HTTP if cellular fails
        print('Attempting fallback to regular HTTP...');
        return await _makeFallbackPostRequest(urlString, headers, body);
      }
    } catch (e) {
      print('Request error: $e');
      _debugLog.logError('Request failed', e);

      // Try fallback to regular HTTP on any error
      try {
        print('Attempting fallback to regular HTTP...');
        return await _makeFallbackPostRequest(urlString, headers, body);
      } catch (fallbackError) {
        print('Fallback also failed: $fallbackError');
        rethrow;
      }
    }
  }

  /// Fallback POST request using dart:io HttpClient
  Future<Map<String, dynamic>> _makeFallbackPostRequest(
    String urlString,
    Map<String, String> headers,
    String body,
  ) async {
    final uri = Uri.parse(urlString);
    final client = HttpClient();

    _debugLog.logInfo('Using fallback HTTP request...');

    try {
      final request = await client.postUrl(uri);

      // Set headers
      headers.forEach((key, value) {
        request.headers.set(key, value);
      });

      // Write body
      request.write(body);

      // Get response
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      print('Fallback Response status: ${response.statusCode}');
      print('Fallback Response body: $responseBody');

      // Log response
      _debugLog.logResponse(urlString, response.statusCode, responseBody);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(responseBody);
      } else {
        _debugLog.logError('API Error: ${response.statusCode}', responseBody);
        throw Exception('API Error: ${response.statusCode} - $responseBody');
      }
    } catch (e) {
      print('Fallback request error: $e');
      _debugLog.logError('Fallback request failed', e);
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Complete 3-step verification flow
  ///
  /// Step 1: Get authorization code
  /// Step 2: Exchange code for JWT token
  /// Step 3: Verify phone number with JWT
  Future<VerificationResult> verifyPhoneNumber(String phoneNumber) async {
    _debugLog.logInfo('Starting phone verification for: 84$phoneNumber');

    try {
      // Step 1: Get authorization code
      print('Step 1: Getting authorization code...');
      _debugLog.logInfo('STEP 1: Getting authorization code...');
      final authResponse = await _getAuthorizationCode(phoneNumber);

      if (authResponse.code == null || authResponse.code!.isEmpty) {
        _debugLog.logError('STEP 1 FAILED: No authorization code received');
        return VerificationResult(
          success: false,
          message: 'Failed to get authorization code',
        );
      }

      print('Step 1 completed. Code received.');
      _debugLog.logSuccess('STEP 1 COMPLETED: Authorization code received');

      // Step 2: Get JWT token
      print('Step 2: Getting JWT token...');
      _debugLog.logInfo('STEP 2: Getting JWT token...');
      final tokenResponse = await _getJwtToken(authResponse.code!);

      if (tokenResponse.jwt.isEmpty) {
        _debugLog.logError('STEP 2 FAILED: No JWT token received');
        return VerificationResult(
          success: false,
          message: 'Failed to get JWT token',
        );
      }

      print('Step 2 completed. JWT received.');
      _debugLog.logSuccess('STEP 2 COMPLETED: JWT token received');

      // Step 3: Verify phone number
      print('Step 3: Verifying phone number...');
      _debugLog.logInfo('STEP 3: Verifying phone number...');
      final verificationResponse = await _verifyPhoneNumberWithJwt(
        phoneNumber,
        tokenResponse.jwt,
      );

      print(
        'Step 3 completed. Verification result: ${verificationResponse.devicePhoneNumberVerified}',
      );

      if (verificationResponse.devicePhoneNumberVerified) {
        _debugLog.logSuccess(
          'STEP 3 COMPLETED: Phone number verified successfully!',
        );
        return VerificationResult(
          success: true,
          message: 'Phone number verified successfully',
          data: verificationResponse,
        );
      } else {
        _debugLog.logError('STEP 3 FAILED: Phone number not verified');
        return VerificationResult(
          success: false,
          message: 'The phone number not match with the device',
          data: verificationResponse,
        );
      }
    } catch (e) {
      print('Error during verification: $e');
      _debugLog.logError('VERIFICATION FAILED', e);
      return VerificationResult(
        success: false,
        message: 'An error occurred: ${e.toString()}',
      );
    }
  }

  /// Step 1: Get authorization code from authorizer endpoint
  Future<AuthorizerResponse> _getAuthorizationCode(String phoneNumber) async {
    final bodyParams = {
      'response_type': 'code',
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'scope': 'sherlockapiresource/write',
      'provision_key': provisionKey,
      'authenticated_userid': 'test_id',
      'grant_type': 'authorization_code',
      'customerName': 'abcd',
    };

    // Convert map to URL-encoded string
    final bodyString = bodyParams.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');

    final jsonResponse = await _makePostRequest('$baseUrl/camara/authorizer', {
      'Content-Type': 'application/x-www-form-urlencoded',
      'x-correlator': correlator,
    }, bodyString);

    return AuthorizerResponse.fromJson(jsonResponse);
  }

  /// Step 2: Exchange code for JWT token
  Future<TokenResponse> _getJwtToken(String code) async {
    final jsonResponse = await _makePostRequest(
      '$baseUrl/camara/token',
      {'Content-Type': 'application/x-www-form-urlencoded', 'code': code},
      '', // Empty body for this request
    );

    return TokenResponse.fromJson(jsonResponse);
  }

  /// Step 3: Verify phone number using JWT token
  Future<PhoneVerificationResponse> _verifyPhoneNumberWithJwt(
    String phoneNumber,
    String jwt,
  ) async {
    // Ensure phone number is in correct format (84xxxxxxxxx)
    String formattedPhone = phoneNumber;
    if (phoneNumber.startsWith('+84')) {
      formattedPhone = phoneNumber.substring(1);
    } else if (phoneNumber.startsWith('84')) {
      formattedPhone = phoneNumber;
    } else if (phoneNumber.startsWith('0')) {
      formattedPhone = '84${phoneNumber.substring(1)}';
    } else {
      formattedPhone = '84$phoneNumber';
    }

    final body = json.encode({'phoneNumber': formattedPhone});

    final jsonResponse =
        await _makePostRequest('$baseUrl/number-verification/v0/verify', {
          'Authorization': 'Bearer $jwt',
          'customerName': customerName,
          'x-correlator': correlator,
          'Content-Type': 'application/json',
        }, body);

    return PhoneVerificationResponse.fromJson(jsonResponse);
  }
}
