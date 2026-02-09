import Foundation

struct MoveGenerator {

    static func legalPlays(board: BoardState, dice: Dice) -> [Play] {
        let player = board.currentPlayer
        if dice.isDoubles {
            return generateDoublesPlays(board: board, player: player, dieValue: dice.die1)
        } else {
            var allPlays = [Play]()
            var seenStates = Set<BoardState>()

            let plays1 = generateNonDoublesPlays(board: board, player: player, dice: [dice.die1, dice.die2])
            let plays2 = generateNonDoublesPlays(board: board, player: player, dice: [dice.die2, dice.die1])

            for play in plays1 + plays2 {
                let resultBoard = board.applying(play, for: player)
                if seenStates.insert(resultBoard).inserted {
                    allPlays.append(play)
                }
            }

            let maxMoves = allPlays.map(\.moves.count).max() ?? 0
            let filtered = allPlays.filter { $0.moves.count == maxMoves }

            if maxMoves == 1 {
                let largerDie = max(dice.die1, dice.die2)
                let usesLarger = filtered.filter { $0.moves[0].dieUsed == largerDie }
                if !usesLarger.isEmpty { return usesLarger }
            }

            return filtered
        }
    }

    // MARK: - Non-Doubles

    private static func generateNonDoublesPlays(
        board: BoardState, player: Player, dice: [Int]
    ) -> [Play] {
        guard !dice.isEmpty else { return [Play(moves: [])] }
        let currentDie = dice[0]
        let remainingDice = Array(dice.dropFirst())
        let singleMoves = generateSingleMoves(board: board, player: player, die: currentDie)

        if singleMoves.isEmpty {
            if remainingDice.isEmpty { return [Play(moves: [])] }
            return generateNonDoublesPlays(board: board, player: player, dice: remainingDice)
        }

        var plays = [Play]()
        for move in singleMoves {
            let newBoard = board.applying(move, for: player)
            let continuations = generateNonDoublesPlays(board: newBoard, player: player, dice: remainingDice)
            for cont in continuations {
                plays.append(Play(moves: [move] + cont.moves))
            }
        }
        return plays
    }

    // MARK: - Doubles

    private static func generateDoublesPlays(
        board: BoardState, player: Player, dieValue: Int
    ) -> [Play] {
        return generateDoublesRecursive(board: board, player: player,
                                         dieValue: dieValue, remaining: 4, movesSoFar: [])
    }

    private static func generateDoublesRecursive(
        board: BoardState, player: Player, dieValue: Int,
        remaining: Int, movesSoFar: [CheckerMove]
    ) -> [Play] {
        guard remaining > 0 else { return [Play(moves: movesSoFar)] }
        let singleMoves = generateSingleMoves(board: board, player: player, die: dieValue)
        if singleMoves.isEmpty { return [Play(moves: movesSoFar)] }

        var plays = [Play]()
        var seenStates = Set<BoardState>()
        for move in singleMoves {
            let newBoard = board.applying(move, for: player)
            if seenStates.insert(newBoard).inserted {
                let continuations = generateDoublesRecursive(
                    board: newBoard, player: player, dieValue: dieValue,
                    remaining: remaining - 1, movesSoFar: movesSoFar + [move])
                plays.append(contentsOf: continuations)
            }
        }
        let maxUsed = plays.map(\.moves.count).max() ?? 0
        return plays.filter { $0.moves.count == maxUsed }
    }

    // MARK: - Single Moves

    static func generateSingleMoves(
        board: BoardState, player: Player, die: Int
    ) -> [CheckerMove] {
        var moves = [CheckerMove]()
        let barCount = board.bar[player.barIndex]

        if barCount > 0 {
            let entryPoint = player == .white ? (25 - die) : die
            if board.isPointOpen(entryPoint, for: player) {
                let hit = board.isBlot(entryPoint, for: player)
                moves.append(CheckerMove(
                    from: player == .white ? 0 : 25,
                    to: entryPoint, dieUsed: die, isHit: hit, isBearOff: false))
            }
            return moves
        }

        for from in 1...24 {
            let checkers = player == .white ? max(0, board.points[from]) : max(0, -board.points[from])
            guard checkers > 0 else { continue }
            let to = from + (die * player.direction)

            if player == .white && to <= 0 && board.canBearOff(.white) {
                if to == 0 || isHighestChecker(board: board, player: .white, point: from) {
                    moves.append(CheckerMove(from: from, to: 0, dieUsed: die, isHit: false, isBearOff: true))
                }
                continue
            }
            if player == .black && to >= 25 && board.canBearOff(.black) {
                if to == 25 || isHighestChecker(board: board, player: .black, point: from) {
                    moves.append(CheckerMove(from: from, to: 25, dieUsed: die, isHit: false, isBearOff: true))
                }
                continue
            }

            guard (1...24).contains(to), board.isPointOpen(to, for: player) else { continue }
            let hit = board.isBlot(to, for: player)
            moves.append(CheckerMove(from: from, to: to, dieUsed: die, isHit: hit, isBearOff: false))
        }
        return moves
    }

    private static func isHighestChecker(board: BoardState, player: Player, point: Int) -> Bool {
        if player == .white {
            for i in stride(from: 6, through: point + 1, by: -1) {
                if board.points[i] > 0 { return false }
            }
            return true
        } else {
            for i in 19..<point {
                if board.points[i] < 0 { return false }
            }
            return true
        }
    }
}
