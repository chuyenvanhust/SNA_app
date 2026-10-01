import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// Channel for the TAS SDK demo (VTNet Number Verification step 1).
  /// Same name and method as on Android (MainActivity.kt).
  private let tasChannelName = "com.example.appv1/tas"
  private let tasBridge = TasAuthBridge()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Initialize TAS SDK (it reads the redirect scheme from TasScheme in Info.plist)
    tasBridge.initSDK()

    if let controller = window?.rootViewController as? FlutterViewController {
      FlutterMethodChannel(name: tasChannelName, binaryMessenger: controller.binaryMessenger)
        .setMethodCallHandler { [weak self] call, result in
          guard call.method == "authenticate" else {
            result(FlutterMethodNotImplemented)
            return
          }
          guard let args = call.arguments as? [String: Any],
                let authorizeUrl = args["authorizeUrl"] as? String,
                !authorizeUrl.isEmpty else {
            result(FlutterError(code: "INVALID_ARGUMENT",
                                message: "authorizeUrl is required", details: nil))
            return
          }
          self?.tasBridge.authenticate(url: authorizeUrl, result: result)
        }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
