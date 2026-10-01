import Flutter
import Foundation
import TAS_SDK

/// Bridges the TAS SDK to Flutter for step 1 (authorization code) of the VTNet
/// CAMARA Number Verification flow. iOS counterpart of TasAuthBridge.kt.
///
/// Replies to Dart with the same map as Android, so TasSdkService needs no
/// platform checks: {code, state, metadata} or {error, error_description}.
///
/// Differences from the Android SDK that shape this class (from the SDK's
/// public interface and binary):
/// - initSDK takes no context and TasConfig only has `debug`.
/// - The redirect_uri is read from Info.plist `TasScheme` (its scheme part)
///   instead of a manifest meta-data. The app uses the same redirect_uri,
///   client_id, scope and endpoints as Android (VtnetNumberVerificationService).
/// - When mobile data is not available the SDK shows its own alert and fails
///   with cellularDisable.
/// - ExceptionCode has no userNotFound / networkError cases.
final class TasAuthBridge: AuthHandler {
    private let lock = NSLock()
    private var authorizeUrl = ""
    private var authorizeCode: String?
    private var codeMetaData: [String: Any] = [:]

    /// Initialises the SDK; debug logs go to the Xcode console.
    func initSDK() {
        TasSDK.shared.initSDK(config: TasConfig(debug: true), authHandler: self)
    }

    func getAuthorizeUrl() -> String {
        lock.lock()
        defer { lock.unlock() }
        return authorizeUrl
    }

    func sendAuthorizeCode(code: String, metaData: [String: Any]) async -> Bool {
        NSLog("TasAuthBridge: Authorization code received, metadata keys=\(Array(metaData.keys))")
        lock.lock()
        authorizeCode = code
        codeMetaData = metaData
        lock.unlock()
        return true
    }

    /// Runs the TAS authentication for [url] and replies to [result] exactly once
    /// with either {code, state, metadata} or {error, error_description}.
    /// Must be called on the main thread (the SDK presents a browser session).
    func authenticate(url: String, result: @escaping FlutterResult) {
        lock.lock()
        authorizeUrl = url
        authorizeCode = nil
        codeMetaData = [:]
        lock.unlock()

        var replied = false
        let reply: ([String: Any]) -> Void = { payload in
            DispatchQueue.main.async {
                guard !replied else { return }
                replied = true
                result(payload)
            }
        }

        do {
            try TasSDK.shared.authenticate(callback: AuthCallback(
                onSuccess: { [weak self] in
                    guard let self = self else { return }
                    self.lock.lock()
                    let code = self.authorizeCode
                    let metaData = self.codeMetaData
                    self.lock.unlock()
                    reply([
                        "code": code ?? NSNull(),
                        "state": metaData["state"].map { "\($0)" } ?? NSNull(),
                        "metadata": metaData.mapValues { "\($0)" },
                    ])
                },
                onError: { e in
                    NSLog("TasAuthBridge: TAS authentication failed: \(e.code) \(e.message)")
                    reply([
                        "error": TasAuthBridge.errorName(e.code),
                        "error_description": e.message,
                    ])
                }
            ))
        } catch {
            // Thrown synchronously when initSDK was not called or TasScheme is missing.
            NSLog("TasAuthBridge: TAS authenticate threw: \(error)")
            reply([
                "error": "SdkException",
                "error_description": "\(error)",
            ])
        }
    }

    /// Same error names as the Android SDK, so TasSdkService.describeError works
    /// unchanged.
    private static func errorName(_ code: ExceptionCode) -> String {
        switch code {
        case .closeBrowserWithoutResult: return "CloseBrowserWithoutResult"
        case .cannotOpenBrowser: return "CannotOpenBrowser"
        case .invalidUrl: return "InvalidUrl"
        case .cellularDisable: return "CellularDisable"
        case .consentDenied: return "ConsentDenied"
        case .sendAuthorizeCodeFailed: return "SendAuthorizeCodeFailed"
        case .unknown: return "Unknown"
        @unknown default: return "Unknown"
        }
    }
}
