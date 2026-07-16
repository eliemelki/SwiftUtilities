   #!/usr/bin/env swift

import Foundation

// MARK: - Configuration

struct Arguments {
    let inputURL: URL
    let outputURL: URL
    let rootTypeName: String
    let bundleExpression: String

    static func parse() throws -> Arguments {
        let arguments = Array(CommandLine.arguments.dropFirst())

        func value(after option: String) -> String? {
            guard let index = arguments.firstIndex(of: option),
                  arguments.indices.contains(index + 1) else {
                return nil
            }

            return arguments[index + 1]
        }

        guard let input = value(after: "--input"),
              let output = value(after: "--output") else {
            throw ScriptError.invalidArguments
        }

        return Arguments(
            inputURL: URL(fileURLWithPath: input),
            outputURL: URL(fileURLWithPath: output),
            rootTypeName: value(after: "--type-name") ?? "DesignColors",
            bundleExpression: value(after: "--bundle") ?? ".main"
        )
    }
}

// MARK: - Errors

enum ScriptError: LocalizedError {
    case invalidArguments
    case inputDoesNotExist(String)
    case noColorAssetsFound

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return """
            Usage:

              swift generate-color-code.swift \
                --input MyApp/Resources/DesignColors.xcassets \
                --output MyApp/Generated/DesignColors.swift

            Optional:

              --type-name DesignColors
              --bundle .main

            Swift Package example:

              --bundle Bundle.module
            """

        case let .inputDoesNotExist(path):
            return "The asset catalog does not exist at: \(path)"

        case .noColorAssetsFound:
            return "No .colorset directories were found."
        }
    }
}

// MARK: - Asset model

struct ColorAsset {
    let assetName: String
    let pathComponents: [String]
}

final class AssetNode {
    var children: [String: AssetNode] = [:]
    var colors: [ColorAsset] = []
}

// MARK: - Scanner

final class AssetCatalogScanner {

    private let fileManager = FileManager.default

    func scan(at catalogURL: URL) throws -> [ColorAsset] {
        guard fileManager.fileExists(atPath: catalogURL.path) else {
            throw ScriptError.inputDoesNotExist(catalogURL.path)
        }

        guard let enumerator = fileManager.enumerator(
            at: catalogURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ScriptError.noColorAssetsFound
        }

        var colors: [ColorAsset] = []

        for case let url as URL in enumerator {
            guard url.pathExtension == "colorset" else {
                continue
            }

            enumerator.skipDescendants()

            let relativePath = url.path
                .replacingOccurrences(
                    of: catalogURL.path + "/",
                    with: ""
                )

            var components = relativePath
                .split(separator: "/")
                .map(String.init)

            guard let colorSetName = components.popLast() else {
                continue
            }

            let assetName = colorSetName
                .replacingOccurrences(of: ".colorset", with: "")

            /*
             Xcode named colors use the complete namespace path only when
             intermediate asset folders have "provides-namespace": true.

             The original generator adds that property when preserving groups,
             so build the runtime name using slash-separated components.
             */
            let runtimeAssetName = (components + [assetName])
                .joined(separator: "/")

            colors.append(
                ColorAsset(
                    assetName: runtimeAssetName,
                    pathComponents: components + [assetName]
                )
            )
        }

        guard !colors.isEmpty else {
            throw ScriptError.noColorAssetsFound
        }

        return colors.sorted {
            $0.assetName.localizedStandardCompare($1.assetName) == .orderedAscending
        }
    }
}

// MARK: - Tree building

func buildTree(from colors: [ColorAsset]) -> AssetNode {
    let root = AssetNode()

    for color in colors {
        var currentNode = root

        for group in color.pathComponents.dropLast() {
            if currentNode.children[group] == nil {
                currentNode.children[group] = AssetNode()
            }

            currentNode = currentNode.children[group]!
        }

        currentNode.colors.append(color)
    }

    return root
}

// MARK: - Swift generation

final class SwiftCodeGenerator {

    private let rootTypeName: String
    private let bundleExpression: String

    init(
        rootTypeName: String,
        bundleExpression: String
    ) {
        self.rootTypeName = swiftTypeName(rootTypeName)
        self.bundleExpression = bundleExpression
    }

