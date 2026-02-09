import XCTest
@testable import BackgammonCoach

final class MoveGeneratorTests: XCTestCase {

    func testOpeningPosition31() {
        var board = BoardState.newGame()
        board.currentPlayer = .white
        let plays = MoveGenerator.legalPlays(board: board, dice: Dice(die1: 3, die2: 1))
        XCTAssertFalse(plays.isEmpty)
        for play in plays { XCTAssertEqual(play.moves.count, 2) }
        // 8/5 6/5 should exist
        let makesFive = plays.contains { p in
            let sorted = p.moves.sorted { $0.dieUsed > $1.dieUsed }
            return sorted.count == 2 && sorted[0].from == 8 && sorted[0].to == 5
                && sorted[1].from == 6 && sorted[1].to == 5
        }
        XCTAssertTrue(makesFive)
    }

    func testDoubles66() {
        var board = BoardState.newGame()
        board.currentPlayer = .white
        let plays = MoveGenerator.legalPlays(board: board, dice: Dice(die1: 6, die2: 6))
        XCTAssertFalse(plays.isEmpty)
        XCTAssertTrue(plays.allSatisfy { $0.moves.count == 4 })
    }

    func testBarEntryMustEnterFirst() {
        var board = BoardState.newGame()
        board.currentPlayer = .white
        board.bar[0] = 1; board.points[24] -= 1
        let plays = MoveGenerator.legalPlays(board: board, dice: Dice(die1: 3, die2: 1))
        for play in plays { XCTAssertTrue(play.moves[0].from == 0) }
    }

    func testBarBlocked() {
        var board = emptyBoard(.white)
        board.bar[0] = 2; board.borneOff[0] = 13
        for i in 19...24 { board.points[i] = -2 }
        let plays = MoveGenerator.legalPlays(board: board, dice: Dice(die1: 3, die2: 5))
        XCTAssertTrue(plays.isEmpty || plays.allSatisfy { $0.moves.isEmpty })
    }

    func testBearOffExact() {
        var board = emptyBoard(.white)
        board.points[6] = 2; board.points[5] = 3; board.points[1] = 2; board.borneOff[0] = 8
        let plays = MoveGenerator.legalPlays(board: board, dice: Dice(die1: 6, die2: 5))
        let bothOff = plays.contains { $0.moves.count == 2 && $0.moves.allSatisfy(\.isBearOff) }
        XCTAssertTrue(bothOff)
    }

    func testCannotBearOffOutside() {
        var board = emptyBoard(.white)
        board.points[6] = 3; board.points[5] = 2; board.points[10] = 2; board.borneOff[0] = 8
        let plays = MoveGenerator.legalPlays(board: board, dice: Dice(die1: 6, die2: 5))
        XCTAssertFalse(plays.contains { $0.moves.contains(\.isBearOff) })
    }

    func testHitDetection() {
        var board = BoardState.newGame()
        board.currentPlayer = .white
        board.points[20] = -1
        let plays = MoveGenerator.legalPlays(board: board, dice: Dice(die1: 4, die2: 2))
        XCTAssertTrue(plays.contains { $0.moves.contains { $0.to == 20 && $0.isHit } })
    }

    func testCheckerCountPreserved() {
        var board = BoardState.newGame()
        board.currentPlayer = .white
        let plays = MoveGenerator.legalPlays(board: board, dice: Dice(die1: 3, die2: 1))
        for play in plays {
            let nb = board.applying(play, for: .white)
            var w = nb.bar[0] + nb.borneOff[0], b = nb.bar[1] + nb.borneOff[1]
            for i in 1...24 {
                if nb.points[i] > 0 { w += nb.points[i] }
                if nb.points[i] < 0 { b += abs(nb.points[i]) }
            }
            XCTAssertEqual(w, 15); XCTAssertEqual(b, 15)
        }
    }

    func testNoDuplicatePlays() {
        var board = BoardState.newGame()
        board.currentPlayer = .white
        let plays = MoveGenerator.legalPlays(board: board, dice: Dice(die1: 6, die2: 1))
        var seen = Set<BoardState>()
        for play in plays {
            XCTAssertTrue(seen.insert(board.applying(play, for: .white)).inserted)
        }
    }

    func testBlackMoveDirection() {
        var board = BoardState.newGame()
        board.currentPlayer = .black
        let plays = MoveGenerator.legalPlays(board: board, dice: Dice(die1: 3, die2: 1))
        XCTAssertFalse(plays.isEmpty)
        for play in plays {
            for m in play.moves where m.from != 0 && m.from != 25 && !m.isBearOff {
                XCTAssertGreaterThan(m.to, m.from)
            }
        }
    }

    private func emptyBoard(_ player: Player) -> BoardState {
        BoardState(points: [Int](repeating: 0, count: 25), bar: [0, 0],
                   borneOff: [0, 0], cube: CubeState(), currentPlayer: player)
    }
}

final class BoardStateTests: XCTestCase {
    func testStartingPipCount() {
        let b = BoardState.newGame()
        XCTAssertEqual(b.pipCount.white, 167)
        XCTAssertEqual(b.pipCount.black, 167)
    }

    func testGameOver() {
        var b = BoardState(points: [Int](repeating: 0, count: 25),
                           bar: [0, 0], borneOff: [15, 0], cube: CubeState(), currentPlayer: .white)
        XCTAssertTrue(b.isGameOver)
        XCTAssertEqual(b.winner, .white)
    }

    func testGammon() {
        var b = BoardState(points: [Int](repeating: 0, count: 25),
                           bar: [0, 0], borneOff: [15, 0], cube: CubeState(), currentPlayer: .white)
        b.points[19] = -10; b.points[20] = -5
        XCTAssertEqual(b.gameResult, 2)
    }

    func testBackgammon() {
        var b = BoardState(points: [Int](repeating: 0, count: 25),
                           bar: [0, 0], borneOff: [15, 0], cube: CubeState(), currentPlayer: .white)
        b.points[3] = -2; b.points[19] = -8; b.points[20] = -5
        XCTAssertEqual(b.gameResult, 3)
    }

    func testCubeDoubling() {
        var c = CubeState()
        XCTAssertTrue(c.canDouble(.white))
        XCTAssertTrue(c.canDouble(.black))
        c.value = 2; c.owner = .black
        XCTAssertTrue(c.canDouble(.black))
        XCTAssertFalse(c.canDouble(.white))
    }
}

final class MatchStateTests: XCTestCase {
    func testCrawfordRule() {
        var ms = MatchState(config: .match(length: 5))
        ms.recordGameResult(winner: .white, multiplier: 2, cubeValue: 2)
        // Score: 4-0, white is 1 away -> Crawford
        XCTAssertTrue(ms.isCrawford)
        XCTAssertFalse(ms.isCubeAvailable)

        ms.recordGameResult(winner: .black, multiplier: 1, cubeValue: 1)
        // Score: 4-1, post-Crawford
        XCTAssertFalse(ms.isCrawford)
        XCTAssertTrue(ms.isPostCrawford)
        XCTAssertTrue(ms.isCubeAvailable)
    }

    func testMatchEquityTable() {
        let eq = MatchEquityTable.equity(awayWhite: 1, awayBlack: 1)
        XCTAssertEqual(eq, 0.5)

        let eq2 = MatchEquityTable.equity(awayWhite: 1, awayBlack: 15)
        XCTAssertGreaterThan(eq2, 0.9)
    }
}
