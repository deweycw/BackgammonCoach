"""
GNU Backgammon evaluation server.
Wraps gnubg in TTY mode and exposes position evaluation as REST endpoints.
"""
import asyncio
import logging
import os
import re
from contextlib import asynccontextmanager
from typing import Optional

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# MARK: - Models

class EvaluateRequest(BaseModel):
    points: list[int] = Field(..., min_length=24, max_length=24)
    bar: list[int] = Field(default=[0, 0], min_length=2, max_length=2)
    borne_off: list[int] = Field(default=[0, 0], min_length=2, max_length=2)
    dice: list[int] = Field(..., min_length=2, max_length=2)
    player: str = "white"
    ply: int = Field(default=2, ge=0, le=4)


class CubeRequest(BaseModel):
    points: list[int] = Field(..., min_length=24, max_length=24)
    bar: list[int] = Field(default=[0, 0])
    borne_off: list[int] = Field(default=[0, 0])
    cube_value: int = 1
    cube_owner: str = "centered"
    player: str = "white"
    ply: int = Field(default=2, ge=0, le=4)


class MoveResponse(BaseModel):
    from_point: int
    to_point: int
    die_used: int
    is_hit: bool = False
    is_bear_off: bool = False


class PlayResponse(BaseModel):
    moves: list[MoveResponse]
    notation: str


class RankedPlay(BaseModel):
    rank: int
    play: PlayResponse
    equity: float
    win_probability: float = 0.5
    equity_difference: float = 0.0


class EvaluateResponse(BaseModel):
    best_play: PlayResponse
    best_equity: float
    all_plays: list[RankedPlay]


class CubeResponse(BaseModel):
    recommendation: str
    no_double_equity: float = 0.0
    double_take_equity: float = 0.0
    double_pass_equity: float = 1.0
    proper_cube_action: str = ""
    win_probability: float = 0.5
    gammon_threat: float = 0.0


# MARK: - Engine Manager

