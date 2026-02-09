import Foundation

// MARK: - Match Configuration

struct MatchConfig: Codable, Equatable {
    enum GameType: String, Codable, CaseIterable {
        case money = "Money Game"
        case match = "Match"
    }

    let gameType: GameType
    let matchLength: Int
    let jacobyRule: Bool
    let beaverRule: Bool

    static func money(jacoby: Bool = true, beaver: Bool = true) -> MatchConfig {
        MatchConfig(gameType: .money, matchLength: 0, jacobyRule: jacoby, beaverRule: beaver)
    }

    static func match(length: Int) -> MatchConfig {
        MatchConfig(gameType: .match, matchLength: length, jacobyRule: false, beaverRule: false)
    }
}

// MARK: - Match State

struct MatchState: Codable, Equatable {
    let config: MatchConfig
    var score: [Int]
    var currentGameNumber: Int
    var isCrawford: Bool
    var isPostCrawford: Bool

    init(config: MatchConfig) {
        self.config = config
        self.score = [0, 0]
        self.currentGameNumber = 1
        self.isCrawford = false
        self.isPostCrawford = false
    }

    var isMatchOver: Bool {
        guard config.gameType == .match else { return false }
        return score[0] >= config.matchLength || score[1] >= config.matchLength
    }

    var matchWinner: Player? {
        guard isMatchOver else { return nil }
        if score[0] >= config.matchLength { return .white }
        if score[1] >= config.matchLength { return .black }
        return nil
    }

    var pointsToGo: (white: Int, black: Int) {
        guard config.gameType == .match else { return (0, 0) }
        return (max(0, config.matchLength - score[0]),
                max(0, config.matchLength - score[1]))
    }

    var isCubeAvailable: Bool {
        if config.gameType == .money { return true }
        return !isCrawford
    }

    func gammonMultiplierApplies(cubeValue: Int) -> Bool {
        if config.gameType == .money {
            return !config.jacobyRule || cubeValue > 1
        }
        return true
    }

    var matchEquity: (white: Double, black: Double) {
        guard config.gameType == .match else { return (0.5, 0.5) }
        let ptg = pointsToGo
        let whiteEq = MatchEquityTable.equity(awayWhite: ptg.white, awayBlack: ptg.black)
        return (whiteEq, 1.0 - whiteEq)
    }

    mutating func recordGameResult(winner: Player, multiplier: Int, cubeValue: Int) {
        let winnerIdx = winner == .white ? 0 : 1
        let actualMultiplier = gammonMultiplierApplies(cubeValue: cubeValue) ? multiplier : 1
        score[winnerIdx] += actualMultiplier * cubeValue
        currentGameNumber += 1
        updateCrawfordState()
    }

    private mutating func updateCrawfordState() {
        guard config.gameType == .match else { return }
        if isPostCrawford { isCrawford = false; return }
        let whiteAway = config.matchLength - score[0]
        let blackAway = config.matchLength - score[1]
        if (whiteAway == 1 || blackAway == 1) && !isCrawford && !isPostCrawford {
            isCrawford = true
        } else if isCrawford {
            isCrawford = false
            isPostCrawford = true
        }
    }
}

// MARK: - Match Equity Table (Mec26 / Kazaross-Trice)

struct MatchEquityTable {
    static func equity(awayWhite: Int, awayBlack: Int) -> Double {
        let w = min(max(awayWhite, 0), maxAway)
        let b = min(max(awayBlack, 0), maxAway)
        if w <= 0 { return 1.0 }
        if b <= 0 { return 0.0 }
        return table[w - 1][b - 1]
    }

    private static let maxAway = 15

    private static let table: [[Double]] = [
        [0.500, 0.685, 0.749, 0.812, 0.843, 0.874, 0.893, 0.911, 0.922, 0.933, 0.941, 0.948, 0.954, 0.959, 0.963],
        [0.315, 0.500, 0.594, 0.664, 0.710, 0.748, 0.778, 0.802, 0.822, 0.839, 0.853, 0.865, 0.875, 0.884, 0.892],
        [0.251, 0.406, 0.500, 0.575, 0.629, 0.674, 0.710, 0.740, 0.765, 0.786, 0.804, 0.820, 0.833, 0.845, 0.856],
        [0.188, 0.336, 0.425, 0.500, 0.559, 0.608, 0.649, 0.684, 0.714, 0.739, 0.761, 0.780, 0.797, 0.811, 0.824],
        [0.157, 0.290, 0.371, 0.441, 0.500, 0.551, 0.595, 0.633, 0.666, 0.694, 0.719, 0.741, 0.760, 0.777, 0.792],
        [0.126, 0.252, 0.326, 0.392, 0.449, 0.500, 0.546, 0.586, 0.621, 0.652, 0.680, 0.704, 0.726, 0.745, 0.762],
        [0.107, 0.222, 0.290, 0.351, 0.405, 0.454, 0.500, 0.541, 0.578, 0.611, 0.641, 0.668, 0.692, 0.713, 0.732],
        [0.089, 0.198, 0.260, 0.316, 0.367, 0.414, 0.459, 0.500, 0.538, 0.572, 0.604, 0.633, 0.659, 0.682, 0.703],
        [0.078, 0.178, 0.235, 0.286, 0.334, 0.379, 0.422, 0.462, 0.500, 0.535, 0.568, 0.598, 0.626, 0.651, 0.674],
        [0.067, 0.161, 0.214, 0.261, 0.306, 0.348, 0.389, 0.428, 0.465, 0.500, 0.533, 0.564, 0.593, 0.620, 0.644],
        [0.059, 0.147, 0.196, 0.239, 0.281, 0.320, 0.359, 0.396, 0.432, 0.467, 0.500, 0.532, 0.562, 0.590, 0.616],
        [0.052, 0.135, 0.180, 0.220, 0.259, 0.296, 0.332, 0.367, 0.402, 0.436, 0.468, 0.500, 0.531, 0.560, 0.587],
        [0.046, 0.125, 0.167, 0.203, 0.240, 0.274, 0.308, 0.341, 0.374, 0.407, 0.438, 0.469, 0.500, 0.530, 0.558],
        [0.041, 0.116, 0.155, 0.189, 0.223, 0.255, 0.287, 0.318, 0.349, 0.380, 0.410, 0.440, 0.470, 0.500, 0.529],
        [0.037, 0.108, 0.144, 0.176, 0.208, 0.238, 0.268, 0.297, 0.326, 0.356, 0.384, 0.413, 0.442, 0.471, 0.500],
    ]
}
