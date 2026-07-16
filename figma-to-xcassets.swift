#!/usr/bin/env swift

import Foundation

// MARK: - Errors

enum GeneratorError: LocalizedError {
    case invalidArguments
    case invalidJSON(URL)
    case invalidRoot(URL)
    case invalidColor(token: String)
    case missingReference(String)
    case circularReference(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return """
            Usage:

              Single mode:
                swift figma-to-xcassets.swift \
                  --input colors.json \
                  --output DesignColors.xcassets

              Light and dark modes:
                swift figma-to-xcassets.swift \
                  --light light.json \
                  --dark dark.json \
                  --output DesignColors.xcassets

              Optional:
                --namespace Colors
                --preserve-groups
            """

        case let .invalidJSON(url):
            return "Could not parse JSON file: \(url.path)"

        case let .invalidRoot(url):
            return "The JSON root must be an object: \(url.path)"

        case let .invalidColor(token):
            return "Invalid color value for token: \(token)"

        case let .missingReference(reference):
            return "Could not resolve token reference: {\(reference)}"

        case let .circularReference(reference):
            return "Circular token alias detected: {\(reference)}"
        }
    }
}

// MARK: - Arguments

struct Arguments {
    let lightURL: URL
    let darkURL: URL?
    let outputURL: URL
    let namespace: String?
    let preserveGroups: Bool

    static func parse() throws -> Arguments {
        let values = Array(CommandLine.arguments.dropFirst())

        func value(after flag: String) -> String? {
            guard let index = values.firstIndex(of: flag),
                  values.indices.contains(index + 1) else {
                return nil
            }

            return values[index + 1]
        }

        let inputPath = value(after: "--input")
        let lightPath = value(after: "--light") ?? inputPath
        let darkPath = value(after: "--dark")
        let outputPath = value(after: "--output")
        let namespace = value(after: "--namespace")

        guard let lightPath, let outputPath else {
            throw GeneratorError.invalidArguments
        }

        return Arguments(
            lightURL: URL(fileURLWithPath: lightPath),
            darkURL: darkPath.map(URL.init(fileURLWithPath:)),
            outputURL: URL(fileURLWithPath: outputPath),
            namespace: namespace,
            preserveGroups: values.contains("--preserve-groups")
        )
    }
}

// MARK: - JSON loading

func loadJSONObject(from url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)

    guard let json = try? JSONSerialization.jsonObject(with: data) else {
        throw GeneratorError.invalidJSON(url)
    }

    guard let dictionary = json as? [String: Any] else {
        throw GeneratorError.invalidRoot(url)
    }

    return dictionary
}

// MARK: - Models

struct RGBA {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
}

struct Token {
    let path: [String]
    let value: Any

    var referencePath: String {
        path.joined(separator: ".")
    }
}

struct GeneratedColor {
    let path: [String]
    let light: RGBA
    let dark: RGBA?
}

// MARK: - Token parser

final class FigmaTokenParser {

    private let root: [String: Any]
    private var tokensByPath: [String: Token] = [:]

    init(root: [String: Any]) {
        self.root = root
        collectTokens(in: root, path: [])
    }

    func colorTokens() -> [Token] {
        tokensByPath.values
            .filter { token in
                isColorToken(at: token.path)
            }
            .sorted {
                $0.referencePath.localizedStandardCompare(
                    $1.referencePath
                ) == .orderedAscending
            }
    }

    func resolveColor(
        for token: Token,
        visited: Set<String> = []
    ) throws -> RGBA {
        try resolveColorValue(
            token.value,
            tokenPath: token.referencePath,
            visited: visited
        )
    }

    func token(at path: [String]) -> Token? {
        tokensByPath[path.joined(separator: ".")]
    }

    // MARK: Discovery

    private func collectTokens(
        in dictionary: [String: Any],
        path: [String]
    ) {
        for (key, value) in dictionary {
            guard !key.hasPrefix("$") else {
                continue
            }

            let currentPath = path + [key]

            if let object = value as? [String: Any],
               let tokenValue = object["$value"] {
                tokensByPath[currentPath.joined(separator: ".")] = Token(
                    path: currentPath,
                    value: tokenValue
                )

                continue
            }

            if let nested = value as? [String: Any] {
                collectTokens(in: nested, path: currentPath)
            }
        }
    }

    private func isColorToken(at path: [String]) -> Bool {
        guard let object = objectAtPath(path, in: root) as? [String: Any] else {
            return false
        }

        if let type = object["$type"] as? String {
            return type.lowercased() == "color"
        }

        /*
         DTCG allows $type to be declared on a parent group.
         Walk upward until a $type declaration is found.
         */
        for endIndex in stride(
            from: path.count - 1,
            through: 0,
            by: -1
        ) {
            let parentPath = Array(path.prefix(endIndex))

            guard let parent = objectAtPath(
                parentPath,
                in: root
            ) as? [String: Any] else {
                continue
            }

            if let type = parent["$type"] as? String {
                return type.lowercased() == "color"
            }
        }

        return looksLikeColorValue(object["$value"])
    }

