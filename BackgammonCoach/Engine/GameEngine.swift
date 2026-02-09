import Foundation
import Combine
import SwiftUI

// MARK: - Game Phase

enum GamePhase: Equatable {
    case notStarted
    case openingRoll  // Both players rolling one die to determine who starts
    case rolling
    case moving
    case cubeOffered(by: Player)
    case analyzing
    case gameOver(winner: Player, multiplier: Int)
    case matchOver(winner: Player)
}

// MARK: - Coach Message

struct CoachMessage: Identifiable {
    let id = UUID()
    let type: MessageType
    let text: String
    let timestamp = Date()

    enum MessageType { case system, aiMove, coaching, error }

    static func system(_ t: String) -> CoachMessage { CoachMessage(type: .system, text: t) }
    static func aiMove(_ t: String) -> CoachMessage { CoachMessage(type: .aiMove, text: t) }
    static func coaching(_ t: String) -> CoachMessage { CoachMessage(type: .coaching, text: t) }
    static func error(_ t: String) -> CoachMessage { CoachMessage(type: .error, text: t) }
}

// MARK: - Game Engine

@MainActor
class GameEngine: ObservableObject {
    @Published var board: BoardState
    @Published var phase: GamePhase = .notStarted
    @Published var legalPlays: [Play] = []
    @Published var currentTurnMoves: [CheckerMove] = []
    @Published var pendingDice: Dice?
    @Published var remainingDice: [Int] = []  // Ordered: first element is next move to use
    @Published var aiDice: Dice?  // AI's current dice roll (shown during AI turn)
    @Published var lastAIPlay: Play?  // The AI's last play (for display)
    @Published var highlightedMoveFrom: Int?  // Point being moved FROM (for animation)
    @Published var highlightedMoveTo: Int?  // Point being moved TO (for animation)
    @Published var currentAIMoveIndex: Int = 0  // Which move in the sequence (1-based when displayed)
    @Published var totalAIMoves: Int = 0  // Total moves in AI's play
    @Published var currentAIMoveDescription: String = ""  // e.g., "13/9"
    @Published var lastAnalysis: MoveAnalysis?
    @Published var showingAnalysis: Bool = false
    @Published var isAnalyzing: Bool = false
    @Published var gameRecord: GameRecord
    @Published var messageLog: [CoachMessage] = []
    @Published var aiThinking: Bool = false
    @Published var matchState: MatchState
    @Published var matchConfig: MatchConfig

    // Opening roll state
    @Published var openingRollWhite: Int? = nil  // White's opening die
    @Published var openingRollBlack: Int? = nil  // Black's opening die

    let settings: AppSettings
    let humanPlayer: Player

    private let gnuBg: GNUBgService
    private let claude: ClaudeAnalysisService
    private var boardBeforeTurn: BoardState

    init(settings: AppSettings) {
        let initial = BoardState.newGame()
        self.board = initial
        self.boardBeforeTurn = initial
        self.gameRecord = GameRecord()
        self.settings = settings
        self.humanPlayer = settings.humanColor.player

        let config = MatchConfig.money()
        self.matchConfig = config
        self.matchState = MatchState(config: config)

        self.gnuBg = GNUBgService(baseURL: URL(string: settings.gnuBgServerURL)!)
        self.claude = ClaudeAnalysisService(apiKey: settings.claudeAPIKey)
    }

    // MARK: - New Game / Match

    func startNewMatch(config: MatchConfig) {
        matchConfig = config
        matchState = MatchState(config: config)
        startNewGame()
    }

