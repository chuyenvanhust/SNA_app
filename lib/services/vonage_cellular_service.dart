import 'package:flutter/services.dart';
import 'dart:convert';

/// Service to handle Vonage cellular network requests
/// This ensures requests go through the cellular network for number verification
class VonageCellularService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.appv1/vonage',
  );

  /// Make a GET request over cellular network
  ///
  /// [url] - The URL to make the request to
  /// [headers] - Optional HTTP headers
  /// [debug] - Enable debug mode for detailed logs
  ///
  /// Returns a Map containing either:
  /// - Success: { "http_status": int, "response_body": Map, "response_raw_body": String }
  /// - Error: { "error": String, "error_description": String }
  Future<Map<String, dynamic>> makeCellularGetRequest({
    required String url,
    Map<String, String>? headers,
    bool debug = false,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'makeCellularRequest',
        {'url': url, 'headers': headers ?? {}, 'debug': debug},
      );

      if (result == null) {
        return {
          'error': 'sdk_error',
          'error_description': 'No response from native code',
        };
      }

      // Convert the result to Map<String, dynamic>
      return _convertToStringKeyMap(result);
    } on PlatformException catch (e) {
      return {
        'error': e.code,
        'error_description': e.message ?? 'Unknown error occurred',
        'details': e.details?.toString() ?? '',
      };
    } catch (e) {
      return {
        'error': 'sdk_error',
        'error_description': 'Failed to make cellular request: ${e.toString()}',
      };
    }
  }

  /// Make a POST request over cellular network with form data
  ///
  /// Now supports actual POST requests using the internal Vonage API
  Future<Map<String, dynamic>> makeCellularPostRequest({
    required String url,
    Map<String, String>? headers,
    String? body,
    bool debug = false,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'makeCellularPostRequest',
        {'url': url, 'headers': headers ?? {}, 'body': body, 'debug': debug},
      );

      if (result == null) {
        return {
          'error': 'sdk_error',
          'error_description': 'No response from native code',
        };
      }

      // Convert the result to Map<String, dynamic>
      return _convertToStringKeyMap(result);
    } on PlatformException catch (e) {
      return {
        'error': e.code,
        'error_description': e.message ?? 'Unknown error occurred',
        'details': e.details?.toString() ?? '',
      };
    } catch (e) {
      return {
        'error': 'sdk_error',
        'error_description':
            'Failed to make cellular POST request: ${e.toString()}',
      };
    }
  }

  /// Convert Map with Object keys to Map with String keys
  Map<String, dynamic> _convertToStringKeyMap(Map<Object?, Object?> map) {
    final result = <String, dynamic>{};

    map.forEach((key, value) {
      final stringKey = key.toString();

      if (value is Map) {
        result[stringKey] = _convertToStringKeyMap(
          value.cast<Object?, Object?>(),
        );
      } else if (value is List) {
        result[stringKey] = _convertList(value);
      } else {
        result[stringKey] = value;
      }
    });

    return result;
  }

  /// Convert List with proper type handling
  List<dynamic> _convertList(List<Object?> list) {
    return list.map((item) {
      if (item is Map) {
        return _convertToStringKeyMap(item.cast<Object?, Object?>());
      } else if (item is List) {
        return _convertList(item.cast<Object?>());
      } else {
        return item;
      }
    }).toList();
  }

  /// Helper method to build URL with query parameters
  String buildUrlWithParams(String baseUrl, Map<String, String> params) {
    if (params.isEmpty) return baseUrl;

    final uri = Uri.parse(baseUrl);
    final newUri = uri.replace(
      queryParameters: {...uri.queryParameters, ...params},
    );

    return newUri.toString();
  }

  /// Helper method to parse response body as JSON
  Map<String, dynamic>? parseResponseBody(Map<String, dynamic> response) {
    if (response.containsKey('response_body')) {
      final body = response['response_body'];
      if (body is Map) {
        return body.cast<String, dynamic>();
      }
    }

    if (response.containsKey('response_raw_body')) {
      final rawBody = response['response_raw_body'] as String?;
      if (rawBody != null && rawBody.isNotEmpty) {
        try {
          return json.decode(rawBody) as Map<String, dynamic>;
        } catch (e) {
          print('Failed to parse raw body as JSON: $e');
        }
      }
    }

    return null;
  }

  /// Check if response is successful
  bool isSuccessResponse(Map<String, dynamic> response) {
    // Check for error field
    if (response.containsKey('error') &&
        response['error'] != null &&
        response['error'].toString().isNotEmpty) {
      return false;
    }

    // Check HTTP status
    final httpStatus = response['http_status'] as int?;
    if (httpStatus != null) {
      return httpStatus >= 200 && httpStatus < 300;
    }

    return false;
  }

  /// Get error message from response
  String getErrorMessage(Map<String, dynamic> response) {
    if (response.containsKey('error_description')) {
      return response['error_description'] as String? ?? 'Unknown error';
    }

    if (response.containsKey('error')) {
      final error = response['error'];
      switch (error) {
        case 'sdk_no_data_connectivity':
          return 'No cellular data connectivity available';
        case 'sdk_timeout':
          return 'Request timed out. Please check your mobile data and try again.';
        case 'sdk_connection_error':
          return 'Failed to establish cellular connection';
        case 'sdk_redirect_error':
          return 'Too many redirects';
        case 'sdk_error':
          return 'Internal SDK error occurred';
        default:
          return 'Error: $error';
      }
    }

    return 'Unknown error occurred';
  }
}
