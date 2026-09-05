import SwiftUI
import Combine

enum Difficulty: String, CaseIterable, Codable {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"
    
    var cluesToRemove: Int {
        switch self {
        case .easy: return 32
        case .medium: return 45
        case .hard: return 54
        }
    }
}

struct SudokuCell: Identifiable, Codable {
    let id: String
    let row: Int
    let col: Int
    var value: Int
    var solutionValue: Int
    var isGiven: Bool
    var notes: Set<Int>
    var isSelected: Bool = false
    var isError: Bool = false
}

class SudokuEngine: ObservableObject {
    @Published var grid: [[SudokuCell]] = []
    @Published var selectedCell: (row: Int, col: Int)? = nil
    @Published var difficulty: Difficulty = .medium
    @Published var timerSeconds: Int = 0
    @Published var mistakes: Int = 0
    @Published var maxMistakes: Int = 3
    @Published var isGameOver: Bool = false
    @Published var isGameWon: Bool = false
    @Published var isNotesMode: Bool = false
    
    private var history: [[[SudokuCell]]] = []
    private var timerSubscription: AnyCancellable?
    
    init() {
        startNewGame(difficulty: .medium)
    }
    
    func startNewGame(difficulty: Difficulty) {
        self.difficulty = difficulty
        self.timerSeconds = 0
        self.mistakes = 0
        self.isGameOver = false
        self.isGameWon = false
        self.history.removeAll()
        
        let (puzzle, solution) = generateUniquePuzzle(difficulty: difficulty)
        
        var newGrid = [[SudokuCell]]()
        for r in 0..<9 {
            var rowCells = [SudokuCell]()
            for c in 0..<9 {
                let val = puzzle[r][c]
                let solVal = solution[r][c]
                let cell = SudokuCell(
                    id: "\(r)-\(c)",
                    row: r,
                    col: c,
                    value: val,
                    solutionValue: solVal,
                    isGiven: val != 0,
                    notes: []
                )
                rowCells.append(cell)
            }
            newGrid.append(rowCells)
        }
        self.grid = newGrid
        startTimer()
    }
    