    private func looksLikeColorValue(_ value: Any?) -> Bool {
        if let string = value as? String {
            return string.hasPrefix("#") ||
                (string.hasPrefix("{") && string.hasSuffix("}"))
        }

        guard let object = value as? [String: Any] else {
            return false
        }

        return object["components"] != nil ||
            object["hex"] != nil ||
            object["r"] != nil
    }

    // MARK: Resolution

    private func resolveColorValue(
        _ value: Any,
        tokenPath: String,
        visited: Set<String>
    ) throws -> RGBA {
        if let string = value as? String {
            if let reference = aliasPath(from: string) {
                guard !visited.contains(reference) else {
                    throw GeneratorError.circularReference(reference)
                }

                guard let referencedToken = tokensByPath[reference] else {
                    throw GeneratorError.missingReference(reference)
                }

                var updatedVisited = visited
                updatedVisited.insert(reference)

                return try resolveColorValue(
                    referencedToken.value,
                    tokenPath: referencedToken.referencePath,
                    visited: updatedVisited
                )
            }

            if let color = parseHex(string) {
                return color
            }

            throw GeneratorError.invalidColor(token: tokenPath)
        }

        guard let dictionary = value as? [String: Any] else {
            throw GeneratorError.invalidColor(token: tokenPath)
        }

        // Figma DTCG export:
        //
        // {
        //   "colorSpace": "srgb",
        //   "components": [1, 0.5, 0],
        //   "alpha": 1,
        //   "hex": "#FF8000"
        // }

        if let components = dictionary["components"] as? [Any],
           components.count >= 3 {
            let red = number(components[0])
            let green = number(components[1])
            let blue = number(components[2])
            let alpha = number(dictionary["alpha"]) ?? 1

            if let red, let green, let blue {
                return RGBA(
                    red: clamp(red),
                    green: clamp(green),
                    blue: clamp(blue),
                    alpha: clamp(alpha)
                )
            }
        }

        // Prefer hex when components aren't available.

        if let hex = dictionary["hex"] as? String,
           let color = parseHex(hex) {
            let alpha = number(dictionary["alpha"]) ?? color.alpha

            return RGBA(
                red: color.red,
                green: color.green,
                blue: color.blue,
                alpha: clamp(alpha)
            )
        }

        // Figma REST/Plugin API color representation:
        //
        // {
        //   "r": 1,
        //   "g": 0.5,
        //   "b": 0,
        //   "a": 1
        // }

        if let red = number(dictionary["r"]),
           let green = number(dictionary["g"]),
           let blue = number(dictionary["b"]) {
            return RGBA(
                red: clamp(red),
                green: clamp(green),
                blue: clamp(blue),
                alpha: clamp(number(dictionary["a"]) ?? 1)
            )
        }

        throw GeneratorError.invalidColor(token: tokenPath)
    }

    private func aliasPath(from string: String) -> String? {
        guard string.hasPrefix("{"),
              string.hasSuffix("}") else {
            return nil
        }

        return String(string.dropFirst().dropLast())
            .replacingOccurrences(of: "/", with: ".")
    }

    private func objectAtPath(
        _ path: [String],
        in root: [String: Any]
    ) -> Any? {
        if path.isEmpty {
            return root
        }

        var current: Any = root

        for component in path {
            guard let dictionary = current as? [String: Any],
                  let next = dictionary[component] else {
                return nil
            }

            current = next
        }

        return current
    }
}

// MARK: - Generator

final class XCAssetGenerator {

    private let arguments: Arguments
    private let lightParser: FigmaTokenParser
    private let darkParser: FigmaTokenParser?
    private let fileManager = FileManager.default

    init(
        arguments: Arguments,
        lightJSON: [String: Any],
        darkJSON: [String: Any]?
    ) {
        self.arguments = arguments
        self.lightParser = FigmaTokenParser(root: lightJSON)
        self.darkParser = darkJSON.map(FigmaTokenParser.init(root:))
    }

    func generate() throws {
        let colors = try makeColors()

        try recreateOutputDirectory()
        try writeCatalogContents()

        var namespaces = Set<String>()

        for color in colors {
            let outputPath = outputComponents(for: color.path)

            if arguments.preserveGroups, outputPath.count > 1 {
                var accumulatedPath = arguments.outputURL

                for group in outputPath.dropLast() {
                    accumulatedPath.appendPathComponent(group)
                    namespaces.insert(accumulatedPath.path)
                }
            }

            try writeColorSet(
                color,
                outputComponents: outputPath
            )
        }

        for namespacePath in namespaces.sorted() {
            try writeNamespaceContents(
                at: URL(fileURLWithPath: namespacePath)
            )
        }

        print("Generated \(colors.count) colors")
        print(arguments.outputURL.path)
    }

    private func makeColors() throws -> [GeneratedColor] {
        try lightParser.colorTokens().map { lightToken in
            let light = try lightParser.resolveColor(for: lightToken)

            let dark: RGBA?

            if let darkParser,
               let darkToken = darkParser.token(at: lightToken.path) {
                dark = try darkParser.resolveColor(for: darkToken)
            } else {
                dark = nil
            }

            return GeneratedColor(
                path: lightToken.path,
                light: light,
                dark: dark
            )
        }
    }

