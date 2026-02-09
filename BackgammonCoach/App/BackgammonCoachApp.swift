import SwiftUI

@main
struct BackgammonCoachApp: App {
    @StateObject private var settings = AppSettings()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                AppTabView()
                    .environmentObject(settings)
            } else {
                OnboardingView(settings: settings, isOnboardingComplete: $hasCompletedOnboarding)
            }
        }
    }
}

struct AppTabView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var engine: GameEngine = GameEngine(settings: AppSettings())
    @State private var showSettings = false
    @State private var showNewGame = false

    var body: some View {
        NavigationStack {
            HomeView(engine: engine, showSettings: $showSettings, showNewGame: $showNewGame)
        }
        .onAppear {
            engine.startNewMatch(config: .money())
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings)
        }
        .sheet(isPresented: $showNewGame) {
            MatchSetupView(settings: settings, isPresented: $showNewGame) { config in
                engine.startNewMatch(config: config)
            }
        }
    }
}

// MARK: - Home View

struct HomeView: View {
    @ObservedObject var engine: GameEngine
    @Binding var showSettings: Bool
    @Binding var showNewGame: Bool

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // App title
            VStack(spacing: 8) {
                Image(systemName: "dice.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)
                Text("Backgammon Coach")
                    .font(.largeTitle.bold())
            }

            Spacer()

            // Main actions
            VStack(spacing: 16) {
                NavigationLink {
                    MainGameView(engine: engine)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button { showSettings = true } label: {
                                    Image(systemName: "gearshape")
                                }
                            }
                        }
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                NavigationLink {
                    TrendDashboardView()
                } label: {
                    Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                }

                Button {
                    showNewGame = true
                } label: {
                    Label("New Game", systemImage: "plus.circle")
                        .font(.title3)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.tertiarySystemBackground))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            // Settings button
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 20)
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Main Game View

