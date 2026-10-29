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

    /// Scans the Swift files under `directory`, leaving out what belongs to no target or to another one:
    /// hidden and build folders, Xcode projects, nested packages and package manifests.
    public static func scan(directory: URL) -> Scan {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return Scan(sourceFiles: 0, imports: [:])
        }
        var files: [URL] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if ProjectLocator.ignoredDirectories.contains(name) || name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace")
                    || fm.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                    enumerator.skipDescendants()
                }
            } else if url.pathExtension == "swift", name != "Package.swift", !name.hasPrefix("Package@swift-") {
                files.append(url)
            }
        }
        return scan(files: files)
    }

    /// Scans the given Swift files; one that can't be read isn't counted.
    public static func scan(files: [URL]) -> Scan {
        var count = 0
        var imports: [String: Int] = [:]
        for url in files {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            count += 1
            for (module, occurrences) in self.imports(in: text) { imports[module, default: 0] += occurrences }
        }
        return Scan(sourceFiles: count, imports: imports)
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
