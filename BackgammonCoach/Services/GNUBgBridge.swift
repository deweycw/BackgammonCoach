import Foundation

// MARK: - GNU BG Response Types

struct GnuBgEvaluationResult: Codable {
    let best_play: GnuBgPlayResponse
    let best_equity: Double
    let all_plays: [GnuBgRankedPlay]
}

struct GnuBgPlayResponse: Codable {
    let moves: [GnuBgMoveResponse]
    let notation: String
}

struct GnuBgMoveResponse: Codable {
    let from_point: Int
    let to_point: Int
    let die_used: Int
    let is_hit: Bool
    let is_bear_off: Bool
}

struct GnuBgRankedPlay: Codable {
    let rank: Int
    let play: GnuBgPlayResponse
    let equity: Double
    let win_probability: Double
    let equity_difference: Double
}

struct GnuBgCubeEvaluation: Codable {
    let recommendation: String
    let no_double_equity: Double
    let double_take_equity: Double
    let double_pass_equity: Double
    let proper_cube_action: String
    let win_probability: Double
    let gammon_threat: Double
}

// MARK: - GNU BG Service

actor GNUBgService {
    private let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func evaluate(board: BoardState, dice: Dice, ply: Int = 2) async throws -> GnuBgEvaluationResult {
        var request = URLRequest(url: baseURL.appendingPathComponent("evaluate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "points": Array(board.points[1...24]),
            "bar": [board.bar[0], board.bar[1]],
            "borne_off": [board.borneOff[0], board.borneOff[1]],
            "dice": [dice.die1, dice.die2],
            "player": board.currentPlayer.displayName.lowercased(),
            "ply": ply
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw GnuBgError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(GnuBgEvaluationResult.self, from: data)
    }

    func evaluateCube(board: BoardState, cubeValue: Int = 1, ply: Int = 2) async throws -> GnuBgCubeEvaluation {
        var request = URLRequest(url: baseURL.appendingPathComponent("cube"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "points": Array(board.points[1...24]),
            "bar": [board.bar[0], board.bar[1]],
            "borne_off": [board.borneOff[0], board.borneOff[1]],
            "cube_value": cubeValue,
            "cube_owner": board.cube.owner?.displayName.lowercased() ?? "centered",
            "player": board.currentPlayer.displayName.lowercased(),
            "ply": ply
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw GnuBgError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(GnuBgCubeEvaluation.self, from: data)
    }

    func checkHealth() async throws -> Bool {
        let url = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return false
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let ready = json["engine_ready"] as? Bool {
            return ready
        }
        return true
    }

    func shouldFlagMove(chosenEquity: Double, bestEquity: Double, threshold: Double = 0.04) -> Bool {
        (bestEquity - chosenEquity) >= threshold
    }

    /// Convert a GNU BG play response into our Play type
    static func convertPlay(_ gnuPlay: GnuBgPlayResponse) -> Play {
        let moves = gnuPlay.moves.map { m in
            CheckerMove(from: m.from_point, to: m.to_point,
                        dieUsed: m.die_used, isHit: m.is_hit, isBearOff: m.is_bear_off)
        }
        return Play(moves: moves)
    }
}

enum GnuBgError: Error, LocalizedError {
    case serverError(Int)
    case notReady

    var errorDescription: String? {
        switch self {
        case .serverError(let code): return "GNU BG server error (HTTP \(code))"
        case .notReady: return "GNU BG engine not ready"
        }
    }
}
