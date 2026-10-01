// lib/services/jwt_signer_service.dart
//
// Dart port of ronaldo.py: signs the JAR (JWT-secured Authorization
// Request, RFC 9101) that goes in the VTNet authorize URL's `request`
// field, plus the RS256 client_assertion used for private_key_jwt
// token-endpoint auth.
//
// Requires the `dart_jsonwebtoken` package:
//   dependencies:
//     dart_jsonwebtoken: ^3.4.1
//
// ronaldo.py computes a per-key algorithm (RS256/384/512 for RSA,
// ES256/384/512 for EC) via get_algorithm_from_private_key(), but the
// actual jwt.encode() calls always pass the literal string "RS256" and
// ignore that computed value. So in practice the script only ever
// produces RS256-signed tokens from an RSA key; the EC/Ed25519 branches
// are dead code. This port keeps only the reachable behavior: RSA +
// RS256.

import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:flutter/services.dart' show rootBundle;

class JwtSignerService {
  /// Audience for the client_assertion JWT (private_key_jwt), i.e. the
  /// token endpoint URL. Mirrors create_client_assertion_jwt's default.
  static const String tokenEndpointAudience =
      'https://developers-access.viettel.vn/security-domain/oauth/token';

  /// Loads an RSA private key from a PEM file bundled as a Flutter asset
  /// (e.g. `assets/keys/private_key_2.pem`, declared under `flutter: assets:`
  /// in pubspec.yaml). Use this on Android/iOS: `dart:io`'s `File` resolves
  /// relative paths against the process's runtime working directory, which
  /// on a mobile device is some app-sandbox path, NOT your project's source
  /// tree - so a path like `lib/../private_key_2.pem` will not resolve
  /// on-device no matter how it's written. Bundling as an asset is the way
  /// to ship a file from the source tree into the built app.
  ///
  /// SECURITY NOTE: shipping this raw private key inside a mobile app
  /// bundle is not appropriate for production - same caveat already
  /// noted in VtnetNumberVerificationService for steps 2/3, which belong
  /// on the Application Server. Keep this on-device path for interop
  /// testing only.
  static Future<RSAPrivateKey> loadPrivateKeyFromAsset(String assetPath) async {
    final pem = await rootBundle.loadString(assetPath);
    return RSAPrivateKey(pem);
  }

  /// Loads an RSA private key from a PEM file on a real filesystem path.
  /// Only meaningful for desktop/CLI Dart runs where the process's working
  /// directory is known (e.g. a host-side test harness invoked from the
  /// project root) - not usable on Android/iOS. Prefer
  /// [loadPrivateKeyFromAsset] for the Flutter app itself.
  static Future<RSAPrivateKey> loadPrivateKeyFromFile(String path) async {
    final pem = await File(path).readAsString();
    return RSAPrivateKey(pem);
  }

  /// Same as [loadPrivateKeyFromFile] but from an already-read PEM string.
  static RSAPrivateKey loadPrivateKeyFromPem(String pem) {
    return RSAPrivateKey(pem);
  }

  /// Port of sign_jar_request(): builds and RS256-signs the Request
  /// Object (JAR) for the authorize URL's `request` parameter.
  static String signJarRequest({
    required String clientId,
    required String audience,
    required List<String> scopes,
    required String redirectUri,
    required RSAPrivateKey privateKey,
    String state = '',
  }) {
    final now = DateTime.now().toUtc();
    final jti = now.microsecondsSinceEpoch.toString();

    final jwt = JWT(
      {
        'iss': clientId, // Issuer MUST be client_id
        'aud': audience, // Audience MUST be Token Endpoint
        'sub': clientId, // Subject MUST be client_id
        'jti': jti,
        'client_id': clientId,
        'response_type': 'code',
        'scope': scopes.join(' '),
        'redirect_uri': redirectUri,
        'state': state,
        // Mirrors ronaldo.py exactly: its `nbf` is `timestamp() * 1e6`
        // (microseconds), not the usual second-precision nbf. Kept as-is
        // for parity with the reference script against the VTNet gateway.
        'nbf': now.microsecondsSinceEpoch,
      },
      header: {'kid': 'gsma-cert-kid'},
    );

    return jwt.sign(
      privateKey,
      algorithm: JWTAlgorithm.RS256,
      expiresIn: const Duration(seconds: 300),
      // ronaldo.py's claims dict has no `iat`; don't let the library add one.
      noIssueAt: true,
    );
  }

  /// Port of create_client_assertion_jwt(): builds the RS256 client
  /// assertion for private_key_jwt authentication at the token endpoint.
  ///
  /// ronaldo.py's function signature takes an `audience` parameter but its
  /// body never reads it - the `aud` claim is hardcoded to
  /// [tokenEndpointAudience] regardless of what's passed in (visible in the
  /// script as the commented-out claims dict that used to read it). This
  /// port matches that actual behavior rather than exposing a parameter
  /// that would silently do nothing.
  ///
  /// NOTE: per the existing comment on
  /// VtnetNumberVerificationService._exchangeCodeForToken, this belongs
  /// on the Application Server in production; exposed here only so the
  /// on-device flow can exercise the same TAS SDK integration test.
  static String createClientAssertionJwt({
    required String clientId,
    required RSAPrivateKey privateKey,
  }) {
    final jwt = JWT(
      {
        'iss': clientId, // Issuer MUST be client_id
        'sub': clientId, // Subject MUST be client_id
        'aud': tokenEndpointAudience, // Audience MUST be Token Endpoint URL
      },
      header: {'kid': 'gsma-cert-kid', 'typ': 'JWT'},
      jwtId: DateTime.now().toUtc().microsecondsSinceEpoch.toString(),
    );

    return jwt.sign(
      privateKey,
      algorithm: JWTAlgorithm.RS256,
      expiresIn: const Duration(seconds: 300),
    );
  }
}