    func startNewGame() {
        board = .newGame()
        phase = .openingRoll
        gameRecord = GameRecord()
        legalPlays = []
        currentTurnMoves = []
        messageLog = []
        lastAnalysis = nil
        showingAnalysis = false
        openingRollWhite = nil
        openingRollBlack = nil
        pendingDice = nil
        aiDice = nil

        addMessage(.system("Opening roll..."))

        // Animate the opening roll sequence
        Task {
            // Roll white's die first
            try? await Task.sleep(nanoseconds: 300_000_000)
            let white = Int.random(in: 1...6)
            openingRollWhite = white

            // Roll black's die
            try? await Task.sleep(nanoseconds: 400_000_000)
            let black = Int.random(in: 1...6)
            openingRollBlack = black

            // Check for tie
            if white == black {
                addMessage(.system("Both rolled \(white). Rolling again..."))
                try? await Task.sleep(nanoseconds: 800_000_000)
                startNewGame()
                return
            }

            // Determine winner and start game
            try? await Task.sleep(nanoseconds: 500_000_000)
            board.currentPlayer = white > black ? .white : .black
            let openingDice = Dice(die1: max(white, black), die2: min(white, black))
            addMessage(.system("\(board.currentPlayer.displayName) wins opening roll and plays \(white)-\(black)"))

            // Clear opening roll display before starting the turn
            try? await Task.sleep(nanoseconds: 300_000_000)
            openingRollWhite = nil
            openingRollBlack = nil

            if board.currentPlayer == humanPlayer {
                beginHumanTurn(dice: openingDice)
            } else {
                beginAITurn(dice: openingDice)
            }
        }
    }

    // MARK: - Human Turn

    func rollDice() {
        guard phase == .rolling, board.currentPlayer == humanPlayer else { return }
        beginHumanTurn(dice: Dice.roll())
    }

    func swapDiceOrder() {
        guard phase == .moving, remainingDice.count == 2 else { return }
        remainingDice = [remainingDice[1], remainingDice[0]]
    }

    private func beginHumanTurn(dice: Dice) {
        pendingDice = dice
        boardBeforeTurn = board
        remainingDice = dice.movesAvailable
        currentTurnMoves = []
        legalPlays = MoveGenerator.legalPlays(board: board, dice: dice)

        if legalPlays.isEmpty || (legalPlays.count == 1 && legalPlays[0].moves.isEmpty) {
            addMessage(.system("No legal moves. Turn skipped."))
            completeTurn(play: Play(moves: []))
            return
        }
        phase = .moving
    }

    /// Called when user taps a checker. Uses the first remaining die to move.
    func selectPoint(_ point: Int) {
        guard phase == .moving, let firstDie = remainingDice.first else { return }
        let player = humanPlayer
        let barPoint = player == .white ? 0 : 25

        // If player has pieces on bar, they MUST click on the bar to enter
        if board.bar[player.barIndex] > 0 {
            // Only allow clicking on the bar point
            guard point == barPoint else { return }
        } else {
            // Normal move - verify there's a checker at this point
            guard board.checkersAt(point: point, for: player) > 0 else { return }
        }

        // Find a move from this point using the FIRST die only
        let moves = MoveGenerator.generateSingleMoves(board: board, player: player, die: firstDie)
        if let move = moves.first(where: { $0.from == point }) {
            applyCheckerMove(move)
        }
        // If no legal move with first die from this point, do nothing
    }

    /// Legacy method - now selectPoint handles moves directly using first die
    func selectDestination(_ point: Int) {
        // This is no longer used in the new interaction model
        // Kept for compatibility but does nothing
    }

    private func applyCheckerMove(_ move: CheckerMove) {
        board = board.applying(move, for: humanPlayer)
        currentTurnMoves.append(move)
        if let idx = remainingDice.firstIndex(of: move.dieUsed) {
            remainingDice.remove(at: idx)
        }
        // Turn now requires explicit confirmation via confirmTurn()
        // No auto-complete - user must press confirm button
    }

    func undoLastMove() {
        guard phase == .moving, !currentTurnMoves.isEmpty else { return }
        let movesToReplay = Array(currentTurnMoves.dropLast())
        board = boardBeforeTurn
        currentTurnMoves = []
        remainingDice = pendingDice?.movesAvailable ?? []
        for move in movesToReplay {
            board = board.applying(move, for: humanPlayer)
            currentTurnMoves.append(move)
            if let idx = remainingDice.firstIndex(of: move.dieUsed) {
                remainingDice.remove(at: idx)
            }
        }
    }

