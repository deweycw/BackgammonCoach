import Foundation

// MARK: - Player

enum Player: Int, Codable, CaseIterable, Hashable {
    case white = 1
    case black = -1

    var opponent: Player { self == .white ? .black : .white }

    var homeBoard: ClosedRange<Int> {
        self == .white ? 1...6 : 19...24
    }

    var direction: Int { self == .white ? -1 : 1 }
    var barIndex: Int { self == .white ? 0 : 1 }
    var displayName: String { self == .white ? "White" : "Black" }
    var barEntryStart: Int { self == .white ? 25 : 0 }
}

// MARK: - Cube State

struct CubeState: Codable, Equatable, Hashable {
    var value: Int = 1
    var owner: Player? = nil

    func canDouble(_ player: Player) -> Bool {
        value < 64 && (owner == nil || owner == player)
    }
}

// MARK: - Dice

struct Dice: Codable, Equatable, Hashable {
    let die1: Int
    let die2: Int

    var isDoubles: Bool { die1 == die2 }
    var movesAvailable: [Int] { isDoubles ? [die1, die1, die1, die1] : [die1, die2] }

    static func roll() -> Dice {
        Dice(die1: Int.random(in: 1...6), die2: Int.random(in: 1...6))
    }
}

// MARK: - Checker Move

struct CheckerMove: Codable, Equatable, Hashable, CustomStringConvertible {
    let from: Int
    let to: Int
    let dieUsed: Int
    let isHit: Bool
    let isBearOff: Bool

    var description: String {
        let fromStr = (from == 0 || from == 25) ? "bar" : "\(from)"
        let toStr = isBearOff ? "off" : "\(to)"
        return "\(fromStr)/\(toStr)\(isHit ? "*" : "")"
    }
}

// MARK: - Play

struct Play: Codable, Equatable, Hashable {
    let moves: [CheckerMove]

    var notation: String {
        moves.isEmpty ? "No play" : moves.map(\.description).joined(separator: " ")
    }
}

// MARK: - Move Classification

enum MoveClassification: String, Codable, CaseIterable {
    case excellent
    case good
    case inaccuracy
    case mistake
    case blunder

    init(equityLoss: Double) {
        switch abs(equityLoss) {
        case ..<0.005: self = .excellent
        case ..<0.02:  self = .good
        case ..<0.04:  self = .inaccuracy
        case ..<0.08:  self = .mistake
        default:       self = .blunder
        }
    }
}

// MARK: - Turn Record

struct TurnRecord: Codable, Identifiable {
    let id: UUID
    let player: Player
    let dice: Dice
    let chosenPlay: Play
    let boardBefore: BoardState
    let boardAfter: BoardState
    let timestamp: Date

    var gnuEquityOfChosen: Double?
    var gnuEquityOfBest: Double?
    var gnuBestPlay: Play?
    var equityLoss: Double?
    var classification: MoveClassification?
    var explanation: String?
    var positionalThemes: [String]?

    init(player: Player, dice: Dice, chosenPlay: Play,
         boardBefore: BoardState, boardAfter: BoardState) {
        self.id = UUID()
        self.player = player
        self.dice = dice
        self.chosenPlay = chosenPlay
        self.boardBefore = boardBefore
        self.boardAfter = boardAfter
        self.timestamp = Date()
    }
}

// MARK: - Game Record

struct GameRecord: Codable, Identifiable {
    let id: UUID
    let startDate: Date
    var endDate: Date?
    var turns: [TurnRecord] = []
    var result: GameResult?
    var analysis: GameAnalysis?

    init() {
        self.id = UUID()
        self.startDate = Date()
    }
}

struct GameResult: Codable {
    let winner: Player
    let multiplier: Int
    let cubeValue: Int
    let points: Int
    let wasResignation: Bool
}

// MARK: - Board State

struct BoardState: Codable, Equatable, Hashable {
    var points: [Int]       // 25 elements, index 0 unused
    var bar: [Int]           // [white, black]
    var borneOff: [Int]      // [white, black]
    var cube: CubeState
    var currentPlayer: Player

    static func newGame() -> BoardState {
        var pts = [Int](repeating: 0, count: 25)
        pts[6] = 5; pts[8] = 3; pts[13] = 5; pts[24] = 2
        pts[19] = -5; pts[17] = -3; pts[12] = -5; pts[1] = -2
        return BoardState(points: pts, bar: [0, 0], borneOff: [0, 0],
                          cube: CubeState(), currentPlayer: .white)
    }

    // MARK: Queries

    var pipCount: (white: Int, black: Int) {
        var w = bar[0] * 25, b = bar[1] * 25
        for i in 1...24 {
            if points[i] > 0 { w += points[i] * i }
            if points[i] < 0 { b += (-points[i]) * (25 - i) }
        }
        return (w, b)
    }

    func canBearOff(_ player: Player) -> Bool {
        if bar[player.barIndex] > 0 { return false }
        let outside: ClosedRange<Int> = player == .white ? 7...24 : 1...18
        return !outside.contains {
            (player == .white && points[$0] > 0) || (player == .black && points[$0] < 0)
        }
    }

    var isGameOver: Bool { borneOff[0] == 15 || borneOff[1] == 15 }

    var winner: Player? {
        if borneOff[0] == 15 { return .white }
        if borneOff[1] == 15 { return .black }
        return nil
    }

    var gameResult: Int {
        guard let w = winner else { return 0 }
        let loser = w == .white ? 1 : 0
        guard borneOff[loser] == 0 else { return 1 }
        let loserInWinnerHome = (w == .white ? 19...24 : 1...6).contains {
            (w == .white && points[$0] < 0) || (w == .black && points[$0] > 0)
        }
        return (loserInWinnerHome || bar[loser] > 0) ? 3 : 2
    }

    func checkersAt(point: Int, for player: Player) -> Int {
        guard (1...24).contains(point) else { return 0 }
        return player == .white ? max(0, points[point]) : max(0, -points[point])
    }

    func isPointOpen(_ point: Int, for player: Player) -> Bool {
        guard (1...24).contains(point) else { return false }
        return player == .white ? points[point] >= -1 : points[point] <= 1
    }

    func isBlot(_ point: Int, for player: Player) -> Bool {
        guard (1...24).contains(point) else { return false }
        return player == .white ? points[point] == -1 : points[point] == 1
    }

    // MARK: Mutations

    func applying(_ move: CheckerMove, for player: Player) -> BoardState {
        var new = self
        let sign = player.rawValue
        if move.from == 0 || move.from == 25 {
            new.bar[player.barIndex] -= 1
        } else {
            new.points[move.from] -= sign
        }
        if move.isBearOff {
            new.borneOff[player.barIndex] += 1
        } else {
            if move.isHit {
                new.points[move.to] = 0
                new.bar[player.opponent.barIndex] += 1
            }
            new.points[move.to] += sign
        }
        return new
    }

    func applying(_ play: Play, for player: Player) -> BoardState {
        play.moves.reduce(self) { board, move in board.applying(move, for: player) }
    }

    // MARK: Serialization

    func toAnalysisJSON() throws -> Data {
        let pip = pipCount
        let dict: [String: Any] = [
            "points": Array(points[1...24]),
            "bar": ["white": bar[0], "black": bar[1]],
            "borne_off": ["white": borneOff[0], "black": borneOff[1]],
            "cube": ["value": cube.value, "owner": cube.owner?.displayName ?? "centered"],
            "current_player": currentPlayer.displayName,
            "pip_count": ["white": pip.white, "black": pip.black],
            "can_bear_off": ["white": canBearOff(.white), "black": canBearOff(.black)]
        ]
        return try JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)
    }
}