class GnuBgEngine:
    def __init__(self):
        self.process: Optional[asyncio.subprocess.Process] = None
        self._lock = asyncio.Lock()
        self._ready = False
        self.version = "unknown"

    async def start(self):
        gnubg_path = os.environ.get("GNUBG_PATH", "gnubg")
        logger.info(f"Starting gnubg from: {gnubg_path}")
        try:
            self.process = await asyncio.create_subprocess_exec(
                gnubg_path, "--tty",
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env={**os.environ, "LANG": "C"}
            )
            banner = await self._read_until_prompt(timeout=10.0)
            logger.info(f"gnubg started: {banner[:200]}")
            vm = re.search(r'GNU Backgammon\s+([\d.]+)', banner)
            if vm:
                self.version = vm.group(1)
            await self._send("set evaluation chequer eval plies 2")
            await self._send("set evaluation cubedecision eval plies 2")
            self._ready = True
            logger.info(f"gnubg ready (v{self.version})")
        except FileNotFoundError:
            logger.warning("gnubg not found — running in MOCK mode")
            self._ready = True
            self.version = "mock"

    async def stop(self):
        if self.process:
            try:
                await self._send("quit")
            except Exception:
                pass
            self.process.terminate()

    @property
    def is_ready(self):
        return self._ready

    async def evaluate(self, req: EvaluateRequest) -> EvaluateResponse:
        if self.version == "mock":
            return self._mock_evaluate(req)
        async with self._lock:
            logger.info(f"Evaluating position with dice {req.dice} for {req.player}")
            # Log the board state for debugging
            logger.info(f"Board points: {req.points}")
            logger.info(f"Bar: {req.bar}")

            # Validate checker counts (each player should have exactly 15)
            white_count = sum(max(0, p) for p in req.points) + req.bar[0] + req.borne_off[0]
            black_count = sum(max(0, -p) for p in req.points) + req.bar[1] + req.borne_off[1]
            logger.info(f"Checker counts - White: {white_count}, Black: {black_count}")

            if white_count != 15 or black_count != 15:
                logger.warning(f"Invalid checker count! White={white_count}, Black={black_count}. Using mock.")
                return self._mock_evaluate(req)

            try:
                await self._send(f"set evaluation chequer eval plies {req.ply}")
                await self._send("new game")

                # Encode position (always from fixed white/black perspective)
                pos_id = self._make_position_id(req.points, req.bar)
                logger.info(f"Setting position ID: {pos_id}")

                # Set the board position
                set_result = await self._send(f"set board {pos_id}")
                logger.info(f"Set board result: '{set_result[:150] if set_result else 'empty'}'")

                # Check if position was rejected
                if "Illegal" in set_result:
                    logger.warning(f"gnubg rejected position as illegal, using mock")
                    return self._mock_evaluate(req)

                # Set whose turn it is: 0 = O (white), 1 = X (black)
                turn = 0 if req.player == "white" else 1
                await self._send(f"set turn {turn}")
                logger.info(f"Set turn to {turn} ({req.player})")

                # Verify the board was set correctly
                board_output = await self._send("show board")
                logger.info(f"Board after set: {board_output[:300] if board_output else 'empty'}")

                # Set dice and get hint
                await self._send(f"set dice {req.dice[0]} {req.dice[1]}")
                output = await self._send("hint", timeout=30.0)
                logger.info(f"Hint output: {len(output)} chars")

                if not output or "Eq.:" not in output:
                    logger.warning("No valid hint output, using mock")
                    return self._mock_evaluate(req)

                result = self._parse_evaluation(output)
                logger.info(f"Parsed result (gnubg coords): {result.best_play.notation}")

                # Transform gnubg coordinates to app coordinates if black is on roll
                # gnubg returns moves in player-on-roll's coordinate system:
                # - Point 1 = player's bear-off point
                # - Point 24 = player's far point
                # For black on roll: gnubg point 1 = app point 24, gnubg point 24 = app point 1
                if req.player == "black":
                    result = self._transform_for_black(result)
                    logger.info(f"Transformed result (app coords): {result.best_play.notation}")

                return result
            except Exception as e:
                logger.error(f"Evaluation error: {e}")
                return self._mock_evaluate(req)

    def _transform_for_black(self, result: EvaluateResponse) -> EvaluateResponse:
        """Transform gnubg coordinates to app coordinates for black.

        gnubg uses player-on-roll's coordinate system:
        - gnubg point 1 = player's bear-off point = app point 24 for black
        - gnubg point 24 = player's far point = app point 1 for black
        - gnubg bar (0) = app bar for black = 25

        Transform: app_point = 25 - gnubg_point (for board points 1-24)
        """
        def transform_move(m: MoveResponse) -> MoveResponse:
            # Transform from_point
            if m.from_point == 0:
                # Bar: gnubg uses 0, app uses 25 for black's bar
                from_pt = 25
            else:
                from_pt = 25 - m.from_point

            # Transform to_point
            if m.is_bear_off:
                # For bear-off, calculate the target point (will be > 24 for black)
                to_pt = from_pt + m.die_used
            else:
                to_pt = 25 - m.to_point

            return MoveResponse(
                from_point=from_pt,
                to_point=to_pt,
                die_used=m.die_used,
                is_hit=m.is_hit,
                is_bear_off=m.is_bear_off
            )

        def transform_play(p: PlayResponse) -> PlayResponse:
            new_moves = [transform_move(m) for m in p.moves]
            # Recreate notation with transformed points
            notation_parts = []
            for m in new_moves:
                from_str = "bar" if m.from_point == 0 else str(m.from_point)
                to_str = "off" if m.is_bear_off else str(m.to_point)
                notation_parts.append(f"{from_str}/{to_str}{'*' if m.is_hit else ''}")
            return PlayResponse(moves=new_moves, notation=" ".join(notation_parts))

        new_best = transform_play(result.best_play)
        new_all = [
            RankedPlay(
                rank=rp.rank,
                play=transform_play(rp.play),
                equity=-rp.equity,  # Negate equity for opponent's perspective
                win_probability=1.0 - rp.win_probability,
                equity_difference=rp.equity_difference
            )
            for rp in result.all_plays
        ]
        return EvaluateResponse(
            best_play=new_best,
            best_equity=-result.best_equity,
            all_plays=new_all
        )

    async def evaluate_cube(self, req: CubeRequest) -> CubeResponse:
        if self.version == "mock":
            return self._mock_cube()
        async with self._lock:
            logger.info(f"Evaluating cube decision")
            try:
                await self._send(f"set evaluation cubedecision eval plies {req.ply}")
                await self._send("new game")
                await self._setup_position(req.points, req.bar, req.player)
                output = await self._send("hint cube", timeout=30.0)
                return self._parse_cube(output)
            except Exception as e:
                logger.error(f"Cube evaluation error: {e}")
                return self._mock_cube()

    async def _setup_position(self, points: list[int], bar: list[int], player: str):
        """Set up board position using gnubg edit mode."""
        # Enter edit mode
        await self._send("set turn 0")  # Ensure player 0 is on roll

        # Clear the board first by setting to empty position
        await self._send("clear board")

        # Place checkers using set command
        # In gnubg: "set board simple" followed by point values
        # Or use position by setting checkers directly

        # Build the position string for gnubg's "set board" command
        # Format: 24 point values for player 0, then player 1
        # Positive = player 0, negative = player 1

        # Our format: positive = white, negative = black
        # Determine who is player 0 (on roll) in gnubg

        if player == "white":
            # White on roll - white is player 0
            p0_points = []
            p1_points = []
            for i in range(24):
                if points[i] > 0:
                    p0_points.append(f"{i+1}:{points[i]}")
                elif points[i] < 0:
                    p1_points.append(f"{25-i-1}:{-points[i]}")

            p0_bar = bar[0]
            p1_bar = bar[1]
        else:
            # Black on roll - black is player 0
            p0_points = []
            p1_points = []
            for i in range(24):
                if points[i] < 0:
                    p0_points.append(f"{25-i-1}:{-points[i]}")
                elif points[i] > 0:
                    p1_points.append(f"{i+1}:{points[i]}")

            p0_bar = bar[1]
            p1_bar = bar[0]

        # Set up using external position string
        # Simpler: use the eval command directly with position
        # gnubg accepts: eval 8/5 6/5 (evaluates specific play)
        # But for hint we need the position set up

        # Use gnubg external encoding - build position array
        pos_array = [0] * 26  # Points 0-25 (0=bar, 25=off)
        opp_array = [0] * 26

        if player == "white":
            pos_array[0] = bar[0]  # White's bar
            opp_array[0] = bar[1]  # Black's bar
            for i in range(24):
                if points[i] > 0:
                    pos_array[i + 1] = points[i]
                elif points[i] < 0:
                    opp_array[24 - i] = -points[i]
        else:
            pos_array[0] = bar[1]  # Black's bar
            opp_array[0] = bar[0]  # White's bar
            for i in range(24):
                if points[i] < 0:
                    pos_array[24 - i] = -points[i]
                elif points[i] > 0:
                    opp_array[i + 1] = points[i]

        # Format as gnubg external position string
        pos_str = " ".join(str(x) for x in pos_array[1:25])  # Points 1-24
        opp_str = " ".join(str(x) for x in opp_array[1:25])

        # Use external format: set board external ...
        # Actually, simplest is to use gnubg's native format
        # set board [O-O-O-O-O-|...] format

        # Build standard backgammon position notation
        # gnubg uses: set board simple then answers questions
        # Or we can use the board string format

        # Simplest working approach: use gnubg position ID
        pos_id = self._make_position_id(points, bar)
        logger.info(f"Position ID: {pos_id}")
        await self._send(f"set board {pos_id}")

        # Set whose turn it is: 0 = O (white), 1 = X (black)
        turn = 0 if player == "white" else 1
        await self._send(f"set turn {turn}")

    def _make_position_id(self, points: list[int], bar: list[int]) -> str:
        """Generate gnubg position ID string.

        gnubg position ID encoding (ALWAYS from fixed perspective):
        - First half: Player 0 (O/white in gnubg) checkers from point 1→24, then bar
        - Second half: Player 1 (X/black in gnubg) checkers from point 1→24, then bar
        - Each point: N ones (for N checkers) followed by one zero
        - Total: 80 bits, packed LSB-first into 10 bytes, base64 encoded

        The position ID describes WHERE pieces are, not whose turn it is.
        Turn is set separately with 'set turn 0' or 'set turn 1'.
        """
        import base64

        bits = []

        # Player 0 (O/white): encode from point 1→24
        # App point N = gnubg point N for white = index N-1
        for i in range(24):  # indices 0→23 = points 1→24
            count = max(0, points[i])  # White checkers (positive)
            bits.extend([1] * count)
            bits.append(0)
        bits.extend([1] * bar[0])  # White's bar
        bits.append(0)

        # Player 1 (X/black): encode from point 1→24
        # Black's point 1 = app point 24 = index 23
        # Black's point 24 = app point 1 = index 0
        for i in range(23, -1, -1):  # indices 23→0 = black's points 1→24
            count = max(0, -points[i])  # Black checkers (negative)
            bits.extend([1] * count)
            bits.append(0)
        bits.extend([1] * bar[1])  # Black's bar
        bits.append(0)

        # Truncate/pad to 80 bits
        bits = (bits + [0] * 80)[:80]

        # Convert to bytes (LSB first)
        data = bytearray(10)
        for i, bit in enumerate(bits):
            if bit:
                data[i // 8] |= (1 << (i % 8))

        return base64.b64encode(data).decode('ascii').rstrip('=')

    def _make_match_id(self, dice: list[int]) -> str:
        """Generate gnubg match ID for evaluation."""
        import base64

        # Match ID is 9 bytes (72 bits) base64 encoded
        # Bits:
        # 0-3: cube value (log2)
        # 4-5: cube owner (0=player 0, 1=player 1, 3=centered)
        # 6: player on roll (0=player 0, 1=player 1)
        # 7: crawford flag
        # 8-10: game state (0=no game, 1=playing)
        # ... more fields for match play

        data = bytearray(9)

        # Cube = 1 (log2=0), centered (3), player 0 on roll, no crawford
        data[0] = 0b00110000

        # Game state = 1 (playing), turn = player 0's turn
        data[1] = 0b00000001

        # Dice encoding: bits 21-26
        # Die 1: bits 21-23 (values 0-5 for dice 1-6)
        # Die 2: bits 24-26 (values 0-5 for dice 1-6)
        if dice and len(dice) == 2 and dice[0] > 0 and dice[1] > 0:
            d1 = (dice[0] - 1) & 0x7
            d2 = (dice[1] - 1) & 0x7
            # Bit 21-23 = d1 spans bytes 2 (bits 5-7) and byte 3 (bit 0)
            # Bit 24-26 = d2 is in byte 3 (bits 1-3)
            data[2] |= (d1 << 5) & 0xFF
            data[3] |= (d1 >> 3) & 0xFF
            data[3] |= (d2 << 1) & 0xFF

        return base64.b64encode(data).decode('ascii').rstrip('=')

    def _parse_evaluation(self, output: str) -> EvaluateResponse:
        plays = []
        move_pat = re.compile(
            r'^\s*(\d+)\.\s+.*?(\S+(?:/\S+)+(?:\*?(?:\s+\S+/\S+\*?)*)?)\s+.*?Eq\.:\s*([+-]?\d+\.\d+)',
            re.MULTILINE)
        for m in move_pat.finditer(output):
            rank = int(m.group(1))
            notation = m.group(2).strip()
            equity = float(m.group(3))
            play = self._parse_notation(notation)
            plays.append(RankedPlay(
                rank=rank, play=play, equity=equity,
                equity_difference=0.0 if rank == 1 else (plays[0].equity - equity) if plays else 0.0
            ))
        if not plays:
            plays.append(RankedPlay(
                rank=1, play=PlayResponse(moves=[], notation="No move"),
                equity=0.0))
        return EvaluateResponse(
            best_play=plays[0].play, best_equity=plays[0].equity, all_plays=plays)

    def _parse_notation(self, notation: str) -> PlayResponse:
        moves = []
        for part in notation.split():
            # Handle multiplier notation like "20/24(3)" - extract count
            multiplier_match = re.search(r'\((\d+)\)', part)
            count = int(multiplier_match.group(1)) if multiplier_match else 1
            part = re.sub(r'\(\d+\)', '', part)

            # Split first, then detect which segment has the hit marker
            segments = part.split('/')
            if len(segments) >= 2:
                # Handle compound moves like "7/11/15" (one checker moving twice)
                for i in range(len(segments) - 1):
                    from_str = segments[i].strip()
                    to_str = segments[i + 1].strip()

                    # Check if this segment has a hit marker (the * is on the destination)
                    segment_hit = '*' in to_str

                    # Strip hit markers from both (from_str may have * from previous compound move)
                    from_str = from_str.replace('*', '')
                    to_str = to_str.replace('*', '')

                    # Handle "bar" and "off" cases
                    from_pt = 0 if from_str.lower() == 'bar' else int(from_str)
                    bear_off = to_str.lower() == 'off'

                    if bear_off:
                        # For bear-off, die = from_point (minimum die needed to bear off)
                        to_pt = 0  # Placeholder, will be calculated in transformation
                        die = from_pt
                    else:
                        to_pt = int(to_str)
                        die = abs(from_pt - to_pt)

                    # Add the move 'count' times (for doubles notation like 20/24(3))
                    for _ in range(count):
                        moves.append(MoveResponse(
                            from_point=from_pt, to_point=to_pt, die_used=die,
                            is_hit=segment_hit,
                            is_bear_off=bear_off))

        # Post-process: split any combined moves (die > 6) into individual die moves
        # This handles gnubg notation like "1/10" which uses both dice on one checker
        processed_moves = []
        for m in moves:
            if m.die_used > 6 and not m.is_bear_off:
                # This is a combined move - need to split into two dice
                # For now, just mark it so validation can handle it
                # We'll split based on common dice combinations
                total = m.die_used
                # Try to find valid die combinations (assuming dice 1-6)
                # Common splits: 7=1+6, 8=2+6=3+5, 9=3+6=4+5, 10=4+6=5+5, 11=5+6, 12=6+6
                if total <= 12:
                    # Find a valid split using dice 1-6
                    for d1 in range(1, 7):
                        d2 = total - d1
                        if 1 <= d2 <= 6:
                            mid_pt = m.from_point + d1 if m.to_point > m.from_point else m.from_point - d1
                            processed_moves.append(MoveResponse(
                                from_point=m.from_point, to_point=mid_pt, die_used=d1,
                                is_hit=False, is_bear_off=False))
                            processed_moves.append(MoveResponse(
                                from_point=mid_pt, to_point=m.to_point, die_used=d2,
                                is_hit=m.is_hit, is_bear_off=False))
                            break
                else:
                    processed_moves.append(m)  # Can't split, keep as is
            else:
                processed_moves.append(m)

        return PlayResponse(moves=processed_moves, notation=notation)

    def _parse_cube(self, output: str) -> CubeResponse:
        nd = re.search(r'No\s+double.*?([+-]?\d+\.\d+)', output)
        dt = re.search(r'Double.*?take.*?([+-]?\d+\.\d+)', output, re.IGNORECASE)
        dp = re.search(r'Double.*?pass.*?([+-]?\d+\.\d+)', output, re.IGNORECASE)
        nd_eq = float(nd.group(1)) if nd else 0.0
        dt_eq = float(dt.group(1)) if dt else 0.0
        dp_eq = float(dp.group(1)) if dp else 1.0
        best = max(nd_eq, dt_eq, dp_eq)
        if best == nd_eq:
            rec = "no_double"
        elif best == dt_eq:
            rec = "double_take"
        else:
            rec = "double_pass"
        return CubeResponse(
            recommendation=rec, no_double_equity=nd_eq,
            double_take_equity=dt_eq, double_pass_equity=dp_eq,
            proper_cube_action=rec.replace("_", " ").title())

    # MARK: - Mock mode (when gnubg is not installed)

    def _mock_evaluate(self, req: EvaluateRequest) -> EvaluateResponse:
        """Generate plausible mock evaluations for testing without gnubg."""
        import random
        # Generate a few mock plays
        player = req.player
        d1, d2 = req.dice
        sign = 1 if player == "white" else -1
        direction = -1 if player == "white" else 1

        mock_plays = []
        # Find occupied points
        occupied = []
        for i in range(24):
            pt = i + 1
            val = req.points[i]
            if (player == "white" and val > 0) or (player == "black" and val < 0):
                occupied.append(pt)

        # Generate a simple play
        if occupied:
            src = random.choice(occupied)
            dest1 = src + d1 * direction
            dest2 = src + d2 * direction
            moves = []
            if 1 <= dest1 <= 24:
                moves.append(MoveResponse(from_point=src, to_point=dest1, die_used=d1))
            if 1 <= dest2 <= 24:
                moves.append(MoveResponse(from_point=src, to_point=dest2, die_used=d2))

            base_eq = random.uniform(-0.2, 0.5)
            play = PlayResponse(moves=moves, notation=f"{src}/{dest1} {src}/{dest2}")
            mock_plays.append(RankedPlay(rank=1, play=play, equity=base_eq))

            # Add a slightly worse alternative
            if len(occupied) > 1:
                src2 = random.choice([p for p in occupied if p != src])
                d2_dest = src2 + d1 * direction
                if 1 <= d2_dest <= 24:
                    alt_moves = [MoveResponse(from_point=src2, to_point=d2_dest, die_used=d1)]
                    alt_play = PlayResponse(moves=alt_moves, notation=f"{src2}/{d2_dest}")
                    mock_plays.append(RankedPlay(
                        rank=2, play=alt_play, equity=base_eq - random.uniform(0.01, 0.1),
                        equity_difference=random.uniform(0.01, 0.1)))

        if not mock_plays:
            mock_plays.append(RankedPlay(
                rank=1, play=PlayResponse(moves=[], notation="No move"), equity=0.0))

        return EvaluateResponse(
            best_play=mock_plays[0].play,
            best_equity=mock_plays[0].equity,
            all_plays=mock_plays)

    def _mock_cube(self) -> CubeResponse:
        import random
        eq = random.uniform(-0.3, 0.8)
        return CubeResponse(
            recommendation="no_double" if eq < 0.4 else "double_take",
            no_double_equity=eq, double_take_equity=eq + 0.1,
            double_pass_equity=1.0,
            proper_cube_action="No double" if eq < 0.4 else "Double, take",
            win_probability=0.5 + eq * 0.3, gammon_threat=max(0, eq * 0.2))

    # MARK: - Process IO

    async def _send(self, cmd: str, timeout: float = 10.0) -> str:
        if not self.process or not self.process.stdin:
            raise RuntimeError("gnubg not running")
        logger.debug(f"Sending command: {cmd}")
        self.process.stdin.write(f"{cmd}\n".encode())
        await self.process.stdin.drain()
        result = await self._read_until_prompt(timeout)
        logger.debug(f"Response: {result[:200] if result else 'empty'}")
        return result

    async def _read_until_prompt(self, timeout: float = 10.0) -> str:
        if not self.process or not self.process.stdout:
            return ""
        parts = []
        # Read with a short per-line timeout - when no more data comes, we're done
        line_timeout = 0.5  # Wait up to 0.5s for each line
        deadline = asyncio.get_event_loop().time() + timeout
        try:
            while asyncio.get_event_loop().time() < deadline:
                remaining = deadline - asyncio.get_event_loop().time()
                wait_time = min(line_timeout, remaining)
                if wait_time <= 0:
                    break
                try:
                    line = await asyncio.wait_for(
                        self.process.stdout.readline(),
                        timeout=wait_time
                    )
                    if not line:
                        break
                    decoded = line.decode("utf-8", errors="replace").rstrip()
                    parts.append(decoded)
                    # Check for prompt or end of hint output
                    if "(gnubg)" in decoded:
                        break
                    # If we see numbered moves (hint output), keep reading until timeout
                except asyncio.TimeoutError:
                    # No more data available - we're done
                    if parts:
                        break
        except Exception as e:
            logger.error(f"Read error: {e}")
        return "\n".join(parts)


# MARK: - FastAPI App

engine = GnuBgEngine()


@asynccontextmanager
async def lifespan(app: FastAPI):
    await engine.start()
    yield
    await engine.stop()


app = FastAPI(title="GNU Backgammon Server", version="1.0.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


@app.get("/health")
async def health():
    return {"status": "ok" if engine.is_ready else "starting",
            "gnubg_version": engine.version, "engine_ready": engine.is_ready}


@app.post("/evaluate", response_model=EvaluateResponse)
async def evaluate(req: EvaluateRequest):
    if not engine.is_ready:
        raise HTTPException(503, "Engine not ready")
    return await engine.evaluate(req)


@app.post("/cube", response_model=CubeResponse)
async def cube(req: CubeRequest):
    if not engine.is_ready:
        raise HTTPException(503, "Engine not ready")
    return await engine.evaluate_cube(req)
