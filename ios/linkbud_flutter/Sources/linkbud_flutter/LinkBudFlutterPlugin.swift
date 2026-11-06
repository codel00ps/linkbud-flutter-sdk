import Flutter
import UIKit

public final class LinkBudFlutterPlugin: NSObject, FlutterPlugin {
    private static weak var owner: LinkBudFlutterPlugin?
    private static var sharedSDK: LinkBud?
    private static var sharedConfiguration: [String: String]?
    private let channel: FlutterMethodChannel
    private var sdk: LinkBud?
    private var initialURL: URL?
    private var started = false
    private var operating = false

    private init(channel: FlutterMethodChannel) { self.channel = channel }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "dev.linkbud/flutter", binaryMessenger: registrar.messenger())
        let instance = LinkBudFlutterPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.addApplicationDelegate(instance)
        registrar.publish(instance)
    }

    public func application(_ application: UIApplication, continue userActivity: NSUserActivity,
                            restorationHandler: @escaping ([Any]) -> Void) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL else { return false }
        guard started, let sdk else {
            if initialURL == nil { initialURL = url }
            return true
        }
        guard !operating else {
            channel.invokeMethod("onResult", arguments: ["status": "rejected", "reason": "operation_in_progress_reopen_link"])
            return true
        }
        operating = true
        Task { @MainActor in
            let value = await sdk.handle(url: url)
            operating = false
            channel.invokeMethod("onResult", arguments: encode(value))
        }
        return true
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        if Self.owner === self { Self.owner = nil }
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: String] ?? [:]
        if call.method == "initialize" {
            guard Self.owner == nil || Self.owner === self else {
                result(FlutterError(code: "engine_in_use", message: "LinkBud supports one Flutter engine", details: nil)); return
            }
            if let configuration = Self.sharedConfiguration, configuration != args {
                result(FlutterError(code: "configuration_locked", message: "Restart the app to change environment", details: nil)); return
            }
            do {
                if sdk == nil {
                    guard let origin = URL(string: args["origin"] ?? "") else { throw LinkBudError.invalidConfiguration }
                    let config = try LinkBudConfiguration(origin: origin, applicationID: args["applicationId"] ?? "",
                        environment: args["environment"] ?? "", sdkID: args["sdkId"] ?? "", appleAppID: args["appleAppId"] ?? "", routePrefix: args["routePrefix"])
                    sdk = try Self.sharedSDK ?? LinkBud(configuration: config)
                    Self.sharedSDK = sdk
                    Self.sharedConfiguration = args
                    Self.owner = self
                }
                result(nil)
            } catch { result(FlutterError(code: "invalid_configuration_or_storage", message: "Check environment identifiers, HTTPS origin and local storage", details: nil)) }
            return
        }
        guard let sdk else { result(FlutterError(code: "not_initialized", message: "Initialize LinkBud first", details: nil)); return }
        guard ["start", "handleUrl", "resume", "pending", "recover", "acknowledge", "destinationFailed"].contains(call.method) else {
            result(FlutterMethodNotImplemented); return
        }
        guard !operating else {
            result(FlutterError(code: "operation_in_progress", message: "Wait for the current operation, then retry this input", details: nil)); return
        }
        operating = true
        // Set the guard before scheduling the task, preserving channel arrival order.
        let coldURL = call.method == "start" ? initialURL : nil
        if call.method == "start" { started = true; initialURL = nil }
        Task { @MainActor in
            defer { operating = false }
            switch call.method {
            case "start":
                let value: LinkBudResult
                if let coldURL { value = await sdk.handle(url: coldURL) }
                else { value = await sdk.resume() }
                result(encode(value))
            case "handleUrl":
                guard let raw = args["url"], let url = URL(string: raw) else {
                    result(encode(.rejected(reason: "invalid_link"))); return
                }
                result(encode(await sdk.handle(url: url)))
            case "resume": result(encode(await sdk.resume()))
            case "pending": result(encode(await sdk.pending()))
            case "recover": result(encode(await sdk.recover(code: args["code"] ?? "")))
            case "acknowledge": result(await sdk.acknowledge(id: args["id"] ?? ""))
            case "destinationFailed": result(await sdk.destinationFailed(id: args["id"] ?? "", reason: args["reason"] ?? ""))
            default: result(FlutterMethodNotImplemented)
            }
        }
    }

    private func encode(_ result: LinkBudResult) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        switch result {
        case .pending(let value):
            return ["status": "pending", "id": value.id, "destination": value.destination, "expiresAt": formatter.string(from: value.expiresAt)]
        case .empty: return ["status": "empty"]
        case .alreadyAcknowledged: return ["status": "alreadyAcknowledged"]
        case .retryable(let date): return ["status": "retryable", "retryAt": formatter.string(from: date)]
        case .rejected(let reason): return ["status": "rejected", "reason": reason]
        }
    }
}
