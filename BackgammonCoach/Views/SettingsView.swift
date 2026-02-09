import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var showAPIKey = false

    var body: some View {
        NavigationView {
            Form {
                Section("Coaching") {
                    Toggle("Show equity numbers", isOn: $settings.showEquityNumbers)
                    Toggle("Post-game analysis", isOn: $settings.postGameAnalysisEnabled)
                    Toggle("Trend analysis", isOn: $settings.trendAnalysisEnabled)
                    Toggle("Explain AI moves", isOn: $settings.explainAIMoves)
                    Picker("Coach Mode", selection: $settings.coachMode) {
                        ForEach(CoachMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    if settings.isRealTimeCoachingEnabled {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sensitivity: \(sensitivityLabel)").font(.subheadline)
                            Slider(value: $settings.coachThreshold, in: 0.005...0.1, step: 0.005)
                            Text("Lower = more feedback").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }

                if settings.explainAIMoves {
                    Section {
                        Text("The AI coach will explain the reasoning behind each move the AI opponent makes. This uses API credits and may slow down gameplay slightly.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Game") {
                    Picker("Play as", selection: $settings.humanColor) {
                        Text("White").tag(PlayerColor.white)
                        Text("Black").tag(PlayerColor.black)
                    }
                    Picker("AI Strength", selection: $settings.aiDifficulty) {
                        Text("Beginner (0-ply)").tag(0)
                        Text("Intermediate (1-ply)").tag(1)
                        Text("Advanced (2-ply)").tag(2)
                        Text("Expert (3-ply)").tag(3)
                        Text("World Class (4-ply)").tag(4)
                    }
                    Toggle("Auto-roll dice", isOn: $settings.autoRoll)
                    Toggle("Highlight movable pieces", isOn: $settings.highlightMovablePieces)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI move delay: \(String(format: "%.1f", settings.aiMoveDelay))s")
                            .font(.subheadline)
                        Slider(value: $settings.aiMoveDelay, in: 0.5...3.0, step: 0.5)
                        Text("Time to show AI dice before move").font(.caption).foregroundColor(.secondary)
                    }
                }

                Section("Server") {
                    TextField("GNU BG Server URL", text: $settings.gnuBgServerURL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    HStack {
                        if showAPIKey {
                            TextField("Claude API Key", text: $settings.claudeAPIKey)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("Claude API Key", text: $settings.claudeAPIKey)
                        }
                        Button {
                            showAPIKey.toggle()
                        } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var sensitivityLabel: String {
        switch settings.coachThreshold {
        case ..<0.01: return "Very sensitive"
        case ..<0.025: return "Standard"
        case ..<0.05: return "Major errors only"
        default: return "Blunders only"
        }
    }
}