    private func outputComponents(for path: [String]) -> [String] {
        var result = path

        if let namespace = arguments.namespace {
            result.insert(namespace, at: 0)
        }

        if arguments.preserveGroups {
            return result.map(sanitizeAssetName)
        }

        return [
            sanitizeAssetName(
                result.joined(separator: "-")
            )
        ]
    }

    private func recreateOutputDirectory() throws {
        if fileManager.fileExists(atPath: arguments.outputURL.path) {
            try fileManager.removeItem(at: arguments.outputURL)
        }

        try fileManager.createDirectory(
            at: arguments.outputURL,
            withIntermediateDirectories: true
        )
    }

    private func writeCatalogContents() throws {
        let json: [String: Any] = [
            "info": [
                "author": "figma-to-xcassets",
                "version": 1
            ]
        ]

        try writeJSON(
            json,
            to: arguments.outputURL.appendingPathComponent("Contents.json")
        )
    }

    private func writeNamespaceContents(at url: URL) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )

        let json: [String: Any] = [
            "info": [
                "author": "figma-to-xcassets",
                "version": 1
            ],
            "properties": [
                "provides-namespace": true
            ]
        ]

        try writeJSON(
            json,
            to: url.appendingPathComponent("Contents.json")
        )
    }

    private func writeColorSet(
        _ color: GeneratedColor,
        outputComponents: [String]
    ) throws {
        var directory = arguments.outputURL

        for component in outputComponents.dropLast() {
            directory.appendPathComponent(component)

            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        guard let colorName = outputComponents.last else {
            return
        }

        let colorSetURL = directory.appendingPathComponent(
            "\(colorName).colorset"
        )

        try fileManager.createDirectory(
            at: colorSetURL,
            withIntermediateDirectories: true
        )

        var entries: [[String: Any]] = [
            colorEntry(color.light, appearance: nil)
        ]

        if let dark = color.dark {
            entries.append(
                colorEntry(dark, appearance: "dark")
            )
        }

        let json: [String: Any] = [
            "colors": entries,
            "info": [
                "author": "figma-to-xcassets",
                "version": 1
            ]
        ]

        try writeJSON(
            json,
            to: colorSetURL.appendingPathComponent("Contents.json")
        )
    }

    private func colorEntry(
        _ color: RGBA,
        appearance: String?
    ) -> [String: Any] {
        var entry: [String: Any] = [
            "idiom": "universal",
            "color": [
                "color-space": "srgb",
                "components": [
                    "red": componentString(color.red),
                    "green": componentString(color.green),
                    "blue": componentString(color.blue),
                    "alpha": componentString(color.alpha)
                ]
            ]
        ]

        if let appearance {
            entry["appearances"] = [
                [
                    "appearance": "luminosity",
                    "value": appearance
                ]
            ]
        }

        return entry
    }

    private func writeJSON(
        _ object: [String: Any],
        to url: URL
    ) throws {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )

        try data.write(to: url, options: .atomic)
    }
}

// MARK: - Utilities

func number(_ value: Any?) -> Double? {
    switch value {
    case let number as NSNumber:
        return number.doubleValue

    case let string as String:
        return Double(string)

    default:
        return nil
    }
}

func clamp(_ value: Double) -> Double {
    min(max(value, 0), 1)
}

func parseHex(_ value: String) -> RGBA? {
    var hex = value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .uppercased()

    if hex.hasPrefix("#") {
        hex.removeFirst()
    }

    switch hex.count {
    case 3:
        hex = hex.map { "\($0)\($0)" }.joined() + "FF"

    case 4:
        hex = hex.map { "\($0)\($0)" }.joined()

    case 6:
        hex += "FF"

    case 8:
        break

    default:
        return nil
    }

    guard let raw = UInt64(hex, radix: 16) else {
        return nil
    }

    return RGBA(
        red: Double((raw >> 24) & 0xFF) / 255,
        green: Double((raw >> 16) & 0xFF) / 255,
        blue: Double((raw >> 8) & 0xFF) / 255,
        alpha: Double(raw & 0xFF) / 255
    )
}

func componentString(_ value: Double) -> String {
    String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
}

func sanitizeAssetName(_ name: String) -> String {
    let permitted = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "-_"))

    let sanitized = name.unicodeScalars.map { scalar -> Character in
        permitted.contains(scalar) ? Character(String(scalar)) : "-"
    }

    return String(sanitized)
        .replacingOccurrences(
            of: "-+",
            with: "-",
            options: .regularExpression
        )
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

// MARK: - Run

do {
    let arguments = try Arguments.parse()
    let lightJSON = try loadJSONObject(from: arguments.lightURL)
    let darkJSON = try arguments.darkURL.map(loadJSONObject(from:))

    let generator = XCAssetGenerator(
        arguments: arguments,
        lightJSON: lightJSON,
        darkJSON: darkJSON
    )

    try generator.generate()
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
}