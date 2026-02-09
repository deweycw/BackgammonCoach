import Foundation

// MARK: - Analysis Service

actor ClaudeAnalysisService {
    private let apiKey: String
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-sonnet-4-5-20250929"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Real-Time Move Analysis

    func analyzeMoveChoice(
        board: BoardState, dice: Dice,
        chosenPlay: Play, bestPlay: Play,
        equityOfChosen: Double, equityOfBest: Double
    ) async throws -> MoveAnalysis {
        let boardJSON = (try? String(data: board.toAnalysisJSON(), encoding: .utf8)) ?? "{}"
        let equityLoss = equityOfBest - equityOfChosen

        let prompt = """
        You are an expert backgammon coach analyzing a position.

        IMPORTANT BACKGAMMON RULES:
        - A player completes their ENTIRE turn before the opponent can respond
        - Move order within a turn does NOT matter - only the final position counts
        - The opponent CANNOT hit you between your moves - they respond after your full turn
        - If two plays reach the same final position, they are strategically equivalent

        POSITION (positive = player's checkers, negative = opponent's):
        \(boardJSON)

        DICE ROLLED: \(dice.die1)-\(dice.die2)
        PLAYER CHOSE: \(chosenPlay.notation)
        BEST PLAY:    \(bestPlay.notation)
        EQUITY OF CHOSEN: \(String(format: "%.4f", equityOfChosen))
        EQUITY OF BEST:   \(String(format: "%.4f", equityOfBest))
        EQUITY LOSS:      \(String(format: "%.4f", equityLoss))

        Analyze the FINAL POSITIONS resulting from each play. Focus on concrete differences like:
        - Different points made or broken
        - Blots left vs safe checkers
        - Racing position changes
        - Blocking/priming differences

        Provide a concise coaching explanation. Respond ONLY with valid JSON:
        {
            "chosenPlay": "\(chosenPlay.notation)",
            "bestPlay": "\(bestPlay.notation)",
            "equityLoss": \(equityLoss),
            "classification": "\(MoveClassification(equityLoss: equityLoss).rawValue)",
            "explanation": "2-3 sentence coaching explanation",
            "positionalThemes": ["theme1", "theme2"]
        }
        """
        return try await callClaude(prompt: prompt)
    }

    // MARK: - Post-Game Analysis

    func analyzeGame(turns: [TurnRecord]) async throws -> GameAnalysis {
        let interestingTurns = turns.filter { ($0.equityLoss ?? 0) >= 0.02 }
        let turnSummaries = interestingTurns.enumerated().map { _, turn -> String in
            let idx = turns.firstIndex(where: { $0.id == turn.id }).map { $0 + 1 } ?? 0
            let loss = turn.equityLoss.map { String(format: "%.3f", $0) } ?? "?"
            return "Turn \(idx): Dice \(turn.dice.die1)-\(turn.dice.die2), " +
                   "Played \(turn.chosenPlay.notation), " +
                   "Best \(turn.gnuBestPlay?.notation ?? "?"), Loss: \(loss)"
        }.joined(separator: "\n")

        let totalErrors = turns.compactMap(\.equityLoss).reduce(0, +)
        let blunders = turns.filter { $0.classification == .blunder }.count

        let prompt = """
        You are an expert backgammon coach reviewing a completed game.

        GAME SUMMARY:
        - Total turns: \(turns.count)
        - Total equity lost: \(String(format: "%.3f", totalErrors))
        - Blunders: \(blunders)
        - Result: \(turns.last?.boardAfter.winner?.displayName ?? "incomplete")

        KEY ERRORS:
        \(turnSummaries)

        Respond ONLY with valid JSON:
        {
            "summary": "Brief game narrative",
            "criticalPositions": [{"turnNumber": 1, "equityLoss": 0.1, "explanation": "Why"}],
            "overallRating": "Beginner to Expert",
            "strengths": ["what went well"],
            "weaknesses": ["patterns to improve"],
            "keyLesson": "One actionable takeaway"
        }
        """
        return try await callClaude(prompt: prompt)
    }

    // MARK: - Trend Analysis

    func analyzeTrends(gameStats: [GameStats]) async throws -> TrendAnalysis {
        let statsSummary = gameStats.enumerated().map { i, s in
            "Game \(i + 1): \(s.result), Errors: \(String(format: "%.3f", s.totalEquityLost)), Blunders: \(s.blunderCount)"
        }.joined(separator: "\n")

        let winCount = gameStats.filter(\.isWin).count
        let winRate = gameStats.isEmpty ? 0 : Double(winCount) / Double(gameStats.count)
        let avgLoss = gameStats.isEmpty ? 0 : gameStats.map(\.totalEquityLost).reduce(0, +) / Double(gameStats.count)

        let prompt = """
        You are an expert backgammon coach analyzing trends across games.

        RECENT GAMES:
        \(statsSummary)

        AGGREGATE:
        - Games: \(gameStats.count), Win rate: \(String(format: "%.0f%%", winRate * 100))
        - Avg equity lost: \(String(format: "%.3f", avgLoss))

        Respond ONLY with valid JSON:
        {
            "summary": "Overview of trends",
            "patterns": [{"pattern": "Description", "frequency": "How often", "impact": "Cost", "advice": "Fix"}],
            "recommendations": ["Top 3 things to practice"]
        }
        """
        return try await callClaude(prompt: prompt)
    }

    // MARK: - Explain AI Move

    func explainAIMove(
        board: BoardState,
        dice: Dice,
        play: Play,
        equity: Double
    ) async throws -> String {
        let boardJSON = (try? String(data: board.toAnalysisJSON(), encoding: .utf8)) ?? "{}"

        let prompt = """
        You are an expert backgammon coach explaining why a move is good.

        POSITION BEFORE MOVE (positive = white checkers, negative = black):
        \(boardJSON)

        DICE ROLLED: \(dice.die1)-\(dice.die2)
        MOVE PLAYED: \(play.notation)
        POSITION EQUITY: \(String(format: "%.3f", equity))

        Explain in 2-3 sentences why this is a good move. Focus on:
        - Strategic concepts (priming, blitzing, racing, holding, back game)
        - Tactical considerations (hitting, making points, safety, duplication)
        - Position-specific reasoning

        Be concise and educational. Respond ONLY with JSON: {"explanation": "Your explanation here"}
        """

        let response: [String: String] = try await callClaude(prompt: prompt)
        return response["explanation"] ?? "Good positional play."
    }

    // MARK: - Cube Decision

    func analyzeCubeDecision(
        board: BoardState,
        gnuCubeEquity: Double,
        gnuRecommendation: String,
        matchContext: String = ""
    ) async throws -> String {
        let boardJSON = (try? String(data: board.toAnalysisJSON(), encoding: .utf8)) ?? "{}"
        let prompt = """
        POSITION: \(boardJSON)
        \(matchContext)
        GNU BG: Equity \(String(format: "%.3f", gnuCubeEquity)), Recommendation: \(gnuRecommendation)

        Explain this cube decision in 3-4 sentences. Respond ONLY with JSON: {"explanation": "..."}
        """
        let response: [String: String] = try await callClaude(prompt: prompt)
        return response["explanation"] ?? "Unable to analyze."
    }

    // MARK: - API Call

    private func callClaude<T: Decodable>(prompt: String) async throws -> T {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": "You are an expert backgammon coach. Always respond with valid JSON only, no markdown or preamble.",
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AnalysisError.apiError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        let apiResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = apiResponse?["content"] as? [[String: Any]],
              let textBlock = content.first(where: { $0["type"] as? String == "text" }),
              let text = textBlock["text"] as? String else {
            throw AnalysisError.parseError("No text in response")
        }

        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleaned.data(using: .utf8) else {
            throw AnalysisError.parseError("Invalid UTF8")
        }
        return try JSONDecoder().decode(T.self, from: jsonData)
    }
}

enum AnalysisError: Error, LocalizedError {
    case apiError(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .apiError(let msg): return "API error: \(msg)"
        case .parseError(let msg): return "Parse error: \(msg)"
        }
    }
}
