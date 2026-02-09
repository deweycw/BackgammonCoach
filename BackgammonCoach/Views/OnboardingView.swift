import SwiftUI

struct OnboardingView: View {
    @ObservedObject var settings: AppSettings
    @Binding var isOnboardingComplete: Bool

    @State private var step = 0  // 0=welcome, 1=server, 2=apiKey, 3=prefs, 4=ready
    @State private var serverOK = false
    @State private var apiOK = false
    @State private var testing = false

    var body: some View {
        VStack(spacing: 0) {
            // Progress
            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { i in
                    Capsule().fill(i <= step ? Color.blue : Color.gray.opacity(0.3)).frame(height: 4)
                }
            }.padding(.horizontal, 32).padding(.top)

            TabView(selection: $step) {
                welcomeView.tag(0)
                serverView.tag(1)
                apiKeyView.tag(2)
                prefsView.tag(3)
                readyView.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: step)

            // Navigation
            HStack {
                if step > 0 { Button("Back") { step -= 1 } }
                Spacer()
                if step == 4 {
                    Button("Start Playing") { isOnboardingComplete = true }
                        .bold().padding(.horizontal, 20).padding(.vertical, 10)
                        .background(Color.blue).foregroundColor(.white).cornerRadius(10)
                } else {
                    Button { step += 1 } label: {
                        HStack { Text("Next"); Image(systemName: "arrow.right") }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Color.blue).foregroundColor(.white).cornerRadius(10)
                    }
                }
            }.padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Steps

    private var welcomeView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "dice.fill").font(.system(size: 64)).foregroundColor(.blue)
            Text("Backgammon Coach").font(.largeTitle.bold())
            Text("Play backgammon against AI while getting real-time coaching from Claude.")
                .font(.body).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            VStack(alignment: .leading, spacing: 10) {
                feat("brain.head.profile", .purple, "Move Analysis", "Feedback on suboptimal plays")
                feat("chart.line.uptrend.xyaxis", .green, "Trend Tracking", "Patterns in your game")
                feat("cube", .orange, "Cube Coaching", "When to double and take")
                feat("trophy", .yellow, "Match Play", "Money games or matches")
            }.padding(.horizontal, 32)
            Spacer()
        }
    }

    private func feat(_ icon: String, _ color: Color, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.title3).foregroundColor(color).frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.bold())
                Text(sub).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private var serverView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "server.rack").font(.system(size: 48)).foregroundColor(.blue)
            Text("GNU Backgammon Server").font(.title2.bold())
            Text("Powers the AI opponent and position evaluation.")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            VStack(spacing: 12) {
                HStack {
                    TextField("http://localhost:8080", text: $settings.gnuBgServerURL)
                        .textFieldStyle(.roundedBorder).autocapitalization(.none)
                    Button("Test") { testServer() }.buttonStyle(.borderedProminent).disabled(testing)
                }
                if serverOK {
                    Label("Connected", systemImage: "checkmark.circle.fill").font(.caption).foregroundColor(.green)
                }
            }.padding(.horizontal, 32)
            Spacer()
        }
    }

    private var apiKeyView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "brain.head.profile").font(.system(size: 48)).foregroundColor(.purple)
            Text("Claude API Key").font(.title2.bold())
            Text("Provides natural-language coaching explanations.")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            VStack(spacing: 12) {
                HStack {
                    SecureField("sk-ant-...", text: $settings.claudeAPIKey)
                        .textFieldStyle(.roundedBorder).autocapitalization(.none)
                    Button("Test") { testAPI() }.buttonStyle(.borderedProminent).tint(.purple).disabled(testing)
                }
                if apiOK {
                    Label("Valid", systemImage: "checkmark.circle.fill").font(.caption).foregroundColor(.green)
                }
                Button("Skip — play without coaching") {
                    settings.coachMode = .off; step = 3
                }.font(.caption).foregroundColor(.secondary)
            }.padding(.horizontal, 32)
            Spacer()
        }
    }

    private var prefsView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "slider.horizontal.3").font(.system(size: 48)).foregroundColor(.green)
            Text("Coaching Preferences").font(.title2.bold())
            VStack(spacing: 10) {
                ForEach(CoachMode.allCases, id: \.self) { mode in
                    let sel = settings.coachMode == mode
                    let disabled = mode != .off && settings.claudeAPIKey.isEmpty
                    Button {
                        if !disabled { settings.coachMode = mode }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.rawValue).font(.subheadline.bold())
                                Text(modeDesc(mode)).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            if sel { Image(systemName: "checkmark.circle.fill").foregroundColor(.blue) }
                        }
                        .padding().background(sel ? Color.blue.opacity(0.1) : Color(.secondarySystemBackground))
                        .cornerRadius(10).overlay(RoundedRectangle(cornerRadius: 10).stroke(sel ? Color.blue : .clear, lineWidth: 2))
                    }.disabled(disabled).opacity(disabled ? 0.5 : 1)
                }
            }.padding(.horizontal, 32)
            Spacer()
        }
    }

    private var readyView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundColor(.green)
            Text("You're All Set").font(.title2.bold())
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "server.rack").foregroundColor(serverOK ? .green : .orange).frame(width: 24)
                    Text("Server"); Spacer()
                    Text(serverOK ? "Connected" : "Not configured").foregroundColor(serverOK ? .green : .orange)
                }
                HStack {
                    Image(systemName: "brain.head.profile").foregroundColor(.purple).frame(width: 24)
                    Text("Coaching"); Spacer()
                    Text(settings.coachMode.rawValue).foregroundColor(.purple)
                }
            }.font(.subheadline).padding(16)
            .background(Color(.secondarySystemBackground)).cornerRadius(12).padding(.horizontal, 32)
            Spacer()
        }
    }

    private func modeDesc(_ mode: CoachMode) -> String {
        switch mode {
        case .off: return "No analysis"
        case .passive: return "Review after game ends"
        case .active: return "Flag significant errors"
        case .full: return "Analyze every move"
        }
    }

    private func testServer() {
        testing = true
        Task {
            let gnuBg = GNUBgService(baseURL: URL(string: settings.gnuBgServerURL)!)
            let ok = (try? await gnuBg.checkHealth()) ?? false
            await MainActor.run { serverOK = ok; testing = false }
        }
    }

    private func testAPI() {
        testing = true
        Task {
            do {
                let url = URL(string: "https://api.anthropic.com/v1/messages")!
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue(settings.claudeAPIKey, forHTTPHeaderField: "x-api-key")
                req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                req.timeoutInterval = 15
                let body: [String: Any] = [
                    "model": "claude-sonnet-4-5-20250929", "max_tokens": 16,
                    "messages": [["role": "user", "content": "Say ok"]]
                ]
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (_, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                await MainActor.run { apiOK = (200...299).contains(code) || code == 429; testing = false }
            } catch {
                await MainActor.run { apiOK = false; testing = false }
            }
        }
    }
}
