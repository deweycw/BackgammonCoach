import Foundation

// MARK: - Move Analysis (real-time coaching)

struct MoveAnalysis: Codable {
    let chosenPlay: String
    let bestPlay: String
    let equityLoss: Double
    let classification: MoveClassification
    let explanation: String
    let positionalThemes: [String]
}

// MARK: - Game Analysis (post-game)

struct GameAnalysis: Codable {
    let summary: String
    let criticalPositions: [CriticalPosition]
    let overallRating: String
    let strengths: [String]
    let weaknesses: [String]
    let keyLesson: String
}

struct CriticalPosition: Codable {
    let turnNumber: Int
    let equityLoss: Double
    let explanation: String
}

// MARK: - Trend Analysis (multi-game)

struct TrendAnalysis: Codable {
    let summary: String
    let patterns: [PlayPattern]
    let recommendations: [String]
}

struct PlayPattern: Codable {
    let pattern: String
    let frequency: String
    let impact: String
    let advice: String
}

// MARK: - Game Stats (for trend input)

struct GameStats: Codable {
    let gameId: UUID
    let isWin: Bool
    let result: String
    let totalEquityLost: Double
    let blunderCount: Int
    let mistakeCount: Int
    let errorThemes: [String]
}

// MARK: - Aggregate Stats

struct AggregateStats {
    let totalGames: Int
    let wins: Int
    let losses: Int
    let winRate: Double
    let averageEquityLossPerGame: Double
    let averageBlundersPerGame: Double
    let averageMistakesPerGame: Double
    let topErrorThemes: [String]
    let equityTrend: [Double]

    static let empty = AggregateStats(
        totalGames: 0, wins: 0, losses: 0, winRate: 0,
        averageEquityLossPerGame: 0, averageBlundersPerGame: 0,
        averageMistakesPerGame: 0, topErrorThemes: [], equityTrend: []
    )
}
