import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let channelName = "com.conquerclub.app/social_share"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: channelName, binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return }
        switch call.method {
        case "shareToInstagramStory":
          guard let args = call.arguments as? [String: Any],
                let imagePath = args["imagePath"] as? String else {
            result(FlutterError(code: "BAD_ARGS", message: "imagePath is required", details: nil))
            return
          }
          result(self.shareToInstagramStory(imagePath: imagePath))
        case "shareToSnapchat":
          // Snapchat has no reliable pasteboard/URL-scheme method on iOS
          // without integrating the Snap Creative Kit SDK. Report
          // unavailable so the Dart side falls back to the generic
          // (already image-only) share sheet.
          result(false)
        case "isAppInstalled":
          guard let args = call.arguments as? [String: Any],
                let scheme = args["scheme"] as? String,
                let url = URL(string: scheme) else {
            result(false)
            return
          }
          result(UIApplication.shared.canOpenURL(url))
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Places the image on the pasteboard in the format Instagram's Stories
  // composer reads, then opens Instagram directly into that composer.
  private func shareToInstagramStory(imagePath: String) -> Bool {
    guard let urlScheme = URL(string: "instagram-stories://share"),
          UIApplication.shared.canOpenURL(urlScheme) else {
      return false
    }

    guard let imageData = FileManager.default.contents(atPath: imagePath) else {
      return false
    }

    let bundleId = Bundle.main.bundleIdentifier ?? ""
    let pasteboardItems: [String: Any] = [
      "com.instagram.sharedSticker.backgroundImage": imageData
    ]
    let pasteboardOptions: [UIPasteboard.OptionsKey: Any] = [
      .expirationDate: Date().addingTimeInterval(60 * 5)
    ]
    UIPasteboard.general.setItems([pasteboardItems], options: pasteboardOptions)

    let shareUrl = URL(string: "instagram-stories://share?source_application=\(bundleId)")!
    UIApplication.shared.open(shareUrl, options: [:], completionHandler: nil)
    return true
  }
}