    private func startTimer() {
        timerSubscription?.cancel()
        timerSubscription = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, !self.isGameOver, !self.isGameWon else { return }
                self.timerSeconds += 1
            }
    }
    
    func selectCell(row: Int, col: Int) {
        for r in 0..<9 {
            for c in 0..<9 {
                grid[r][c].isSelected = (r == row && c == col)
            }
        }
        selectedCell = (row, col)
    }
    
    func inputNumber(_ num: Int) {
        guard let pos = selectedCell, !grid[pos.row][pos.col].isGiven, !isGameOver else { return }
        
        recordHistory()
        
        if isNotesMode {
            if grid[pos.row][pos.col].notes.contains(num) {
                grid[pos.row][pos.col].notes.remove(num)
            } else {
                grid[pos.row][pos.col].notes.insert(num)
            }
            grid[pos.row][pos.col].value = 0
        } else {
            grid[pos.row][pos.col].notes.removeAll()
            grid[pos.row][pos.col].value = num
            
            if num != grid[pos.row][pos.col].solutionValue {
                grid[pos.row][pos.col].isError = true
                mistakes += 1
                if mistakes >= maxMistakes {
                    isGameOver = true
                }
            } else {
                grid[pos.row][pos.col].isError = false
                checkWinCondition()
            }
        }
    }
    
    func erase() {
        guard let pos = selectedCell, !grid[pos.row][pos.col].isGiven else { return }
        recordHistory()
        grid[pos.row][pos.col].value = 0
        grid[pos.row][pos.col].notes.removeAll()
        grid[pos.row][pos.col].isError = false
    }
    
    func provideHint() {
        guard let pos = selectedCell, !grid[pos.row][pos.col].isGiven else { return }
        recordHistory()
        let sol = grid[pos.row][pos.col].solutionValue
        grid[pos.row][pos.col].value = sol
        grid[pos.row][pos.col].notes.removeAll()
        grid[pos.row][pos.col].isError = false
        checkWinCondition()
    }
    
    func undo() {
        guard let previousState = history.popLast() else { return }
        self.grid = previousState
    }
    
    private func recordHistory() {
        if history.count > 20 { history.removeFirst() }
        history.append(self.grid)
    }
    
    private func checkWinCondition() {
        for r in 0..<9 {
            for c in 0..<9 {
                if grid[r][c].value != grid[r][c].solutionValue { return }
            }
        }
        isGameWon = true
    }
    
    private func generateUniquePuzzle(difficulty: Difficulty) -> ([[Int]], [[Int]]) {
        var board = Array(repeating: Array(repeating: 0, count: 9), count: 9)
        _ = fillBoard(&board)
        let solution = board
        
        var puzzle = solution
        var removed = 0
        let targetRemove = difficulty.cluesToRemove
        
        var cells = [(Int, Int)]()
        for r in 0..<9 { for c in 0..<9 { cells.append((r, c)) } }
        cells.shuffle()
        
        for (r, c) in cells {
            if removed >= targetRemove { break }
            let temp = puzzle[r][c]
            puzzle[r][c] = 0
            
            var solutionsCount = 0
            countSolutions(puzzle, count: &solutionsCount)
            
            if solutionsCount != 1 {
                puzzle[r][c] = temp
            } else {
                removed += 1
            }
        }
        return (puzzle, solution)
    }
    
    private func fillBoard(_ board: inout [[Int]]) -> Bool {
        for r in 0..<9 {
            for c in 0..<9 {
                if board[r][c] == 0 {
                    let numbers = (1...9).shuffled()
                    for num in numbers {
                        if isValid(board, r, c, num) {
                            board[r][c] = num
                            if fillBoard(&board) { return true }
                            board[r][c] = 0
                        }
                    }
                    return false
                }
            }
        }
        return true
    }
    
    private func countSolutions(_ board: [[Int]], count: inout Int) {
        var tempBoard = board
        func solve(_ b: inout [[Int]]) {
            if count >= 2 { return }
            for r in 0..<9 {
                for c in 0..<9 {
                    if b[r][c] == 0 {
                        for num in 1...9 {
                            if isValid(b, r, c, num) {
                                b[r][c] = num
                                solve(&b)
                                b[r][c] = 0
                            }
                        }
                        return
                    }
                }
            }
            count += 1
        }
        solve(&tempBoard)
    }
    
    private func isValid(_ board: [[Int]], _ r: Int, _ c: Int, _ num: Int) -> Bool {
        for i in 0..<9 {
            if board[r][i] == num || board[i][c] == num { return false }
            let boxR = 3 * (r / 3) + i / 3
            let boxC = 3 * (c / 3) + i % 3
            if board[boxR][boxC] == num { return false }
        }
        return true
    }
}

struct NeonTheme {
    static let background = Color(red: 0.03, green: 0.03, blue: 0.07)
    static let cyanGlow = Color(red: 0.0, green: 0.95, blue: 1.0)
    static let magentaGlow = Color(red: 1.0, green: 0.0, blue: 0.55)
    static let yellowGlow = Color(red: 1.0, green: 0.85, blue: 0.0)
    static let cellBg = Color(red: 0.08, green: 0.08, blue: 0.15)
    static let selectedBg = Color(red: 0.15, green: 0.25, blue: 0.45)
}

struct ContentView: View {
    @StateObject private var engine = SudokuEngine()
    
