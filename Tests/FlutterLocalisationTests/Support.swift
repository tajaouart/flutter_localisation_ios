import Foundation
import XCTest
@testable import FlutterLocalisation

enum Fixture {
    static func url(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: "xcstrings", subdirectory: "Fixtures")!
    }

    static func catalog(_ name: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: url(name))) as! [String: Any]
    }
}

func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// What Xcode builds from a catalog: `xcstringstool compile`, the tool the
/// build system itself runs, laid out as an app bundle.
func xcodeBuiltBundle(_ fixture: String, developmentRegion: String = "en", only locales: [String]? = nil) throws -> Bundle {
    let output = temporaryDirectory()
    let tool = Process()
    tool.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    tool.arguments = ["xcstringstool", "compile", Fixture.url(fixture).path, "-o", output.path]
        + (locales ?? []).flatMap { ["-l", $0] }
    try tool.run()
    tool.waitUntilExit()
    XCTAssertEqual(tool.terminationStatus, 0, "xcstringstool failed")
    let fileManager = FileManager.default
    for lproj in try fileManager.contentsOfDirectory(atPath: output.path) where lproj.hasSuffix(".lproj") {
        for ext in ["strings", "stringsdict"] {
            let from = output.appendingPathComponent(lproj).appendingPathComponent("\(fixture).\(ext)")
            if fileManager.fileExists(atPath: from.path) {
                try fileManager.moveItem(at: from, to: output.appendingPathComponent(lproj).appendingPathComponent("Localizable.\(ext)"))
            }
        }
    }
    let info: [String: Any] = ["CFBundleIdentifier": "test.\(UUID().uuidString)", "CFBundleDevelopmentRegion": developmentRegion]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: output.appendingPathComponent("Info.plist"))
    return Bundle(url: output)!
}

/// A bundle holding one locale of an Xcode-built bundle, the way the store
/// holds one locale of a live update.
func singleLocaleBundle(from bundle: Bundle, locale: String) throws -> Bundle {
    let root = temporaryDirectory()
    try FileManager.default.copyItem(
        at: bundle.bundleURL.appendingPathComponent("\(locale).lproj"),
        to: root.appendingPathComponent("\(locale).lproj")
    )
    let info: [String: Any] = ["CFBundleIdentifier": "test.\(UUID().uuidString)", "CFBundleDevelopmentRegion": locale]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: root.appendingPathComponent("Info.plist"))
    return Bundle(url: root)!
}

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, [String: Any]))?
    nonisolated(unsafe) static var requests: [[String: Any]] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            body = data
        }
        var recorded = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        recorded["authorization"] = request.value(forHTTPHeaderField: "Authorization")
        MockURLProtocol.requests.append(recorded)
        let (status, json) = MockURLProtocol.handler?(request) ?? (500, [:])
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: json))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}
