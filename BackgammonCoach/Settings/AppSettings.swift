import Foundation
import SwiftUI
import Combine

// MARK: - Stats Per Difficulty Level

struct DifficultyStats: Codable, Equatable {
    var wins: Int = 0
    var losses: Int = 0
    var gammonsWon: Int = 0
    var gammonsLost: Int = 0
    var backgammonsWon: Int = 0
    var backgammonsLost: Int = 0

    var totalGames: Int { wins + losses }
    var winRate: Double {
        guard totalGames > 0 else { return 0 }
        return Double(wins) / Double(totalGames)
    }
}

// MARK: - Coach Mode

enum CoachMode: String, CaseIterable {
    case off = "Off"
    case passive = "Post-Game Only"
    case active = "Active Coaching"
    case full = "Full Analysis"
}

// MARK: - Player Color Preference

enum PlayerColor: String, CaseIterable {
    case white = "white"
    case black = "black"
    var player: Player { self == .white ? .white : .black }
}

// MARK: - App Settings

class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var coachMode: CoachMode {
        didSet { defaults.set(coachMode.rawValue, forKey: "coachMode") }
    }
    @Published var coachThreshold: Double {
        didSet { defaults.set(coachThreshold, forKey: "coachThreshold") }
    }
    @Published var showEquityNumbers: Bool {
        didSet { defaults.set(showEquityNumbers, forKey: "showEquityNumbers") }
    }
    @Published var showPositionalThemes: Bool {
        didSet { defaults.set(showPositionalThemes, forKey: "showPositionalThemes") }
    }
    @Published var postGameAnalysisEnabled: Bool {
        didSet { defaults.set(postGameAnalysisEnabled, forKey: "postGameAnalysisEnabled") }
    }
    @Published var trendAnalysisEnabled: Bool {
        didSet { defaults.set(trendAnalysisEnabled, forKey: "trendAnalysisEnabled") }
    }
    @Published var aiDifficulty: Int {
        didSet { defaults.set(aiDifficulty, forKey: "aiDifficulty") }
    }
    @Published var autoRoll: Bool {
        didSet { defaults.set(autoRoll, forKey: "autoRoll") }
    }
    @Published var highlightMovablePieces: Bool {
        didSet { defaults.set(highlightMovablePieces, forKey: "highlightMovablePieces") }
    }
    @Published var aiMoveDelay: Double {
        didSet { defaults.set(aiMoveDelay, forKey: "aiMoveDelay") }
    }
    @Published var explainAIMoves: Bool {
        didSet { defaults.set(explainAIMoves, forKey: "explainAIMoves") }
    }
    @Published var humanColor: PlayerColor {
        didSet { defaults.set(humanColor.rawValue, forKey: "humanColor") }
    }
    @Published var gnuBgServerURL: String {
        didSet { defaults.set(gnuBgServerURL, forKey: "gnuBgServerURL") }
    }
    @Published var claudeAPIKey: String {
        didSet { defaults.set(claudeAPIKey, forKey: "claudeAPIKey") }
    }

    /// Stats per AI difficulty level (0-4 ply)
    @Published var statsByDifficulty: [Int: DifficultyStats] {
        didSet { saveStats() }
    }

    init() {
        let d = UserDefaults.standard
        self.coachMode = CoachMode(rawValue: d.string(forKey: "coachMode") ?? "") ?? .active
        self.coachThreshold = d.object(forKey: "coachThreshold") as? Double ?? 0.02
        self.showEquityNumbers = d.bool(forKey: "showEquityNumbers")
        self.showPositionalThemes = d.object(forKey: "showPositionalThemes") as? Bool ?? true
        self.postGameAnalysisEnabled = d.object(forKey: "postGameAnalysisEnabled") as? Bool ?? true
                self.trendAnalysisEnabled = d.object(forKey: "trendAnalysisEnabled") as? Bool ?? true
                self.aiDifficulty = d.object(forKey: "aiDifficulty") as? Int ?? 2
                self.autoRoll = d.bool(forKey: "autoRoll")
                self.highlightMovablePieces = d.object(forKey: "highlightMovablePieces") as? Bool ?? false
                self.aiMoveDelay = d.object(forKey: "aiMoveDelay") as? Double ?? 0.8
                self.explainAIMoves = d.object(forKey: "explainAIMoves") as? Bool ?? false
                self.humanColor = PlayerColor(rawValue: d.string(forKey: "humanColor") ?? "") ?? .white
                self.gnuBgServerURL = d.string(forKey: "gnuBgServerURL") ?? "http://localhost:8080"
                self.claudeAPIKey = d.string(forKey: "claudeAPIKey") ?? ""

                // Load stats
                if let data = d.data(forKey: "statsByDifficulty"),
                   let decoded = try? JSONDecoder().decode([Int: DifficultyStats].self, from: data) {
                    self.statsByDifficulty = decoded
                } else {
                    self.statsByDifficulty = [:]
                }
            }

            private func saveStats() {
                if let encoded = try? JSONEncoder().encode(statsByDifficulty) {
                    defaults.set(encoded, forKey: "statsByDifficulty")
                }
            }

            /// Record a game result for the current AI difficulty
            func recordGameResult(won: Bool, multiplier: Int) {
                var stats = statsByDifficulty[aiDifficulty] ?? DifficultyStats()

                if won {
                    stats.wins += 1
                    if multiplier == 2 { stats.gammonsWon += 1 }
                    else if multiplier == 3 { stats.backgammonsWon += 1 }
                } else {
                    stats.losses += 1
                    if multiplier == 2 { stats.gammonsLost += 1 }
                    else if multiplier == 3 { stats.backgammonsLost += 1 }
                }

                statsByDifficulty[aiDifficulty] = stats
            }

            /// Get stats for a specific difficulty level
            func stats(for difficulty: Int) -> DifficultyStats {
                statsByDifficulty[difficulty] ?? DifficultyStats()
            }

            /// Reset all stats
            func resetAllStats() {
                statsByDifficulty = [:]
            }

            var isRealTimeCoachingEnabled: Bool {
                coachMode == .active || coachMode == .full
            }

            var isAnyCoachingEnabled: Bool {
                coachMode != .off
            }

            var equityLossThreshold: Double {
                switch coachMode {
                case .off:      return .infinity
                case .passive:  return .infinity
                case .active:   return coachThreshold
                case .full:     return 0.0
                }
            }
        }