    /// Whether the current turn is ready to be confirmed (all dice used or no more legal moves)
    var turnReadyToConfirm: Bool {
        guard phase == .moving else { return false }
        if remainingDice.isEmpty { return true }
        let furtherMoves = remainingDice.flatMap {
            MoveGenerator.generateSingleMoves(board: board, player: humanPlayer, die: $0)
        }
        return furtherMoves.isEmpty
    }

    /// Whether the human player has pieces on the bar that must be entered
    var humanHasBarPieces: Bool {
        phase == .moving && board.bar[humanPlayer.barIndex] > 0
    }

    func confirmTurn() {
        guard phase == .moving else { return }
        completeTurn(play: Play(moves: currentTurnMoves))
    }

    // MARK: - AI Turn

    private func beginAITurn(dice: Dice) {
        aiThinking = true
        aiDice = dice  // Show the AI's dice
        lastAIPlay = nil
        highlightedMoveFrom = nil
        highlightedMoveTo = nil
        currentAIMoveIndex = 0
        totalAIMoves = 0
        currentAIMoveDescription = ""
        let aiPlayer = humanPlayer.opponent

        Task {
            do {
                let evaluation = try await gnuBg.evaluate(board: board, dice: dice,
                                                           ply: settings.aiDifficulty)
                var bestPlay = GNUBgService.convertPlay(evaluation.best_play)

                // Validate the play - if GNU BG returns invalid moves, use our own generator
                if !isPlayValid(bestPlay, for: aiPlayer, dice: dice) {
                    addMessage(.system("Invalid move from server, using fallback."))
                    let legalPlays = MoveGenerator.legalPlays(board: board, dice: dice)
                    bestPlay = legalPlays.first ?? Play(moves: [])
                }

                aiThinking = false
                lastAIPlay = bestPlay
                totalAIMoves = bestPlay.moves.count

                // Animate each move individually
                let before = board
                for (index, move) in bestPlay.moves.enumerated() {
                    // Update move info
                    currentAIMoveIndex = index + 1
                    currentAIMoveDescription = move.description

                    // Highlight the move
                    highlightedMoveFrom = move.from
                    highlightedMoveTo = move.to

                    // Brief pause to show highlight (scaled by aiMoveDelay setting)
                    let highlightTime = UInt64(settings.aiMoveDelay * 0.3 * 1_000_000_000)
                    try await Task.sleep(nanoseconds: highlightTime)

                    // Apply the move
                    board = board.applying(move, for: aiPlayer)

                    // Brief pause after move
                    let postMoveTime = UInt64(settings.aiMoveDelay * 0.2 * 1_000_000_000)
                    try await Task.sleep(nanoseconds: postMoveTime)
                }

                // Clear highlights
                highlightedMoveFrom = nil
                highlightedMoveTo = nil
                currentAIMoveDescription = ""

                var record = TurnRecord(player: aiPlayer, dice: dice, chosenPlay: bestPlay,
                                        boardBefore: before, boardAfter: board)
                record.gnuEquityOfBest = evaluation.best_equity
                record.gnuEquityOfChosen = evaluation.best_equity
                record.equityLoss = 0
                record.classification = .excellent
                gameRecord.turns.append(record)

                addMessage(.aiMove("AI plays: \(bestPlay.notation)"))

                // Explain AI move if setting is enabled
                if settings.explainAIMoves && !bestPlay.moves.isEmpty {
                    Task {
                        do {
                            let explanation = try await claude.explainAIMove(
                                board: before,
                                dice: dice,
                                play: bestPlay,
                                equity: evaluation.best_equity
                            )
                            addMessage(.coaching("💡 \(explanation)"))
                        } catch {
                            // Silently fail - explanation is optional
                        }
                    }
                }

                // Brief pause after all moves
                try await Task.sleep(nanoseconds: 500_000_000)
                aiDice = nil
                pendingDice = nil  // Clear human's old dice so Roll button appears
                currentAIMoveIndex = 0
                totalAIMoves = 0

                if board.isGameOver {
                    endGame()
                } else {
                    board.currentPlayer = humanPlayer
                    phase = .rolling
                }
            } catch {
                addMessage(.error("AI error: \(error.localizedDescription). Using fallback."))
                aiThinking = false
                aiDice = nil
                pendingDice = nil
                highlightedMoveFrom = nil
                highlightedMoveTo = nil
                currentAIMoveIndex = 0
                totalAIMoves = 0
                currentAIMoveDescription = ""
                playValidatedAIMove(dice: dice, player: aiPlayer)
            }
        }
    }

