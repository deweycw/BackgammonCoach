import SwiftUI

// MARK: - Large Die View (for clear display)

struct LargeDieView: View {
    let value: Int
    var size: CGFloat = 44
    var isHighlighted: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)

            // Dot pattern for dice
            DieDotsView(value: value, size: size * 0.7)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isHighlighted ? Color.blue : Color.gray.opacity(0.3), lineWidth: isHighlighted ? 2 : 1)
        )
    }
}

// MARK: - Die Dots Pattern

struct DieDotsView: View {
    let value: Int
    let size: CGFloat

    var body: some View {
        let dotSize = size * 0.22
        let spacing = size * 0.28

        ZStack {
            // Center dot (1, 3, 5)
            if [1, 3, 5].contains(value) {
                Circle().fill(.black).frame(width: dotSize, height: dotSize)
            }
            // Top-left and bottom-right (2, 3, 4, 5, 6)
            if value >= 2 {
                Circle().fill(.black).frame(width: dotSize, height: dotSize)
                    .offset(x: -spacing, y: -spacing)
                Circle().fill(.black).frame(width: dotSize, height: dotSize)
                    .offset(x: spacing, y: spacing)
            }
            // Top-right and bottom-left (4, 5, 6)
            if value >= 4 {
                Circle().fill(.black).frame(width: dotSize, height: dotSize)
                    .offset(x: spacing, y: -spacing)
                Circle().fill(.black).frame(width: dotSize, height: dotSize)
                    .offset(x: -spacing, y: spacing)
            }
            // Middle-left and middle-right (6)
            if value == 6 {
                Circle().fill(.black).frame(width: dotSize, height: dotSize)
                    .offset(x: -spacing, y: 0)
                Circle().fill(.black).frame(width: dotSize, height: dotSize)
                    .offset(x: spacing, y: 0)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Dice View

struct DiceView: View {
    let dice: Dice?
    let remainingDice: [Int]  // Ordered: first element is next move
    let onRoll: () -> Void
    let onSwap: () -> Void
    let canRoll: Bool
    let canSwap: Bool

    var body: some View {
        HStack(spacing: 12) {
            if let dice = dice {
                if dice.isDoubles {
                    // For doubles, show single die with count
                    LargeDieView(value: dice.die1, size: 48)
                    Text("×\(remainingDice.count)")
                        .font(.title3.bold())
                        .foregroundColor(.secondary)
                } else {
                    // Show dice in order - first die is labeled "1st", second is "2nd"
                    HStack(spacing: 10) {
                        if remainingDice.count == 2 {
                            orderedDieFace(remainingDice[0], label: "1st", isFirst: true)
                            orderedDieFace(remainingDice[1], label: "2nd", isFirst: false)
                        } else if remainingDice.count == 1 {
                            let usedDie = dice.die1 == remainingDice[0] ? dice.die2 : dice.die1
                            usedDieFace(usedDie)
                            orderedDieFace(remainingDice[0], label: "1st", isFirst: true)
                        } else {
                            usedDieFace(dice.die1)
                            usedDieFace(dice.die2)
                        }
                    }
                    .onTapGesture {
                        if canSwap { onSwap() }
                    }
                }
            } else if canRoll {
                Button(action: onRoll) {
                    HStack(spacing: 8) {
                        Image(systemName: "dice.fill")
                            .font(.title2)
                        Text("Roll")
                            .font(.headline)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
        }
    }

    private func usedDieFace(_ value: Int) -> some View {
        LargeDieView(value: value, size: 44)
            .opacity(0.4)
    }

    private func orderedDieFace(_ value: Int, label: String, isFirst: Bool) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isFirst ? .blue : .secondary)
            LargeDieView(value: value, size: 48, isHighlighted: isFirst)
        }
    }
}

// MARK: - Scoreboard View

struct ScoreboardView: View {
    let matchState: MatchState
    let humanPlayer: Player

    var body: some View {
        if matchState.config.gameType == .match {
            HStack(spacing: 12) {
                playerScore(.white, matchState.score[0], humanPlayer == .white)
                VStack(spacing: 2) {
                    Text("Match to \(matchState.config.matchLength)").font(.caption2).foregroundColor(.secondary)
                    Text("Game \(matchState.currentGameNumber)").font(.caption2).foregroundColor(.secondary)
                    if matchState.isCrawford {
                        Text("CRAWFORD").font(.caption2.bold()).foregroundColor(.red)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.red.opacity(0.15)).cornerRadius(4)
                    }
                }
                playerScore(.black, matchState.score[1], humanPlayer == .black)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color(.secondarySystemBackground)).cornerRadius(8)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle").foregroundColor(.green)
                Text("Money Game").font(.caption)
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color(.secondarySystemBackground)).cornerRadius(6)
        }
    }

    private func playerScore(_ player: Player, _ score: Int, _ isHuman: Bool) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Circle().fill(player == .white ? .white : .black).frame(width: 10, height: 10)
                    .overlay(Circle().stroke(.gray, lineWidth: 0.5))
                Text(isHuman ? "You" : "AI").font(.caption2).foregroundColor(.secondary)
            }
            Text("\(score)").font(.title3.monospacedDigit().bold())
            let away = matchState.config.matchLength - score
            Text(away > 0 ? "\(away) away" : "WIN").font(.caption2)
                .foregroundColor(away > 0 ? .secondary : .green)
        }
    }
}

