import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Folders whose security-scoped access was started; kept for the app's lifetime.
  private var accessedURLs: [URL] = []

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.setContentSize(NSSize(width: 1280, height: 820))
    self.contentMinSize = NSSize(width: 720, height: 500)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerPlatformChannel(flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  /// Sandbox helpers: security-scoped bookmarks, the real home folder and Finder reveal.
  private func registerPlatformChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "moviecat/macos", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "isSandboxed":
        result(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil)

      case "realHome":
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
          result(String(cString: dir))
        } else {
          result(NSHomeDirectory())
        }

      case "bookmark":
        guard let path = call.arguments as? String else { return result(nil) }
        do {
          let data = try URL(fileURLWithPath: path).bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil, relativeTo: nil)
          result(data.base64EncodedString())
        } catch {
          result(nil)
        }

      case "resolve":
        guard let b64 = call.arguments as? String, let data = Data(base64Encoded: b64) else {
          return result(nil)
        }
        var stale = false
        guard let url = try? URL(
          resolvingBookmarkData: data, options: [.withSecurityScope],
          relativeTo: nil, bookmarkDataIsStale: &stale)
        else { return result(nil) }
        if url.startAccessingSecurityScopedResource() {
          self?.accessedURLs.append(url)
        }
        result(["path": url.path, "stale": stale])

      case "reveal":
        guard let path = call.arguments as? String else { return result(nil) }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