    /// Validate that a play is legal for the given player and dice
    private func isPlayValid(_ play: Play, for player: Player, dice: Dice) -> Bool {
        var checkBoard = board

        for move in play.moves {
            // Check bar rule: if player has pieces on bar, must enter from bar
            let barCount = checkBoard.bar[player.barIndex]
            if barCount > 0 {
                let barPoint = player == .white ? 0 : 25
                if move.from != barPoint {
                    addMessage(.error("Invalid: Must enter from bar first"))
                    return false
                }
            }

            // Get legal moves for this die on current board state
            let legalMoves = MoveGenerator.generateSingleMoves(board: checkBoard, player: player, die: move.dieUsed)

            // Check if the move is legal
            guard legalMoves.contains(where: { $0.from == move.from && $0.to == move.to }) else {
                addMessage(.error("Invalid move: \(move.from) -> \(move.to)"))
                return false
            }

            // Apply move to check board for next iteration
            checkBoard = checkBoard.applying(move, for: player)
        }
        return true
    }

    /// Play a validated move using our own move generator with heuristic evaluation
    private func playValidatedAIMove(dice: Dice, player: Player) {
        var tempBoard = board
        tempBoard.currentPlayer = player
        let plays = MoveGenerator.legalPlays(board: tempBoard, dice: dice)

        // Evaluate plays with heuristics and pick the best one
        let play = plays.max(by: { evaluatePlay($0, for: player) < evaluatePlay($1, for: player) }) ?? Play(moves: [])

        Task {
            lastAIPlay = play
            totalAIMoves = play.moves.count
            let before = board

            // Animate each move individually (timing scaled by aiMoveDelay)
            for (index, move) in play.moves.enumerated() {
                currentAIMoveIndex = index + 1
                currentAIMoveDescription = move.description
                highlightedMoveFrom = move.from
                highlightedMoveTo = move.to
                let highlightTime = UInt64(settings.aiMoveDelay * 0.3 * 1_000_000_000)
                try? await Task.sleep(nanoseconds: highlightTime)
                board = board.applying(move, for: player)
                let postMoveTime = UInt64(settings.aiMoveDelay * 0.2 * 1_000_000_000)
                try? await Task.sleep(nanoseconds: postMoveTime)
            }

            highlightedMoveFrom = nil
            highlightedMoveTo = nil
            currentAIMoveDescription = ""

            let record = TurnRecord(player: player, dice: dice, chosenPlay: play,
                                    boardBefore: before, boardAfter: board)
            gameRecord.turns.append(record)
            addMessage(.aiMove("AI plays: \(play.notation)"))

            // Explain AI move if setting is enabled
            if settings.explainAIMoves && !play.moves.isEmpty {
                Task {
                    do {
                        let explanation = try await claude.explainAIMove(
                            board: before,
                            dice: dice,
                            play: play,
                            equity: 0.0  // No equity available in fallback mode
                        )
                        addMessage(.coaching("💡 \(explanation)"))
                    } catch {
                        // Silently fail - explanation is optional
                    }
                }
            }

            // Brief pause after all moves
            try? await Task.sleep(nanoseconds: 500_000_000)
            aiDice = nil
            pendingDice = nil
            currentAIMoveIndex = 0
            totalAIMoves = 0

            if board.isGameOver {
                endGame()
            } else {
                board.currentPlayer = humanPlayer
                phase = .rolling
            }
        }
    }


    // MARK: - Turn Completion & Analysis

