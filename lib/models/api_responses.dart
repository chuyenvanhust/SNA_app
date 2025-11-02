/// API Response Models for Viettel Number Verification

/// Response from the authorizer API (Step 1)
class AuthorizerResponse {
  final String redirectUri;
  final String? code;

  AuthorizerResponse({required this.redirectUri, this.code});

  factory AuthorizerResponse.fromJson(Map<String, dynamic> json) {
    final redirectUri = json['redirect_uri'] as String;
    // Extract code from redirect_uri query parameter
    final uri = Uri.parse(redirectUri);
    final code = uri.queryParameters['code'];

    return AuthorizerResponse(redirectUri: redirectUri, code: code);
  }
}

/// Response from the token API (Step 2)
class TokenResponse {
  final String jwt;

  TokenResponse({required this.jwt});

  factory TokenResponse.fromJson(Map<String, dynamic> json) {
    return TokenResponse(jwt: json['jwt'] as String);
  }
}

/// Response from the phone verification API (Step 3)
class PhoneVerificationResponse {
  final bool devicePhoneNumberVerified;

  PhoneVerificationResponse({required this.devicePhoneNumberVerified});

  factory PhoneVerificationResponse.fromJson(Map<String, dynamic> json) {
    return PhoneVerificationResponse(
      devicePhoneNumberVerified: json['devicePhoneNumberVerified'] as bool,
    );
  }
}

/// Result of the complete verification flow
class VerificationResult {
  final bool success;
  final String message;
  final PhoneVerificationResponse? data;

  VerificationResult({required this.success, required this.message, this.data});
}
