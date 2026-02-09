import SwiftUI

struct BoardView: View {
    @ObservedObject var engine: GameEngine

    let barWidth: CGFloat = 32

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width - 16
            let pointW = (totalWidth - barWidth) / 12
            let boardHeight = geo.size.height
            let labelHeight: CGFloat = 14
            let halfHeight = (boardHeight - labelHeight * 2) / 2

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.15, green: 0.35, blue: 0.15))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.brown, lineWidth: 4))

                VStack(spacing: 0) {
                    // Top labels with Black's home indicator
                    HStack(spacing: 0) {
                        ForEach(13...18, id: \.self) { i in
                            Text("\(i)").font(.system(size: 8)).frame(width: pointW)
                        }
                        Spacer().frame(width: barWidth)
                        // Black's home (19-24)
                        HStack(spacing: 0) {
                            ForEach(19...24, id: \.self) { i in
                                Text("\(i)").font(.system(size: 8)).frame(width: pointW)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.black.opacity(0.3))
                                .padding(.horizontal, -2)
                        )
                    }
                    .foregroundColor(.white.opacity(0.5))
                    .frame(height: labelHeight)

                    // Top half: points 13-24
                    HStack(spacing: 0) {
                        ForEach(13...18, id: \.self) { pt in
                            pointColumn(point: pt, fromTop: true, width: pointW, height: halfHeight)
                        }
                        barSection(width: barWidth, height: halfHeight * 2)
                        ForEach(19...24, id: \.self) { pt in
                            pointColumn(point: pt, fromTop: true, width: pointW, height: halfHeight)
                        }
                    }
                    .frame(height: halfHeight)

                    // Bottom half: points 12-1
                    HStack(spacing: 0) {
                        ForEach(Array(stride(from: 12, through: 7, by: -1)), id: \.self) { pt in
                            pointColumn(point: pt, fromTop: false, width: pointW, height: halfHeight)
                        }
                        Spacer().frame(width: barWidth)
                        ForEach(Array(stride(from: 6, through: 1, by: -1)), id: \.self) { pt in
                            pointColumn(point: pt, fromTop: false, width: pointW, height: halfHeight)
                        }
                    }
                    .frame(height: halfHeight)

                    // Bottom labels with White's home indicator
                    HStack(spacing: 0) {
                        ForEach(Array(stride(from: 12, through: 7, by: -1)), id: \.self) { i in
                            Text("\(i)").font(.system(size: 8)).frame(width: pointW)
                        }
                        Spacer().frame(width: barWidth)
                        // White's home (1-6)
                        HStack(spacing: 0) {
                            ForEach(Array(stride(from: 6, through: 1, by: -1)), id: \.self) { i in
                                Text("\(i)").font(.system(size: 8)).frame(width: pointW)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.2))
                                .padding(.horizontal, -2)
                        )
                    }
                    .foregroundColor(.white.opacity(0.5))
                    .frame(height: labelHeight)
                }
                .padding(.horizontal, 8)
            }
        }
    }

    // MARK: - Point Column

    private func pointColumn(point: Int, fromTop: Bool, width: CGFloat, height: CGFloat) -> some View {
        let count = abs(engine.board.points[point])
        let isWhite = engine.board.points[point] > 0
        let baseTriangleColor: Color = point % 2 == 0 ? .brown.opacity(0.7) : .red.opacity(0.6)
        let checkerSize = min(width - 2, 24.0)

        // Check if highlighting is enabled and this point can move
        let showHighlight = engine.settings.highlightMovablePieces && canMoveFrom(point: point)

        // Check if this point is part of an AI move animation
        let isAIMoveFrom = engine.highlightedMoveFrom == point
        let isAIMoveTo = engine.highlightedMoveTo == point

        // Highlight triangle for AI moves
        let triangleColor: Color = isAIMoveFrom ? Color.orange.opacity(0.8) :
                                   isAIMoveTo ? Color.green.opacity(0.6) : baseTriangleColor

        // The topmost checker is the one closest to center:
        // Top row (fromTop=true): i == count - 1
        // Bottom row (fromTop=false): i == 0
        let topmostIndex = fromTop ? count - 1 : 0

        return ZStack(alignment: fromTop ? .top : .bottom) {
            Triangle(pointsUp: !fromTop)
                .fill(triangleColor)
                .frame(width: width, height: height * 0.85)
                .animation(.easeInOut(duration: 0.2), value: isAIMoveFrom)
                .animation(.easeInOut(duration: 0.2), value: isAIMoveTo)

            VStack(spacing: -2) {
                if !fromTop { Spacer() }
                ForEach(0..<min(count, 5), id: \.self) { i in
                    let isTopmost = i == topmostIndex
                    let checkerHighlight = (showHighlight && isTopmost) || (isAIMoveFrom && isTopmost)
                    Circle()
                        .fill(isWhite ? Color.white : Color(white: 0.15))
                        .overlay(Circle().stroke(
                            isAIMoveFrom && isTopmost ? Color.orange :
                            showHighlight && isTopmost ? Color.blue : Color.gray.opacity(0.4),
                            lineWidth: checkerHighlight ? 3 : 0.5))
                        .frame(width: checkerSize, height: checkerSize)
                        .scaleEffect(isAIMoveFrom && isTopmost ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: isAIMoveFrom)
                }
                if count > 5 {
                    Text("\(count)").font(.system(size: 9)).bold().foregroundColor(.white)
                }
                if fromTop { Spacer() }
            }
            .frame(height: height * 0.85)
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .onTapGesture { engine.selectPoint(point) }
    }

    /// Check if the current player can move from this point using the first die
    private func canMoveFrom(point: Int) -> Bool {
        guard engine.phase == .moving,
              let firstDie = engine.remainingDice.first else { return false }

        let player = engine.humanPlayer

        // If on bar, can only move from bar
        if engine.board.bar[player.barIndex] > 0 {
            return false
        }

        // Check if player has checkers here
        guard engine.board.checkersAt(point: point, for: player) > 0 else { return false }

        // Check if there's a legal move from here with the first die
        let moves = MoveGenerator.generateSingleMoves(board: engine.board, player: player, die: firstDie)
        return moves.contains { $0.from == point }
    }

    // MARK: - Bar

    private func barSection(width: CGFloat, height: CGFloat) -> some View {
        // Check if bar is highlighted for AI move
        let blackBarHighlighted = engine.highlightedMoveFrom == 25
        let whiteBarHighlighted = engine.highlightedMoveFrom == 0

        // Check if human must enter from bar (pulsing highlight)
        let humanMustEnterBlack = engine.humanHasBarPieces && engine.humanPlayer == .black
        let humanMustEnterWhite = engine.humanHasBarPieces && engine.humanPlayer == .white

        let checkerSize: CGFloat = 18
        let maxVisible = 5

        return VStack(spacing: 0) {
            // Black's captured pieces (top half)
            ZStack {
                VStack(spacing: -4) {
                    ForEach(0..<min(engine.board.bar[1], maxVisible), id: \.self) { i in
                        let isTopmost = i == min(engine.board.bar[1], maxVisible) - 1
                        let needsHighlight = (blackBarHighlighted || humanMustEnterBlack) && isTopmost
                        Circle().fill(Color(white: 0.15))
                            .frame(width: checkerSize, height: checkerSize)
                            .overlay(Circle().stroke(
                                blackBarHighlighted && isTopmost ? Color.orange :
                                humanMustEnterBlack && isTopmost ? Color.blue : Color.clear,
                                lineWidth: needsHighlight ? 3 : 0))
                            .scaleEffect(needsHighlight ? 1.15 : 1.0)
                            .shadow(color: humanMustEnterBlack && isTopmost ? Color.blue.opacity(0.8) : Color.clear, radius: 6)
                            .animation(.easeInOut(duration: 0.2), value: blackBarHighlighted)
                            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: humanMustEnterBlack)
                    }
                    if engine.board.bar[1] > maxVisible {
                        Text("\(engine.board.bar[1])").font(.system(size: 8)).bold()
                            .foregroundColor(.white)
                    }
                }
            }
            .frame(height: height / 2)

            Rectangle().fill(Color.brown.opacity(0.5)).frame(height: 2)

            // White's captured pieces (bottom half)
            ZStack {
                VStack(spacing: -4) {
                    if engine.board.bar[0] > maxVisible {
                        Text("\(engine.board.bar[0])").font(.system(size: 8)).bold()
                            .foregroundColor(.black)
                    }
                    ForEach(0..<min(engine.board.bar[0], maxVisible), id: \.self) { i in
                        let isTopmost = i == 0  // First rendered is visually on top for bottom section
                        let needsHighlight = (whiteBarHighlighted || humanMustEnterWhite) && isTopmost
                        Circle().fill(Color.white)
                            .frame(width: checkerSize, height: checkerSize)
                            .overlay(Circle().stroke(
                                whiteBarHighlighted && isTopmost ? Color.orange :
                                humanMustEnterWhite && isTopmost ? Color.blue : Color.gray.opacity(0.5),
                                lineWidth: needsHighlight ? 3 : 0.5))
                            .scaleEffect(needsHighlight ? 1.15 : 1.0)
                            .shadow(color: humanMustEnterWhite && isTopmost ? Color.blue.opacity(0.8) : Color.clear, radius: 6)
                            .animation(.easeInOut(duration: 0.2), value: whiteBarHighlighted)
                            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: humanMustEnterWhite)
                    }
                }
            }
            .frame(height: height / 2)
        }
        .frame(width: width)
        .background(Color.brown.opacity(0.3))
        .onTapGesture {
            if engine.board.bar[engine.humanPlayer.barIndex] > 0 {
                engine.selectPoint(engine.humanPlayer == .white ? 0 : 25)
            }
        }
    }

}

// MARK: - Triangle Shape

struct Triangle: Shape {
    let pointsUp: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        if pointsUp {
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
        p.closeSubpath()
        return p
    }
}
