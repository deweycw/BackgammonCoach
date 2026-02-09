import SwiftUI

// MARK: - Match Setup

struct MatchSetupView: View {
    @ObservedObject var settings: AppSettings
    @Binding var isPresented: Bool
    let onStart: (MatchConfig) -> Void

    @State private var gameType: MatchConfig.GameType = .money
    @State private var matchLength: Int = 5
    @State private var jacobyRule: Bool = true
    @State private var beaverRule: Bool = false

    var body: some View {
        NavigationView {
            Form {
                Section("Game Type") {
                    Picker("Type", selection: $gameType) {
                        Text("Money Game").tag(MatchConfig.GameType.money)
                        Text("Match").tag(MatchConfig.GameType.match)
                    }.pickerStyle(.segmented)
                }
                if gameType == .match {
                    Section {
                        Stepper("Match to \(matchLength)", value: $matchLength, in: 1...25, step: 2)
                        HStack(spacing: 10) {
                            ForEach([3, 5, 7, 9, 11], id: \.self) { len in
                                Button("\(len)") { matchLength = len }
                                    .buttonStyle(.bordered).tint(matchLength == len ? .blue : .secondary)
                            }
                        }
                    } header: { Text("Match Length") }
                }
                if gameType == .money {
                    Section("Money Game Rules") {
                        Toggle("Jacoby Rule", isOn: $jacobyRule)
                        Toggle("Beaver Rule", isOn: $beaverRule)
                    }
                }
                Section("Opponent") {
                    Picker("AI Strength", selection: $settings.aiDifficulty) {
                        Text("Beginner").tag(0); Text("Intermediate").tag(1)
                        Text("Advanced").tag(2); Text("Expert").tag(3)
                        Text("World Class").tag(4)
                    }
                }
                Section("Coaching") {
                    Picker("Coach Mode", selection: $settings.coachMode) {
                        ForEach(CoachMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
            }
            .navigationTitle("New Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isPresented = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        let config: MatchConfig = gameType == .match
                            ? .match(length: matchLength)
                            : .money(jacoby: jacobyRule, beaver: beaverRule)
                        onStart(config)
                        isPresented = false
                    }.bold()
                }
            }
        }
    }
}

// MARK: - Game Analysis View

struct GameAnalysisView: View {
    let analysis: GameAnalysis
    let turns: [TurnRecord]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Overall Rating").font(.subheadline).foregroundColor(.secondary)
                            Text(analysis.overallRating).font(.title2).bold()
                        }
                        Spacer()
                        errorSummary
                    }
                    .padding().background(Color(.secondarySystemBackground)).cornerRadius(12)

                    Text(analysis.summary).font(.body)

                    if !analysis.criticalPositions.isEmpty {
                        Text("Critical Moments").font(.headline)
                        ForEach(Array(analysis.criticalPositions.enumerated()), id: \.offset) { _, pos in
                            HStack(alignment: .top, spacing: 8) {
                                Text("T\(pos.turnNumber)").font(.caption.bold())
                                    .padding(4).background(Color.red.opacity(0.2)).cornerRadius(4)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(String(format: "Loss: %.3f", pos.equityLoss))
                                        .font(.caption).foregroundColor(.red)
                                    Text(pos.explanation).font(.caption)
                                }
                            }.padding(8).background(Color(.secondarySystemBackground)).cornerRadius(6)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Key Lesson", systemImage: "lightbulb.fill")
                            .font(.headline).foregroundColor(.yellow)
                        Text(analysis.keyLesson).font(.body)
                    }
                    .padding().background(Color.yellow.opacity(0.1)).cornerRadius(12)

                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Strengths", systemImage: "hand.thumbsup.fill")
                                .font(.subheadline.bold()).foregroundColor(.green)
                            ForEach(analysis.strengths, id: \.self) { Text("• \($0)").font(.caption) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 6) {
                            Label("To Improve", systemImage: "arrow.up.right")
                                .font(.subheadline.bold()).foregroundColor(.orange)
                            ForEach(analysis.weaknesses, id: \.self) { Text("• \($0)").font(.caption) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.padding().background(Color(.secondarySystemBackground)).cornerRadius(12)
                }.padding()
            }
            .navigationTitle("Game Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    private var errorSummary: some View {
        HStack(spacing: 10) {
            let b = turns.filter { $0.classification == .blunder }.count
            let m = turns.filter { $0.classification == .mistake }.count
            VStack { Text("\(b)").font(.title3.bold()).foregroundColor(.red); Text("Blunders").font(.caption2) }
            VStack { Text("\(m)").font(.title3.bold()).foregroundColor(.orange); Text("Mistakes").font(.caption2) }
        }
    }
}