    private func completeTurn(play: Play) {
        guard let dice = pendingDice else { return }
        let player = humanPlayer

        var record = TurnRecord(player: player, dice: dice, chosenPlay: play,
                                boardBefore: boardBeforeTurn, boardAfter: board)
        gameRecord.turns.append(record)

        // Run analysis based on coach mode
        if settings.isAnyCoachingEnabled && !play.moves.isEmpty {
            let capturedBoard = boardBeforeTurn
            let capturedDice = dice
            let capturedPlay = play
            let recordId = record.id

            Task {
                await analyzePlayerMove(recordId: recordId, board: capturedBoard,
                                        dice: capturedDice, chosenPlay: capturedPlay)
            }
        }

        if board.isGameOver {
            endGame()
            return
        }

        board.currentPlayer = humanPlayer.opponent
        let aiDice = Dice.roll()
        addMessage(.system("AI rolls: \(aiDice.die1)-\(aiDice.die2)"))
        beginAITurn(dice: aiDice)
    }

    private func analyzePlayerMove(recordId: UUID, board: BoardState,
                                    dice: Dice, chosenPlay: Play) async {
        do {
            let evaluation = try await gnuBg.evaluate(board: board, dice: dice,
                                                       ply: max(settings.aiDifficulty, 2))
            let bestPlay = GNUBgService.convertPlay(evaluation.best_play)

            var equityOfChosen: Double? = nil

            // Try to find the chosen play in the ranked list
            // Note: Move ORDER within a turn doesn't matter in backgammon - only the final position
            for ranked in evaluation.all_plays {
                let rPlay = GNUBgService.convertPlay(ranked.play)

                // Try exact match first
                if rPlay == chosenPlay {
                    equityOfChosen = ranked.equity
                    break
                }

                // Try matching by notation (more forgiving)
                if rPlay.notation == chosenPlay.notation {
                    equityOfChosen = ranked.equity
                    break
                }

                // Try matching by move coordinates only (ignoring hit/bearoff flags)
                if rPlay.moves.count == chosenPlay.moves.count {
                    let coordsMatch = zip(rPlay.moves, chosenPlay.moves).allSatisfy { r, c in
                        r.from == c.from && r.to == c.to
                    }
                    if coordsMatch {
                        equityOfChosen = ranked.equity
                        break
                    }
                }

                // Try matching by sorted coordinates (order doesn't matter in backgammon)
                if rPlay.moves.count == chosenPlay.moves.count {
                    let rSorted = rPlay.moves.map { ($0.from, $0.to) }.sorted { ($0.0, $0.1) < ($1.0, $1.1) }
                    let cSorted = chosenPlay.moves.map { ($0.from, $0.to) }.sorted { ($0.0, $0.1) < ($1.0, $1.1) }
                    let sortedMatch = zip(rSorted, cSorted).allSatisfy { $0 == $1 }
                    if sortedMatch {
                        equityOfChosen = ranked.equity
                        break
                    }
                }
            }

            // If not found in ranked list, estimate equity loss
            // Use the worst ranked play's equity as a conservative estimate
            if equityOfChosen == nil {
                if let worstRanked = evaluation.all_plays.last {
                    // Assume the move is at least as bad as the worst listed option
                    equityOfChosen = worstRanked.equity - 0.02
                } else {
                    equityOfChosen = evaluation.best_equity - 0.05 // Default penalty
                }
                addMessage(.system("Move not in top \(evaluation.all_plays.count) - estimating equity"))
            }

            let chosenEquity = equityOfChosen!  // Safe: always set above
            let equityLoss = evaluation.best_equity - chosenEquity
            let classification = MoveClassification(equityLoss: equityLoss)

            // Update the stored record
            if let idx = gameRecord.turns.firstIndex(where: { $0.id == recordId }) {
                gameRecord.turns[idx].gnuBestPlay = bestPlay
                gameRecord.turns[idx].gnuEquityOfBest = evaluation.best_equity
                gameRecord.turns[idx].gnuEquityOfChosen = chosenEquity
                gameRecord.turns[idx].equityLoss = equityLoss
                gameRecord.turns[idx].classification = classification
            }

            // Call Claude only if loss exceeds threshold
            let threshold = settings.equityLossThreshold
            if equityLoss >= threshold && settings.isRealTimeCoachingEnabled {
                isAnalyzing = true
                let analysis = try await claude.analyzeMoveChoice(
                    board: board, dice: dice,
                    chosenPlay: chosenPlay, bestPlay: bestPlay,
                    equityOfChosen: chosenEquity, equityOfBest: evaluation.best_equity)

                self.lastAnalysis = analysis
                self.showingAnalysis = true
                self.isAnalyzing = false

                let icon = classification == .blunder ? "🔴" :
                           classification == .mistake ? "🟡" : "🟠"
                addMessage(.coaching(
                    "\(icon) \(classification.rawValue.capitalized): \(analysis.explanation)"))
            } else {
                isAnalyzing = false
                if classification == .excellent && Bool.random() {
                    addMessage(.coaching("✅ Good move."))
                }
            }
        } catch {
            isAnalyzing = false
            // Silently fail analysis — game continues
        }
    }

