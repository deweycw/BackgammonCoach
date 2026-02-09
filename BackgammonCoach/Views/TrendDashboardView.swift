import SwiftUI

struct TrendDashboardView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var showResetConfirmation = false

    private let difficultyNames = [
        0: "Beginner (0-ply)",
        1: "Intermediate (1-ply)",
        2: "Advanced (2-ply)",
        3: "Expert (3-ply)",
        4: "World Class (4-ply)"
    ]

    private var hasAnyStats: Bool {
        (0...4).contains { settings.stats(for: $0).totalGames > 0 }
    }

    private var overallStats: (wins: Int, losses: Int, winRate: Double) {
        var totalWins = 0
        var totalLosses = 0
        for level in 0...4 {
            let stats = settings.stats(for: level)
            totalWins += stats.wins
            totalLosses += stats.losses
        }
        let total = totalWins + totalLosses
        let rate = total > 0 ? Double(totalWins) / Double(total) : 0
        return (totalWins, totalLosses, rate)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Progress")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                if hasAnyStats {
                    // Overall summary
                    VStack(spacing: 8) {
                        Text("Overall Record")
                            .font(.headline)
                        HStack(spacing: 20) {
                            VStack {
                                Text("\(overallStats.wins)")
                                    .font(.title.bold())
                                    .foregroundColor(.green)
                                Text("Wins")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            VStack {
                                Text("\(overallStats.losses)")
                                    .font(.title.bold())
                                    .foregroundColor(.red)
                                Text("Losses")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            VStack {
                                Text("\(Int(overallStats.winRate * 100))%")
                                    .font(.title.bold())
                                    .foregroundColor(.blue)
                                Text("Win Rate")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // Stats by difficulty
                    VStack(alignment: .leading, spacing: 12) {
                        Text("By Difficulty")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(0...4, id: \.self) { level in
                            let stats = settings.stats(for: level)
                            if stats.totalGames > 0 {
                                DifficultyStatsRow(
                                    name: difficultyNames[level] ?? "Level \(level)",
                                    stats: stats,
                                    isCurrentLevel: level == settings.aiDifficulty
                                )
                            }
                        }
                    }
                    .padding(.vertical)

                    // Reset button
                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset All Stats")
                        }
                        .font(.caption)
                    }
                    .padding(.top, 10)
                } else {
                    // No stats yet
                    VStack(spacing: 16) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 48))
                            .foregroundColor(.blue.opacity(0.5))

                        Text("Play some games to see your stats here.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Text("Your wins and losses will be tracked for each AI difficulty level. See how you improve as you practice!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.vertical, 40)
                }

                // Coach mode reminder
                if settings.coachMode == .off {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("Coaching is disabled. Enable it in Settings to track move quality.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .confirmationDialog("Reset Stats", isPresented: $showResetConfirmation) {
            Button("Reset All Stats", role: .destructive) {
                settings.resetAllStats()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all your win/loss records.")
        }
    }
}

// MARK: - Difficulty Stats Row

struct DifficultyStatsRow: View {
    let name: String
    let stats: DifficultyStats
    let isCurrentLevel: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(name)
                        .font(.subheadline.bold())
                    if isCurrentLevel {
                        Text("Current")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                }

                HStack(spacing: 12) {
                    Text("\(stats.wins)W - \(stats.losses)L")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if stats.gammonsWon + stats.gammonsLost > 0 {
                        Text("G: \(stats.gammonsWon)/\(stats.gammonsLost)")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    if stats.backgammonsWon + stats.backgammonsLost > 0 {
                        Text("BG: \(stats.backgammonsWon)/\(stats.backgammonsLost)")
                            .font(.caption2)
                            .foregroundColor(.purple)
                    }
                }
            }

            Spacer()

            // Win rate bar
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(stats.winRate * 100))%")
                    .font(.headline.monospacedDigit())
                    .foregroundColor(stats.winRate >= 0.5 ? .green : .red)

                WinRateBar(winRate: stats.winRate)
                    .frame(width: 60, height: 6)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(isCurrentLevel ? Color.blue.opacity(0.1) : Color.clear)
    }
}

// MARK: - Win Rate Bar

struct WinRateBar: View {
    let winRate: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.red.opacity(0.3))

                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.green)
                    .frame(width: geo.size.width * winRate)
            }
        }
    }
}