// MARK: - Coach Panel

struct CoachPanel: View {
    @ObservedObject var engine: GameEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "brain.head.profile").foregroundColor(.purple)
                Text("Coach").font(.headline)
                Spacer()
                Text(engine.settings.coachMode.rawValue).font(.caption).foregroundColor(.secondary)
            }

            if engine.isAnalyzing {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.8)
                    Text("Analyzing...").font(.caption).foregroundColor(.secondary)
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(engine.messageLog) { msg in
                            messageRow(msg).id(msg.id)
                        }
                    }
                }
                .frame(maxHeight: 120)
                .onChange(of: engine.messageLog.count) { _ in
                    if let last = engine.messageLog.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if let analysis = engine.lastAnalysis, engine.showingAnalysis {
                analysisCard(analysis)
            }
        }
        .padding(10)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 1)
    }

    private func messageRow(_ msg: CoachMessage) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Group {
                switch msg.type {
                case .system: Image(systemName: "info.circle").foregroundColor(.blue)
                case .aiMove: Image(systemName: "desktopcomputer").foregroundColor(.orange)
                case .coaching: Image(systemName: "lightbulb").foregroundColor(.purple)
                case .error: Image(systemName: "exclamationmark.triangle").foregroundColor(.red)
                }
            }.font(.caption2)
            Text(msg.text).font(.caption)
                .foregroundColor(msg.type == .coaching ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func analysisCard(_ analysis: MoveAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(analysis.classification.rawValue.capitalized).font(.caption.bold())
                    .foregroundColor(classificationColor(analysis.classification))
                Spacer()
                Button { engine.showingAnalysis = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Played").font(.caption2).foregroundColor(.secondary)
                    Text(analysis.chosenPlay).font(.system(.caption, design: .monospaced))
                }
                VStack(alignment: .leading) {
                    Text("Best").font(.caption2).foregroundColor(.secondary)
                    Text(analysis.bestPlay).font(.system(.caption, design: .monospaced)).foregroundColor(.green)
                }
                VStack(alignment: .leading) {
                    Text("Loss").font(.caption2).foregroundColor(.secondary)
                    Text(String(format: "%.3f", analysis.equityLoss))
                        .font(.system(.caption, design: .monospaced)).foregroundColor(.red)
                }
            }
            Text(analysis.explanation).font(.caption).fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    private func classificationColor(_ cls: MoveClassification) -> Color {
        switch cls {
        case .excellent, .good: return .green
        case .inaccuracy: return .orange
        case .mistake: return .red
        case .blunder: return .red
        }
    }
}