    // MARK: - Doubling Cube

    var canOfferCube: Bool {
        guard phase == .rolling, board.currentPlayer == humanPlayer else { return false }
        if matchState.isCrawford { return false }
        return board.cube.canDouble(humanPlayer)
    }

    func offerDouble() {
        guard canOfferCube else { return }
        phase = .cubeOffered(by: humanPlayer)

        Task {
            do {
                let cubeEval = try await gnuBg.evaluateCube(board: board, cubeValue: board.cube.value)
                if cubeEval.recommendation.contains("pass") {
                    addMessage(.system("AI declines the cube."))
                    endGame(resignation: true, winner: humanPlayer)
                } else {
                    board.cube.value *= 2
                    board.cube.owner = humanPlayer.opponent
                    addMessage(.system("AI takes at \(board.cube.value)."))
                    phase = .rolling
                }
            } catch {
                board.cube.value *= 2
                board.cube.owner = humanPlayer.opponent
                addMessage(.system("AI takes at \(board.cube.value)."))
                phase = .rolling
            }
        }
    }

    func respondToCube(accept: Bool) {
        guard case .cubeOffered(let offeredBy) = phase, offeredBy != humanPlayer else { return }
        if accept {
            board.cube.value *= 2
            board.cube.owner = humanPlayer
            addMessage(.system("You take at \(board.cube.value)."))
            phase = .rolling
        } else {
            addMessage(.system("You decline the cube."))
            endGame(resignation: true, winner: offeredBy)
        }
    }

    // MARK: - Game End

    private func endGame(resignation: Bool = false, winner: Player? = nil) {
        let gameWinner = winner ?? board.winner ?? humanPlayer
        let multiplier = resignation ? 1 : board.gameResult
        let result = GameResult(winner: gameWinner, multiplier: multiplier,
                                cubeValue: board.cube.value,
                                points: multiplier * board.cube.value,
                                wasResignation: resignation)
        gameRecord.result = result
        gameRecord.endDate = Date()

        // Record win/loss stats for current AI difficulty
        settings.recordGameResult(won: gameWinner == humanPlayer, multiplier: multiplier)

        // Update match state
        if matchConfig.gameType == .match {
            matchState.recordGameResult(winner: gameWinner, multiplier: multiplier,
                                        cubeValue: board.cube.value)
            if matchState.isMatchOver {
                phase = .matchOver(winner: matchState.matchWinner!)
                addMessage(.system("Match over! \(matchState.matchWinner!.displayName) wins \(matchState.score[0])-\(matchState.score[1])"))
            } else {
                phase = .gameOver(winner: gameWinner, multiplier: multiplier)
                addMessage(.system("Score: \(matchState.score[0])-\(matchState.score[1])"))
                if matchState.isCrawford {
                    addMessage(.system("Crawford game next — no doubling."))
                }
            }
        } else {
            phase = .gameOver(winner: gameWinner, multiplier: multiplier)
        }

        let resultName = multiplier == 3 ? "backgammon" : multiplier == 2 ? "gammon" : "single game"
        addMessage(.system("\(gameWinner.displayName) wins a \(resultName)! (\(result.points) pts)"))

        // Post-game analysis
        if settings.isAnyCoachingEnabled && settings.postGameAnalysisEnabled {
            runPostGameAnalysis()
        }
    }

    @Published var analysisReady: Bool = false  // Triggers automatic analysis sheet

