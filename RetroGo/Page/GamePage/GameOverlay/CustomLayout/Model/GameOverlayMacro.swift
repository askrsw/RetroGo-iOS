// Copyright © 2026 haharsw. Part of RetroGo, GPL-3.0-or-later.
import Foundation

/// Device-independent macro definition, stored separately from layout geometry.
struct GameOverlayMacro: Codable, Equatable {
    static let defaultSymbol = "play.rectangle"
    static let maxFrames = 600
    static let maxSteps = 128
    var version = 1
    /// Empty only in a new draft; the layout assigns a short local ID on insertion.
    var id: String = ""

    static func makeId(reservedIds: Set<String>) -> String {
        var number = 1
        while reservedIds.contains("macro-\(number)") { number += 1 }
        return "macro-\(number)"
    }
    var name: String
    var steps: [Step]
    // Optional fields keep existing version-1 definitions readable.
    var symbol: String?
    var direction: Direction?

    enum Direction: String, Codable, CaseIterable {
        case left, right
        var marker: String { self == .left ? "←" : "→" }
        var symbol: String { self == .left ? "arrow.left" : "arrow.right" }
        var mirrored: Self { self == .left ? .right : .left }
    }
    var resolvedSymbol: String {
        guard let symbol else { return Self.defaultSymbol }
        if GameOverlayMacroSymbols.names.contains(symbol) { return symbol }
        // Existing filled choices render using the curated outline variant.
        let outline = symbol.hasSuffix(".fill") ? String(symbol.dropLast(5)) : symbol
        return GameOverlayMacroSymbols.names.contains(outline) ? outline : Self.defaultSymbol
    }

    struct Step: Codable, Equatable {
        var binds: [String]
        var frames: Int
    }

    static let allowedBinds = ["UP", "DOWN", "LEFT", "RIGHT", "B", "Y", "SELECT", "START", "A", "X", "L1", "R1", "L2", "R2", "L3", "R3"]
    var totalFrames: Int { steps.reduce(0) { $0 + $1.frames } }
    /// A copy becomes a new draft; its destination assigns a local identity on save.
    func copyForLayout() -> Self {
        var copy = self
        copy.id = ""
        return copy
    }
    /// Creates an independent definition; only horizontal directions change.
    func mirroredCopy(name: String) -> Self {
        var copy = Self(name: name, steps: steps.map { step in
            Step(binds: step.binds.map { bind in
                switch bind {
                case "LEFT": return "RIGHT"
                case "RIGHT": return "LEFT"
                default: return bind
                }
            }, frames: step.frames)
        })
        copy.symbol = symbol
        copy.direction = direction?.mirrored
        return copy
    }
    var isValid: Bool {
        version == 1 && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !steps.isEmpty && steps.count <= Self.maxSteps
        && steps.allSatisfy { (1...Self.maxFrames).contains($0.frames) && Set($0.binds).count == $0.binds.count
            && $0.binds.allSatisfy(Self.allowedBinds.contains)
            && !(Set($0.binds).isSuperset(of: ["UP", "DOWN"]) || Set($0.binds).isSuperset(of: ["LEFT", "RIGHT"])) }
        && totalFrames <= Self.maxFrames && steps.contains { !$0.binds.isEmpty }
    }
}

/// A curated allowlist, excluding product/brand symbols and unrelated UI icons.
enum GameOverlayMacroSymbols {
    struct Category {
        let key: String
        let symbols: [String]
    }
    static let categories: [Category] = [
        .init(key: "actions", symbols: ["play.rectangle", "play", "forward", "backward", "repeat", "arrow.triangle.2.circlepath", "shuffle", "bolt", "sparkles", "flag"]),
        .init(key: "combat", symbols: ["target", "scope", "shield", "burst", "flame", "bomb", "fireworks"]),
        .init(key: "shapes", symbols: ["circle", "square", "triangle", "diamond", "hexagon", "pentagon", "octagon", "seal", "star", "staroflife", "capsule", "oval", "cube", "pyramid", "cone", "cylinder"]),
        .init(key: "nature", symbols: ["leaf", "tree", "mountain.2", "globe.americas", "globe.asia.australia", "pawprint", "hare", "tortoise", "bird", "fish", "ant", "ladybug", "spider", "lizard", "dog", "cat", "butterfly", "fossil.shell"]),
        .init(key: "health", symbols: ["heart", "heart.text.square", "cross", "bandage", "lungs", "brain", "waveform.path.ecg", "pills", "stethoscope", "medical.thermometer"]),
        .init(key: "fitness", symbols: ["figure.run", "figure.walk", "figure.boxing", "figure.martial.arts", "figure.jumprope", "figure.strengthtraining.traditional", "figure.strengthtraining.functional", "figure.climbing", "figure.gymnastics", "figure.dance", "figure.fencing", "figure.archery", "figure.basketball", "figure.tennis", "figure.soccer", "figure.surfing", "figure.skating", "figure.skiing.downhill", "figure.snowboarding", "figure.wrestling", "dumbbell", "sportscourt", "basketball", "baseball", "soccerball", "tennisball", "volleyball"]),
        .init(key: "human", symbols: ["person", "person.2", "figure.stand", "figure.stand.line.dotted.figure.stand", "hand.raised", "hand.point.up.left", "hand.point.up", "hand.point.down", "hand.point.left", "hand.point.right", "hands.clap", "hands.sparkles", "eye", "ear", "mouth", "face.smiling", "hand.thumbsup", "hand.thumbsdown"]),
        .init(key: "transportation", symbols: ["car", "car.side", "bus", "tram", "tram.side", "train.side.front.car", "airplane", "helicopter", "ferry", "sailboat", "bicycle", "scooter", "motorcycle", "truck.box", "truck.pickup.side", "fuelpump", "steeringwheel", "wheelchair"]),
        .init(key: "weather", symbols: ["sun.max", "sun.min", "sunrise", "sunset", "sun.haze", "moon", "moon.stars", "cloud", "cloud.sun", "cloud.moon", "cloud.rain", "cloud.heavyrain", "cloud.drizzle", "cloud.snow", "cloud.hail", "cloud.bolt", "cloud.bolt.rain", "snowflake", "wind", "tornado", "hurricane", "drop", "water.waves", "thermometer.sun"])
    ]
    static let names = Set(categories.flatMap(\.symbols))
}