struct MainGameView: View {
    @ObservedObject var engine: GameEngine
    @State private var showFullAnalysis = false
    @State private var showCoachPanel = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }

    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            HStack {
                let pips = engine.board.pipCount
                let humanIsWhite = engine.humanPlayer == .white
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 3) {
                        Circle().fill(.white).frame(width: 10, height: 10)
                            .overlay(Circle().stroke(.gray, lineWidth: 0.5))
                        Text(humanIsWhite ? "You" : "AI")
                            .font(.caption2.bold())
                            .foregroundColor(humanIsWhite ? .blue : .orange)
                        Text("\(pips.white) pips").font(.caption2.monospacedDigit())
                        Text("Off: \(engine.board.borneOff[0])").font(.caption2).foregroundColor(.secondary)
                    }
                    HStack(spacing: 3) {
                        Circle().fill(.black).frame(width: 10, height: 10)
                        Text(humanIsWhite ? "AI" : "You")
                            .font(.caption2.bold())
                            .foregroundColor(humanIsWhite ? .orange : .blue)
                        Text("\(pips.black) pips").font(.caption2.monospacedDigit())
                        Text("Off: \(engine.board.borneOff[1])").font(.caption2).foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Whose turn indicator
                VStack(spacing: 2) {
                    Text("Turn:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(engine.board.currentPlayer == .white ? Color.white : Color.black)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.gray, lineWidth: 0.5))
                        Text(engine.board.currentPlayer == engine.humanPlayer ? "You" : "AI")
                            .font(.caption.bold())
                    }
                }

                Spacer()

                ZStack {
                    RoundedRectangle(cornerRadius: 3).fill(.white).frame(width: 26, height: 26)
                        .shadow(radius: 1)
                    Text("\(engine.board.cube.value)")
                        .font(.system(.caption, design: .rounded).bold())
                }
                .onTapGesture { if engine.canOfferCube { engine.offerDouble() } }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            // Board
            BoardView(engine: engine)
                .aspectRatio(isLandscape ? 2.0 : 1.2, contentMode: .fit)
                .clipped()
                .padding(.horizontal, 2)

            // Dice + controls bar
            VStack(spacing: 6) {
                // Opening roll display
                if engine.phase == .openingRoll {
                    VStack(spacing: 8) {
                        Text("Opening Roll").font(.headline)
                        HStack(spacing: 30) {
                            // White's die
                            VStack(spacing: 4) {
                                HStack(spacing: 4) {
                                    Circle().fill(.white).frame(width: 12, height: 12)
                                        .overlay(Circle().stroke(.gray, lineWidth: 0.5))
                                    Text("White")
                                        .font(.caption.bold())
                                        .foregroundColor(engine.humanPlayer == .white ? .blue : .orange)
                                }
                                if let roll = engine.openingRollWhite {
                                    LargeDieView(value: roll, size: 50)
                                        .transition(.scale.combined(with: .opacity))
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 50, height: 50)
                                }
                            }

                            // Black's die
                            VStack(spacing: 4) {
                                HStack(spacing: 4) {
                                    Circle().fill(.black).frame(width: 12, height: 12)
                                    Text("Black")
                                        .font(.caption.bold())
                                        .foregroundColor(engine.humanPlayer == .black ? .blue : .orange)
                                }
                                if let roll = engine.openingRollBlack {
                                    LargeDieView(value: roll, size: 50)
                                        .transition(.scale.combined(with: .opacity))
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 50, height: 50)
                                }
                            }
                        }
                        .animation(.easeOut(duration: 0.3), value: engine.openingRollWhite)
                        .animation(.easeOut(duration: 0.3), value: engine.openingRollBlack)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }

                // AI dice and status (shown during AI turn)
                if let aiDice = engine.aiDice {
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            Circle().fill(Color.black).frame(width: 10, height: 10)
                            Text("AI (\(engine.humanPlayer.opponent.displayName))")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            LargeDieView(value: aiDice.die1, size: 40)
                            LargeDieView(value: aiDice.die2, size: 40)
                            if engine.aiThinking {
                                ProgressView().scaleEffect(0.6)
                                Text("thinking...").font(.caption2).foregroundColor(.secondary)
                            }
                        }

                        // Show current move being made
                        if engine.currentAIMoveIndex > 0 {
                            HStack(spacing: 6) {
                                Text("Move \(engine.currentAIMoveIndex) of \(engine.totalAIMoves):")
                                    .font(.caption2.bold())
                                    .foregroundColor(.orange)
                                Text(engine.currentAIMoveDescription)
                                    .font(.system(.caption, design: .monospaced).bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.orange)
                                    .cornerRadius(4)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(8)
                }

                // Human player controls (hidden during opening roll and AI turn)
                if engine.phase != .openingRoll && engine.aiDice == nil {
                    HStack(spacing: 10) {
                        Button { engine.undoLastMove() } label: {
                            Image(systemName: "arrow.uturn.backward").font(.caption)
                        }.disabled(engine.phase != .moving || engine.currentTurnMoves.isEmpty)

                        DiceView(
                            dice: engine.pendingDice,
                            remainingDice: engine.remainingDice,
                            onRoll: { engine.rollDice() },
                            onSwap: { engine.swapDiceOrder() },
                            canRoll: engine.phase == .rolling && engine.board.currentPlayer == engine.humanPlayer,
                            canSwap: engine.phase == .moving && engine.remainingDice.count == 2
                        )

                        Button { engine.confirmTurn() } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                if engine.turnReadyToConfirm {
                                    Text("Confirm")
                                }
                            }
                            .font(.caption)
                            .padding(.horizontal, engine.turnReadyToConfirm ? 12 : 6)
                            .padding(.vertical, 6)
                            .background(engine.turnReadyToConfirm ? Color.green : Color.clear)
                            .foregroundColor(engine.turnReadyToConfirm ? .white : .primary)
                            .cornerRadius(6)
                        }
                        .disabled(!engine.turnReadyToConfirm)

                        if case .cubeOffered(let by) = engine.phase, by != engine.humanPlayer {
                            Button("Take") { engine.respondToCube(accept: true) }
                                .buttonStyle(.borderedProminent).tint(.green).font(.caption2)
                            Button("Pass") { engine.respondToCube(accept: false) }
                                .buttonStyle(.borderedProminent).tint(.red).font(.caption2)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)

            // Game over state
            if case .gameOver(let winner, let multiplier) = engine.phase {
                VStack(spacing: 8) {
                    // Result banner
                    HStack {
                        let resultName = multiplier == 3 ? "Backgammon!" : multiplier == 2 ? "Gammon!" : "Game Over"
                        let isWin = winner == engine.humanPlayer
                        Image(systemName: isWin ? "trophy.fill" : "flag.fill")
                            .foregroundColor(isWin ? .yellow : .gray)
                        Text(resultName)
                            .font(.headline.bold())
                        Text(isWin ? "You Win!" : "AI Wins")
                            .foregroundColor(isWin ? .green : .red)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)

                    // Analysis status
                    if engine.isAnalyzing {
                        HStack {
                            ProgressView().scaleEffect(0.8)
                            Text("Generating game analysis...").font(.caption)
                        }
                    } else if engine.gameRecord.analysis != nil {
                        Button {
                            showFullAnalysis = true
                        } label: {
                            HStack {
                                Image(systemName: "chart.bar.doc.horizontal")
                                Text("View Game Analysis")
                            }
                            .font(.subheadline.bold())
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                    }

                    // Action buttons
                    HStack(spacing: 10) {
                        if engine.matchConfig.gameType == .match && !engine.matchState.isMatchOver {
                            Button("Next Game") { engine.startNextGameInMatch() }
                                .buttonStyle(.borderedProminent).font(.caption)
                        }
                        Button("New Game") {
                            engine.analysisReady = false
                            engine.startNewGame()
                        }
                        .buttonStyle(.bordered).font(.caption)
                    }
                }
                .padding(.vertical, 8)
            }

            if case .matchOver = engine.phase {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "trophy.fill").foregroundColor(.yellow)
                        Text("Match Complete!").font(.headline.bold())
                    }
                    if engine.gameRecord.analysis != nil {
                        Button {
                            showFullAnalysis = true
                        } label: {
                            HStack {
                                Image(systemName: "chart.bar.doc.horizontal")
                                Text("View Analysis")
                            }
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        }
                    }
                    Button("New Match") {
                        engine.analysisReady = false
                        engine.startNewMatch(config: engine.matchConfig)
                    }
                    .buttonStyle(.borderedProminent).font(.caption)
                }
                .padding(.vertical, 8)
            }

            Spacer(minLength: 0)

            // Coach toggle at bottom
            VStack(spacing: 0) {
                HStack {
                    Button {
                        withAnimation { showCoachPanel.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "brain.head.profile")
                            Text("Coach")
                            if engine.messageLog.count > 0 {
                                Text("(\(engine.messageLog.count))").foregroundColor(.secondary)
                            }
                            Image(systemName: showCoachPanel ? "chevron.down" : "chevron.up")
                                .font(.caption2)
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                    }
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

                if showCoachPanel {
                    CoachPanel(engine: engine)
                        .frame(maxHeight: 150)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showFullAnalysis) {
            if let analysis = engine.gameRecord.analysis {
                GameAnalysisView(analysis: analysis, turns: engine.gameRecord.turns)
            }
        }
        .onChange(of: engine.analysisReady) { ready in
            if ready {
                showFullAnalysis = true
                engine.analysisReady = false
            }
        }
    }
}