    var body: some View {
        ZStack {
            NeonTheme.background.ignoresSafeArea()
            
            VStack(spacing: 12) {
                HStack {
                    Text("NEON // SUDOKU")
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                        .foregroundColor(NeonTheme.cyanGlow)
                        .shadow(color: NeonTheme.cyanGlow, radius: 8)
                    Spacer()
                }
                .padding(.horizontal)
                
                Picker("Difficulty", selection: $engine.difficulty) {
                    ForEach(Difficulty.allCases, id: \.self) { diff in
                        Text(diff.rawValue).tag(diff)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: engine.difficulty) { newDiff in
                    engine.startNewGame(difficulty: newDiff)
                }
                .padding(.horizontal)
                
                HStack {
                    Label(formatTime(engine.timerSeconds), systemImage: "clock")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(NeonTheme.cyanGlow)
                    
                    Spacer()
                    
                    Label("MISTAKES: \(engine.mistakes)/\(engine.maxMistakes)", systemImage: "xmark.diamond")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(engine.mistakes > 0 ? NeonTheme.magentaGlow : .gray)
                }
                .padding(.horizontal)
                
                VStack(spacing: 2) {
                    ForEach(0..<9, id: \.self) { r in
                        HStack(spacing: 2) {
                            ForEach(0..<9, id: \.self) { c in
                                CellView(cell: engine.grid[r][c]) {
                                    engine.selectCell(row: r, col: c)
                                }
                            }
                        }
                    }
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(NeonTheme.cyanGlow, lineWidth: 2)
                        .shadow(color: NeonTheme.cyanGlow, radius: 10)
                )
                .padding(.horizontal, 8)
                
                HStack(spacing: 20) {
                    ActionButton(title: "UNDO", icon: "arrow.uturn.backward") { engine.undo() }
                    ActionButton(title: "ERASE", icon: "eraser") { engine.erase() }
                    ActionButton(title: "NOTES", icon: "pencil", isActive: engine.isNotesMode) { engine.isNotesMode.toggle() }
                    ActionButton(title: "HINT", icon: "lightbulb.fill") { engine.provideHint() }
                }
                .padding(.top, 4)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                    ForEach(1...9, id: \.self) { num in
                        Button(action: { engine.inputNumber(num) }) {
                            Text("\(num)")
                                .font(.title2.weight(.bold))
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(NeonTheme.cellBg)
                                .foregroundColor(NeonTheme.cyanGlow)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(NeonTheme.cyanGlow.opacity(0.6), lineWidth: 1)
                                )
                                .shadow(color: NeonTheme.cyanGlow.opacity(0.3), radius: 4)
                        }
                    }
                }
                .padding(.horizontal)
                Spacer()
            }
        }
        .alert("GAME OVER", isPresented: $engine.isGameOver) {
            Button("Try Again") { engine.startNewGame(difficulty: engine.difficulty) }
        } message: { Text("Exceeded maximum allowed mistakes.") }
        .alert("VICTORY!", isPresented: $engine.isGameWon) {
            Button("Next Game") { engine.startNewGame(difficulty: engine.difficulty) }
        } message: { Text("Solved in \(formatTime(engine.timerSeconds))!") }
    }
    
    private func formatTime(_ sec: Int) -> String {
        let m = sec / 60
        let s = sec % 60
        return String(format: "%02d:%02d", m, s)
    }
}

struct CellView: View {
    let cell: SudokuCell
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Rectangle()
                    .fill(cell.isSelected ? NeonTheme.selectedBg : NeonTheme.cellBg)
                    .aspectRatio(1, contentMode: .fit)
                
                if cell.value != 0 {
                    Text("\(cell.value)")
                        .font(.title3.weight(cell.isGiven ? .bold : .semibold))
                        .foregroundColor(
                            cell.isError ? NeonTheme.magentaGlow :
                            cell.isGiven ? .white : NeonTheme.cyanGlow
                        )
                        .shadow(color: cell.isError ? NeonTheme.magentaGlow : (cell.isGiven ? .clear : NeonTheme.cyanGlow), radius: 6)
                } else if !cell.notes.isEmpty {
                    VStack(spacing: 1) {
                        ForEach(0..<3) { r in
                            HStack(spacing: 1) {
                                ForEach(1...3) { c in
                                    let val = r * 3 + c
                                    Text(cell.notes.contains(val) ? "\(val)" : "")
                                        .font(.system(size: 8))
                                        .foregroundColor(NeonTheme.yellowGlow)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                        }
                    }
                    .padding(2)
                }
            }
            .border(Color.gray.opacity(0.2), lineWidth: 0.5)
        }
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    var isActive: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .foregroundColor(isActive ? NeonTheme.background : NeonTheme.cyanGlow)
            .frame(width: 65, height: 45)
            .background(isActive ? NeonTheme.cyanGlow : NeonTheme.cellBg)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(NeonTheme.cyanGlow, lineWidth: 1)
            )
            .shadow(color: NeonTheme.cyanGlow.opacity(0.4), radius: 4)
        }
    }
}

@main
struct NeonSudokuApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