    func generate(from root: AssetNode) -> String {
        var lines: [String] = []

        lines.append("// swiftlint:disable all")
        lines.append("// Generated file. Do not edit manually.")
        lines.append("")
        lines.append("import UIKit")
        lines.append("import SwiftUI")
        lines.append("")
        lines.append("public enum \(rootTypeName) {")

        appendNodeContents(
            root,
            indentation: 1,
            into: &lines
        )

        lines.append("}")
        lines.append("")
        lines.append("public struct DesignColor: Sendable {")
        lines.append("    public let name: String")
        lines.append("")
        lines.append("    public init(name: String) {")
        lines.append("        self.name = name")
        lines.append("    }")
        lines.append("")
        lines.append("    @MainActor")
        lines.append("    public var uiColor: UIColor {")
        lines.append(
            "        guard let color = UIColor(named: name, in: \(bundleExpression), compatibleWith: nil) else {"
        )
        lines.append(
            #"            assertionFailure("Missing color asset: \(name)")"#
        )
        lines.append("            return .clear")
        lines.append("        }")
        lines.append("")
        lines.append("        return color")
        lines.append("    }")
        lines.append("")
        lines.append("    @MainActor")
        lines.append("    public var swiftUIColor: Color {")
        lines.append("        Color(name, bundle: \(bundleExpression))")
        lines.append("    }")
        lines.append("}")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    private func appendNodeContents(
        _ node: AssetNode,
        indentation: Int,
        into lines: inout [String]
    ) {
        let indent = String(repeating: "    ", count: indentation)

        for color in node.colors.sorted(by: {
            $0.assetName.localizedStandardCompare($1.assetName) == .orderedAscending
        }) {
            guard let rawName = color.pathComponents.last else {
                continue
            }

            let propertyName = swiftPropertyName(rawName)

            lines.append(
                "\(indent)public static let \(propertyName) = DesignColor(name: \(swiftStringLiteral(color.assetName)))"
            )
        }

        if !node.colors.isEmpty && !node.children.isEmpty {
            lines.append("")
        }

        let sortedChildren = node.children.sorted {
            $0.key.localizedStandardCompare($1.key) == .orderedAscending
        }

        for (index, child) in sortedChildren.enumerated() {
            let enumName = swiftTypeName(child.key)

            lines.append("\(indent)public enum \(enumName) {")

            appendNodeContents(
                child.value,
                indentation: indentation + 1,
                into: &lines
            )

            lines.append("\(indent)}")

            if index < sortedChildren.count - 1 {
                lines.append("")
            }
        }
    }
}

// MARK: - Swift identifier conversion

private let swiftKeywords: Set<String> = [
    "associatedtype",
    "class",
    "deinit",
    "enum",
    "extension",
    "fileprivate",
    "func",
    "import",
    "init",
    "inout",
    "internal",
    "let",
    "open",
    "operator",
    "private",
    "precedencegroup",
    "protocol",
    "public",
    "rethrows",
    "static",
    "struct",
    "subscript",
    "typealias",
    "var",
    "break",
    "case",
    "catch",
    "continue",
    "default",
    "defer",
    "do",
    "else",
    "fallthrough",
    "for",
    "guard",
    "if",
    "in",
    "repeat",
    "return",
    "throw",
    "switch",
    "where",
    "while",
    "as",
    "Any",
    "false",
    "is",
    "nil",
    "self",
    "Self",
    "super",
    "throws",
    "true",
    "try"
]

func words(from value: String) -> [String] {
    let separated = value
        .replacingOccurrences(
            of: #"([a-z0-9])([A-Z])"#,
            with: "$1 $2",
            options: .regularExpression
        )
        .replacingOccurrences(
            of: #"[^A-Za-z0-9]+"#,
            with: " ",
            options: .regularExpression
        )

    return separated
        .split(separator: " ")
        .map(String.init)
}

func swiftTypeName(_ value: String) -> String {
    let parts = words(from: value)

    var result = parts
        .map { part in
            guard let first = part.first else {
                return ""
            }

            return String(first).uppercased() + part.dropFirst()
        }
        .joined()

    if result.isEmpty {
        result = "Unnamed"
    }

    if result.first?.isNumber == true {
        result = "Value\(result)"
    }

    if swiftKeywords.contains(result) {
        result += "Value"
    }

    return result
}

func swiftPropertyName(_ value: String) -> String {
    let typeName = swiftTypeName(value)

    guard let first = typeName.first else {
        return "unnamed"
    }

    var result = String(first).lowercased() + typeName.dropFirst()

    if result.first?.isNumber == true {
        result = "value\(result)"
    }

    if swiftKeywords.contains(result) {
        return "`\(result)`"
    }

    return result
}

func swiftStringLiteral(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: #"\"#, with: #"\\"#)
        .replacingOccurrences(of: #"""#, with: #"\""#)
        .replacingOccurrences(of: "\n", with: #"\\n"#)

    return "\"\(escaped)\""
}

// MARK: - File output

func writeGeneratedCode(
    _ code: String,
    to outputURL: URL
) throws {
    let directoryURL = outputURL.deletingLastPathComponent()

    try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true
    )

    try code.write(
        to: outputURL,
        atomically: true,
        encoding: .utf8
    )
}

// MARK: - Run

do {
    let arguments = try Arguments.parse()

    let scanner = AssetCatalogScanner()
    let colors = try scanner.scan(at: arguments.inputURL)
    let tree = buildTree(from: colors)

    let generator = SwiftCodeGenerator(
        rootTypeName: arguments.rootTypeName,
        bundleExpression: arguments.bundleExpression
    )

    let code = generator.generate(from: tree)

    try writeGeneratedCode(
        code,
        to: arguments.outputURL
    )

    print("Generated \(colors.count) color references:")
    print(arguments.outputURL.path)
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
}