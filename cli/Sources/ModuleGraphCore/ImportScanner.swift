import Foundation

public enum ImportScanner {
    static let importPattern = try! NSRegularExpression(
        pattern: #"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:public\s+|package\s+|internal\s+|private\s+|fileprivate\s+)?(?:@testable\s+)?import\s+(?:(?:struct|class|enum|protocol|typealias|func|let|var)\s+)?([A-Za-z_]\w*)"#,
        options: [.anchorsMatchLines]
    )

    /// Returns the imported module names in `source`, with their number of occurrences.
    public static func imports(in source: String) -> [String: Int] {
        var result: [String: Int] = [:]
        let range = NSRange(source.startIndex..., in: source)
        for match in importPattern.matches(in: source, range: range) {
            guard let moduleRange = Range(match.range(at: 1), in: source) else { continue }
            result[String(source[moduleRange]), default: 0] += 1
        }
        return result
    }

    public struct Scan: Sendable {
        public var sourceFiles: Int
        public var imports: [String: Int]
    }

    public static func scan(directory: URL) -> Scan {
        var files = 0
        var imports: [String: Int] = [:]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return Scan(sourceFiles: 0, imports: [:])
        }
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files += 1
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for (module, count) in self.imports(in: text) { imports[module, default: 0] += count }
        }
        return Scan(sourceFiles: files, imports: imports)
    }

    public static let systemModules: Set<String> = [
        "Foundation", "SwiftUI", "SwiftData", "UIKit", "AppKit", "Combine", "os", "OSLog", "Observation",
        "XCTest", "Testing", "CoreData", "CoreGraphics", "CoreLocation", "CoreML", "MapKit", "AVFoundation",
        "StoreKit", "WidgetKit", "WatchKit", "Charts", "PhotosUI", "Photos", "Security", "CryptoKit",
        "Network", "UserNotifications", "Dispatch", "Darwin", "Glibc", "Synchronization", "RegexBuilder",
        "Swift", "_Concurrency", "CloudKit", "HealthKit", "WebKit", "SafariServices", "AuthenticationServices",
        "LocalAuthentication", "Intents", "AppIntents", "TipKit", "GameKit", "SpriteKit", "SceneKit", "RealityKit",
        "ARKit", "Metal", "MetalKit", "Accelerate", "Vision", "NaturalLanguage", "Speech", "CoreMotion",
        "CoreBluetooth", "CoreImage", "CoreText", "CoreAudio", "AudioToolbox", "CoreMedia", "CoreVideo",
        "QuartzCore", "ImageIO", "UniformTypeIdentifiers", "Contacts", "EventKit", "MessageUI", "PassKit",
        "BackgroundTasks", "ActivityKit", "SwiftCompilerPlugin", "SwiftSyntax", "SwiftSyntaxMacros", "SwiftSyntaxBuilder",
        "PackageDescription", "System", "FoundationEssentials", "FoundationNetworking", "AdSupport", "AppTrackingTransparency",
        "Cocoa", "ObjectiveC", "SwiftUICore", "DeveloperToolsSupport", "StoreKitTest", "CoreNFC", "CoreSpotlight", "CarPlay",
    ]
}