    private func runPostGameAnalysis() {
        isAnalyzing = true
        addMessage(.system("Analyzing your game..."))

        Task {
            do {
                let analysis = try await claude.analyzeGame(turns: gameRecord.turns)
                gameRecord.analysis = analysis
                isAnalyzing = false
                analysisReady = true  // Signal to show analysis view
                addMessage(.coaching("📊 Game analysis ready! Tap to view full report."))
            } catch {
                isAnalyzing = false
                addMessage(.error("Could not generate analysis: \(error.localizedDescription)"))
            }
        }
    }

    func startNextGameInMatch() {
        guard matchConfig.gameType == .match, !matchState.isMatchOver else { return }
        startNewGame()
    }

    // MARK: - Helpers

    private func addMessage(_ msg: CoachMessage) {
        messageLog.append(msg)
        if messageLog.count > 50 { messageLog.removeFirst(messageLog.count - 50) }
    }

    // MARK: - Heuristic Play Evaluation (fallback when GNU BG unavailable)

    /// Evaluate a play using simple backgammon heuristics (higher = better)
    private func evaluatePlay(_ play: Play, for player: Player) -> Double {
        let resultBoard = board.applying(play, for: player)
        var score: Double = 0

        // 1. Pip count improvement (moving pieces forward is good)
        let beforePips = player == .white ? board.pipCount.white : board.pipCount.black
        let afterPips = player == .white ? resultBoard.pipCount.white : resultBoard.pipCount.black
        score += Double(beforePips - afterPips) * 0.5

        // 2. Hitting blots is valuable
        let hits = play.moves.filter(\.isHit).count
        score += Double(hits) * 15

        // 3. Making points (having 2+ checkers) is valuable
        for point in 1...24 {
            let before = board.checkersAt(point: point, for: player)
            let after = resultBoard.checkersAt(point: point, for: player)
            if before < 2 && after >= 2 {
                // Made a new point
                score += 8
                // Home board points are more valuable
                if player.homeBoard.contains(point) {
                    score += 5
                }
                // Points 4, 5, 6 (relative to home) are the golden points
                let relativePoint = player == .white ? point : 25 - point
                if relativePoint >= 4 && relativePoint <= 6 {
                    score += 3
                }
            }
        }

        // 4. Leaving blots is bad
        for point in 1...24 {
            let before = board.checkersAt(point: point, for: player)
            let after = resultBoard.checkersAt(point: point, for: player)
            if after == 1 && before != 1 {
                // Created a blot
                score -= 8
                // Blots in opponent's home board are very dangerous
                let opponentHome = player.opponent.homeBoard
                if opponentHome.contains(point) {
                    score -= 10
                }
            }
        }

        // 5. Bearing off is very valuable
        let boreOff = play.moves.filter(\.isBearOff).count
        score += Double(boreOff) * 20

        // 6. Entering from bar reduces penalty
        let barEntries = play.moves.filter { $0.from == 0 || $0.from == 25 }.count
        score += Double(barEntries) * 5

        // 7. Priming (consecutive points) is valuable
        score += evaluatePrimeStrength(resultBoard, for: player)

        // 8. Anchors in opponent's home board are valuable (for back game / holding)
        let opponentHome = player.opponent.homeBoard
        for point in opponentHome {
            if resultBoard.checkersAt(point: point, for: player) >= 2 {
                score += 4
            }
        }

        return score
    }

    /// Evaluate the strength of prime formations (consecutive blocked points)
    private func evaluatePrimeStrength(_ board: BoardState, for player: Player) -> Double {
        var score: Double = 0
        var consecutivePoints = 0
        var maxPrime = 0

        for point in 1...24 {
            if board.checkersAt(point: point, for: player) >= 2 {
                consecutivePoints += 1
                maxPrime = max(maxPrime, consecutivePoints)
            } else {
                consecutivePoints = 0
            }
        }

        // A 4-prime is good, 5-prime is great, 6-prime is excellent
        if maxPrime >= 6 { score += 25 }
        else if maxPrime >= 5 { score += 15 }
        else if maxPrime >= 4 { score += 8 }
        else if maxPrime >= 3 { score += 3 }

        return score
    }
}
