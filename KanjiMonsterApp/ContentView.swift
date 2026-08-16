import SwiftUI
import AudioToolbox
import Combine
import AVFoundation
import UIKit

// MARK: - 漢字問題データ構造 (Codableを追加してJSON対応に)
struct KanjiQuestion: Codable, Hashable {
    let kanji: String          // 表示する漢字
    let reading: String        // 正解の読み
    let category: Int          // 0〜24のカテゴリ番号
    let difficulty: Int        // 0:かんたん, 1:ふつう, 2:むずかしい
}

struct SavedQuestion: Codable, Hashable {
    let kanji: String
    let reading: String
    let categoryName: String
}

struct MultiGameSaveData: Codable {
    var rank: Int; var stars: Int; var prestigePoints: Int; var prestigeCount: Int
    var ppAttackLevel: Int; var ppStarLevel: Int; var ppCritLevel: Int
    var unlockedMonsters: [Int]; var totalQuestions: Int; var correctQuestions: Int
    var bestTime: Double; var wrongQuestions: [SavedQuestion]
    var playDays: Set<String>
    var achievements: Set<String>
}

struct DamagePopup: Identifiable {
    let id = UUID()
    let amount: Int
    let isCrit: Bool
    var xOffset: CGFloat = CGFloat.random(in: -40...40)
    var yOffset: CGFloat = -20
    var opacity: Double = 1.0
}

// MARK: - ゲーム全体を統括するデータマネージャー
class GameManager: ObservableObject {
    @Published var isOpening = true
    @Published var rank = 1
    @Published var stars = 0
    @Published var prestigePoints = 0
    @Published var prestigeCount = 0
    @Published var ppAttackLevel = 0
    @Published var ppStarLevel = 0
    @Published var ppCritLevel = 0
    @Published var unlockedMonsters: Set<Int> = [0]
    
    @Published var totalQuestions = 0
    @Published var correctQuestions = 0
    @Published var bestTime: Double = 999.9
    @Published var wrongQuestions: [SavedQuestion] = []
    @Published var playDays: Set<String> = []
    @Published var achievements: Set<String> = []
    
    // 設定
    @Published var selectedCategory = 0
    @Published var selectedDifficulty = 0
    @Published var playMode = 0
    @Published var isMuted = false
    
    // バトル状態
    @Published var isPlaying = false
    @Published var currentKanji = "犬"
    @Published var currentCorrectReading = "いぬ"
    @Published var currentCategoryName = "どうぶつ"
    @Published var choices: [String] = []
    @Published var score = 0; @Published var combo = 0; @Published var isFever = false
    
    // 直前に出題した漢字（連続かぶり防止用）
    private var lastKanji: String = ""
    
    // タイムアタック
    @Published var timeAttackCount = 0; @Published var timeAttackElapsedTime: Double = 0.0
    var timeAttackStartTime: Date? = nil
    var timerSubscription: AnyCancellable?
    
    // モンスター＆演出
    @Published var monsterHP = 30; @Published var monsterMaxHP = 30; @Published var monsterIndex = 0
    @Published var monsterScale: CGFloat = 1.0
    @Published var effectText = ""; @Published var effectColor: Color = .green; @Published var showEffect = false
    @Published var damagePopups: [DamagePopup] = []
    @Published var showConfetti = false
    
    var activeAudioPlayers: [AVAudioPlayer] = []
    
    let monsters = ["👾", "🐉", "🤖", "👻", "🦄", "🦁", "🦖", "🦅", "👑", "🪼", "🐙", "🦈", "🥷", "🧙‍♂️", "🐺", "🧛‍♂️", "💣", "🌌"]
    let monsterNames = ["パズルモン", "ドラゴン", "ロボット", "おばけちゃん", "ユニコーン", "キングライオン", "ティラノくん", "イーグルキング", "かんじ神ゼウス", "クラゲっち", "クラーケン", "ホオジロサメ", "ニンジャ", "大魔導士", "ウルフマン", "ヴァンパイア", "メガトン爆弾", "宇宙大魔王"]
    
    // 全25ジャンル
    let categoryNames = [
        "どうぶつ 🦁", "こんちゅう 🦋", "のりもの 🚗", "たべもの 🍕", "きょうりゅう 🦖",
        "ファンタジー ⚔️", "てつどう 🚃", "げんそ 🧪", "サカナ 🐟", "ほし 🌟",
        "はな 🌸", "ペット 🐶", "とり 🦅", "かわのいきもの 🐸", "どうぶつえん 🐘",
        "てんたい 🔭", "かがく 🔬", "きしょう ☁️", "鉱物 💎", "しょくぶつ 🌿",
        "スポーツ ⚽️", "アート 🎨", "ゲーム 🎮", "料理 🍳", "歴史 📜"
    ]
    
    // JSONから読み込む空の配列（コード直書きデータはここに置き換わりました）
    @Published var kanjiDatabase: [KanjiQuestion] = []
    
    var isBoss: Bool { (monsterIndex + 1) % 10 == 0 }
    
    var rankTitle: String {
        switch rank {
        case 1: return "ルーキー"; case 2: return "ハンター"; case 3: return "マスター"; case 4: return "王者"; case 5...9: return "レジェンド"; default: return "漢字の神様"
        }
    }
    
    var accuracyRate: Int { totalQuestions > 0 ? Int((Double(correctQuestions) / Double(totalQuestions)) * 100) : 0 }
    var critRate: Double { min(0.50, Double(ppCritLevel) * 0.10) }
    var baseDamage: Int { (10 + (ppAttackLevel * 5) + (rank * 2)) * (isFever ? 2 : 1) }
    var starMultiplier: Int { (1 + ppStarLevel) * (isFever ? 2 : 1) }
    var earnedPPOnPrestige: Int { max(0, (rank - 4) * 10) }
    var ppAttackCost: Int { (ppAttackLevel + 1) * 10 }
    var ppStarCost: Int { (ppStarLevel + 1) * 15 }
    var ppCritCost: Int { (ppCritLevel + 1) * 20 }

    init() {
        setupAudioSession()
        loadData()
        recordPlayDay()
        setupTimer()
        loadKanjiDatabase() // 起動時にJSONを読み込む
    }
    
    func loadKanjiDatabase() {
        guard let url = Bundle.main.url(forResource: "kanji_data", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let questions = try? JSONDecoder().decode([KanjiQuestion].self, from: data) else {
            print("JSONの読み込みに失敗しました")
            return
        }
        self.kanjiDatabase = questions
    }
    
    func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AudioSession Setup Error: \(error)")
        }
    }
    
    func playSound(_ fileName: String) {
        if isMuted { return }
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "mp3") else { return }
        
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.5
            player.play()
            activeAudioPlayers.append(player)
            activeAudioPlayers.removeAll { !$0.isPlaying }
        } catch {
            print("Sound Play Error: \(error)")
        }
    }
    
    func recordPlayDay() {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        playDays.insert(today)
        saveData()
    }

    func setupTimer() {
        timerSubscription = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self = self, self.isPlaying && self.playMode == 1, let start = self.timeAttackStartTime else { return }
            self.timeAttackElapsedTime = Date().timeIntervalSince(start)
        }
    }

    func startAdventure() {
        playSound("clear")
        withAnimation(.easeOut(duration: 0.4)) { isOpening = false }
    }

    func startGame() {
        score = 0; combo = 0; isFever = false
        monsterIndex = 0
        setupNextMonster()
        timeAttackCount = 0; timeAttackElapsedTime = 0.0
        timeAttackStartTime = Date()
        isPlaying = true
        lastKanji = ""
        generateQuestion()
    }
    
    func setupNextMonster() {
        let hpBase = 30 + (rank * 10)
        monsterMaxHP = isBoss ? hpBase * 3 : hpBase
        monsterHP = monsterMaxHP
    }

    func quitGame() { isPlaying = false; damagePopups.removeAll() }

    func triggerHaptic(isCorrect: Bool) {
        if isMuted { return }
        if isCorrect {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        } else {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    func generateQuestion() {
        if kanjiDatabase.isEmpty { return } // 読み込み失敗時の安全対策
        
        if playMode == 2 && !wrongQuestions.isEmpty {
            let q = wrongQuestions.randomElement()!
            currentKanji = q.kanji
            currentCorrectReading = q.reading
            currentCategoryName = q.categoryName
        } else {
            // ランダムは番号25
            let cat = (selectedCategory == 25) ? Int.random(in: 0...24) : selectedCategory
            let diff = (selectedDifficulty == 3) ? Int.random(in: 0...2) : selectedDifficulty
            
            // 選択カテゴリと難易度で絞り込み
            let filtered = kanjiDatabase.filter { item in
                item.category == cat && item.difficulty == diff
            }
            let pool = filtered.isEmpty ? kanjiDatabase.filter { $0.category == cat } : filtered
            let finalPool = pool.isEmpty ? kanjiDatabase : pool
            
            // 直前と同じ漢字を除外するロジック
            let candidates = finalPool.filter { $0.kanji != lastKanji }
            let q = candidates.randomElement() ?? finalPool.randomElement()!
            
            currentKanji = q.kanji
            currentCorrectReading = q.reading
            currentCategoryName = (q.category < categoryNames.count) ? categoryNames[q.category] : "かんじ"
            lastKanji = q.kanji
        }

        // ダミー選択肢（誤答）の生成
        var dummyChoices: Set<String> = [currentCorrectReading]
        let allReadings = kanjiDatabase.map { $0.reading }
        
        while dummyChoices.count < 4 {
            if let candidate = allReadings.randomElement(), candidate != currentCorrectReading {
                dummyChoices.insert(candidate)
            }
        }
        choices = Array(dummyChoices).shuffled()
    }

    func checkAnswer(_ selected: String) {
        totalQuestions += 1
        if selected == currentCorrectReading {
            correctQuestions += 1; combo += 1
            if combo >= 5 {
                isFever = true
                unlockAchievement("5連コンボ達成！🔥")
            }
            if combo >= 10 { unlockAchievement("10連コンボの達人！⚡️") }
            
            wrongQuestions.removeAll { $0.kanji == currentKanji && $0.reading == currentCorrectReading }
            let isCrit = Double.random(in: 0...1) < critRate
            let damage = isCrit ? baseDamage * 2 : baseDamage
            
            score += 10 + (combo * 2); stars += 1 * starMultiplier
            monsterHP -= damage
            
            showDamagePopup(damage: damage, isCrit: isCrit)
            triggerHaptic(isCorrect: true)
            
            triggerEffect(text: isFever ? "🔥 FEVER!! せいかい！" : (isCrit ? "💥 バシッ！" : "🎉 せいかい！"), color: isFever ? .orange : .green)
            playSound("correct")

            withAnimation(.spring(response: 0.1, dampingFraction: 0.2)) { monsterScale = 0.7 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { withAnimation { self.monsterScale = self.isBoss ? 1.3 : 1.0 } }

            if playMode == 1 {
                timeAttackCount += 1
                if timeAttackCount >= 10 {
                    if timeAttackElapsedTime < bestTime { bestTime = timeAttackElapsedTime }
                    triggerEffect(text: String(format: "🏁 クリア！ %.1f秒!", timeAttackElapsedTime), color: .purple)
                    playSound("clear"); triggerConfetti()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.quitGame() }
                    saveData()
                    return
                }
            }

            if monsterHP <= 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self.generateQuestion()
                    self.defeatMonster()
                }
            } else { generateQuestion() }
        } else {
            combo = 0; isFever = false
            triggerEffect(text: "❌ おしい！", color: .red)
            triggerHaptic(isCorrect: false)
            playSound("wrong")
            let wrongQ = SavedQuestion(kanji: currentKanji, reading: currentCorrectReading, categoryName: currentCategoryName)
            if !wrongQuestions.contains(wrongQ) { wrongQuestions.append(wrongQ) }
        }
        saveData()
    }
    
    func showDamagePopup(damage: Int, isCrit: Bool) {
        let newPopup = DamagePopup(amount: damage, isCrit: isCrit)
        damagePopups.append(newPopup)
        let id = newPopup.id
        
        withAnimation(.easeOut(duration: 0.6)) {
            if let index = damagePopups.firstIndex(where: { $0.id == id }) {
                damagePopups[index].yOffset = -80
                damagePopups[index].opacity = 0.0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.damagePopups.removeAll { $0.id == id }
        }
    }

    func defeatMonster() {
        playSound("clear")
        triggerHaptic(isCorrect: true)
        if isBoss { triggerConfetti(); unlockAchievement("ボスモンスター討伐！👑") }
        unlockedMonsters.insert(monsterIndex % monsters.count)
        
        monsterIndex += 1; rank += 1
        setupNextMonster()
        
        triggerEffect(text: "🌟 たおした！ ランクUP! 🌟", color: .blue)
        saveData()
    }

    func triggerEffect(text: String, color: Color) {
        effectText = text; effectColor = color
        withAnimation { showEffect = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { withAnimation { self.showEffect = false } }
    }
    
    func triggerConfetti() {
        withAnimation { showConfetti = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.showConfetti = false }
    }
    
    func unlockAchievement(_ title: String) {
        if !achievements.contains(title) { achievements.insert(title); saveData() }
    }
    
    func buyPPAttack() { if prestigePoints >= ppAttackCost { prestigePoints -= ppAttackCost; ppAttackLevel += 1; saveData() } }
    func buyPPCrit() { if prestigePoints >= ppCritCost { prestigePoints -= ppCritCost; ppCritLevel += 1; saveData() } }
    func buyPPStar() { if prestigePoints >= ppStarCost { prestigePoints -= ppStarCost; ppStarLevel += 1; saveData() } }
    func performPrestige() { prestigePoints += earnedPPOnPrestige; prestigeCount += 1; rank = 1; unlockAchievement("はじめての『てんせい』✨"); saveData() }
    
    func saveData() {
        let data = MultiGameSaveData(
            rank: rank, stars: stars, prestigePoints: prestigePoints, prestigeCount: prestigeCount,
            ppAttackLevel: ppAttackLevel, ppStarLevel: ppStarLevel, ppCritLevel: ppCritLevel,
            unlockedMonsters: Array(unlockedMonsters), totalQuestions: totalQuestions,
            correctQuestions: correctQuestions, bestTime: bestTime, wrongQuestions: wrongQuestions,
            playDays: playDays, achievements: achievements
        )
        if let encoded = try? JSONEncoder().encode(data) { UserDefaults.standard.set(encoded, forKey: "KanjiGame_Save") }
    }
    
    func loadData() {
        if let savedData = UserDefaults.standard.data(forKey: "KanjiGame_Save"),
           let decoded = try? JSONDecoder().decode(MultiGameSaveData.self, from: savedData) {
            rank = decoded.rank; stars = decoded.stars; prestigePoints = decoded.prestigePoints; prestigeCount = decoded.prestigeCount
            ppAttackLevel = decoded.ppAttackLevel; ppStarLevel = decoded.ppStarLevel; ppCritLevel = decoded.ppCritLevel
            unlockedMonsters = Set(decoded.unlockedMonsters)
            totalQuestions = decoded.totalQuestions; correctQuestions = decoded.correctQuestions
            bestTime = decoded.bestTime; wrongQuestions = decoded.wrongQuestions
            playDays = decoded.playDays; achievements = decoded.achievements
        }
    }
}

// MARK: - 🎨 目に優しいカラーパレット
struct EyeFriendlyTheme {
    static func bgGradient(_ scheme: ColorScheme) -> [Color] {
        scheme == .dark ?
            [Color(red: 0.12, green: 0.14, blue: 0.18), Color(red: 0.18, green: 0.20, blue: 0.26)] :
            [Color(red: 0.96, green: 0.95, blue: 0.91), Color(red: 0.92, green: 0.94, blue: 0.96)]
    }
    
    static func cardBg(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.22, green: 0.24, blue: 0.30) : Color.white
    }
    
    static func textPrimary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.92, green: 0.93, blue: 0.96) : Color(red: 0.20, green: 0.22, blue: 0.28)
    }
}

// MARK: - メイン View
struct ContentView: View {
    @StateObject private var game = GameManager()
    var body: some View {
        Group {
            if game.isOpening { OpeningView() }
            else if game.isPlaying { BattleView() }
            else { MainTabView() }
        }
        .environmentObject(game)
    }
}

// MARK: - 紙吹雪 View
struct ConfettiView: View {
    let colors: [Color] = [.red, .blue, .green, .yellow, .orange, .purple, .pink]
    @State private var animate = false
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<40, id: \.self) { _ in
                    Circle()
                        .fill(colors.randomElement()!)
                        .frame(width: CGFloat.random(in: 8...15), height: CGFloat.random(in: 8...15))
                        .position(x: CGFloat.random(in: 0...geo.size.width),
                                  y: animate ? geo.size.height + 100 : -100)
                        .animation(Animation.linear(duration: Double.random(in: 1.5...3.0)).delay(Double.random(in: 0...0.5)), value: animate)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { animate = true }
    }
}

// MARK: - オープニング画面
struct OpeningView: View {
    @EnvironmentObject var game: GameManager
    @Environment(\.colorScheme) var scheme
    @State private var isBouncing = false; @State private var isPulsing = false
    
    var body: some View {
        ZStack {
            LinearGradient(colors: EyeFriendlyTheme.bgGradient(scheme), startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 30) {
                Spacer()
                VStack(spacing: 14) {
                    Text("⚔️ かんじ 👑").font(.system(size: 38, weight: .black, design: .rounded)).foregroundColor(.orange)
                    Text("モンスターズ").font(.system(size: 56, weight: .black, design: .rounded)).foregroundColor(EyeFriendlyTheme.textPrimary(scheme)).shadow(color: scheme == .dark ? .black : .white, radius: 4).minimumScaleFactor(0.8)
                    Text("〜 かんじ の よみかた で モンスター を たおせ！ 〜").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(.gray)
                }
                .padding(.vertical, 32).padding(.horizontal, 24).background(RoundedRectangle(cornerRadius: 30).fill(EyeFriendlyTheme.cardBg(scheme)).shadow(color: .black.opacity(0.15), radius: 10, y: 5))
                .scaleEffect(isBouncing ? 1.05 : 0.95)

                HStack(spacing: 18) {
                    Text("👾").font(.system(size: 70)).offset(y: isBouncing ? -12 : 12)
                    Text("🐉").font(.system(size: 80)).offset(y: isBouncing ? 12 : -12)
                    Text("🤖").font(.system(size: 70)).offset(y: isBouncing ? -12 : 12)
                    Text("👑").font(.system(size: 75)).offset(y: isBouncing ? 12 : -12)
                }.padding(.vertical, 10)

                Spacer()
                Button { game.startAdventure() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text("⚔️ ぼうけん を はじめる！")
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Image(systemName: "sparkles")
                    }
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                    .background(RoundedRectangle(cornerRadius: 22).fill(LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom)).shadow(color: .orange.opacity(0.6), radius: 8, y: 4))
                }
                .padding(.horizontal, 24).scaleEffect(isPulsing ? 1.06 : 0.98)
                Spacer()
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { isBouncing = true }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { isPulsing = true }
        }
    }
}

// MARK: - メインタブ画面
struct MainTabView: View {
    @EnvironmentObject var game: GameManager
    @Environment(\.colorScheme) var scheme
    
    var body: some View {
        ZStack {
            LinearGradient(colors: EyeFriendlyTheme.bgGradient(scheme), startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 0) {
                HeaderStatusCard()
                TabView {
                    HomeBattleView().tabItem { Label("バトル", systemImage: "gamecontroller.fill") }
                    MistakeNoteView().tabItem { Label("にがて", systemImage: "square.and.pencil") }.badge(game.wrongQuestions.count)
                    EncyclopediaView().tabItem { Label("ずかん", systemImage: "book.fill") }
                    PrestigeShopView().tabItem { Label("てんせい", systemImage: "bolt.shield.fill") }
                    ParentReportView().tabItem { Label("ほごしゃ", systemImage: "chart.bar.doc.horizontal") }
                }
            }
        }
    }
}

// MARK: - 保護者レポート
struct ParentReportView: View {
    @EnvironmentObject var game: GameManager
    @Environment(\.colorScheme) var scheme
    
    var analysisMessage: String {
        if game.totalQuestions < 10 { return "もっとたくさん遊んでデータを集めよう！" }
        if game.accuracyRate > 90 { return "すばらしい正答率です！この調子で難易度を上げて挑戦してみましょう。" }
        if !game.wrongQuestions.isEmpty {
            let mostWrongCat = game.wrongQuestions.map { $0.categoryName }.reduce(into: [:]) { $0[$1, default: 0] += 1 }.max(by: { $0.value < $1.value })?.key
            if let cat = mostWrongCat { return "分析：「\(cat)」ジャンルでつまずきやすい傾向があります。にがてノートで復習しましょう。" }
        }
        return "毎日少しずつ続けることが大切です。まずはスタンプを集めましょう！"
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("👨‍👩‍👦 保護者向けレポート").font(.title2).bold().foregroundColor(EyeFriendlyTheme.textPrimary(scheme))
                
                HStack(spacing: 20) {
                    VStack { Text("プレイ日数").font(.subheadline).foregroundColor(.gray); Text("\(game.playDays.count) 日").font(.title).bold().foregroundColor(.orange) }
                    Divider().frame(height: 40)
                    VStack { Text("総クリア数").font(.subheadline).foregroundColor(.gray); Text("\(game.correctQuestions) 問").font(.title).bold().foregroundColor(.blue) }
                }.padding(20).frame(maxWidth: .infinity).background(EyeFriendlyTheme.cardBg(scheme)).cornerRadius(16).shadow(color: .black.opacity(0.05), radius: 4)
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Image(systemName: "sparkles"); Text("AI ぶんせき アドバイス") }.font(.headline).bold().foregroundColor(.purple)
                    Text(analysisMessage).font(.body).foregroundColor(EyeFriendlyTheme.textPrimary(scheme))
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color.purple.opacity(scheme == .dark ? 0.25 : 0.1)).cornerRadius(16)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("🏅 かくとくトロフィー (\(game.achievements.count)個)").font(.headline).bold().foregroundColor(.gray)
                    if game.achievements.isEmpty {
                        Text("まだトロフィーはありません。ゲームを遊んでゲットしよう！").font(.subheadline).foregroundColor(.gray).padding(.vertical, 10)
                    } else {
                        ForEach(Array(game.achievements), id: \.self) { title in
                            HStack { Text("🏆").font(.title2); Text(title).font(.headline).bold().foregroundColor(EyeFriendlyTheme.textPrimary(scheme)) }
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(EyeFriendlyTheme.cardBg(scheme)).cornerRadius(12).shadow(color: .black.opacity(0.05), radius: 2)
                        }
                    }
                }
            }.padding(20)
        }
    }
}

// MARK: - ステータスヘッダー
struct HeaderStatusCard: View {
    @EnvironmentObject var game: GameManager
    @Environment(\.colorScheme) var scheme
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("👑 ランク \(game.rank) : \(game.rankTitle)")
                    .font(.title3)
                    .bold()
                    .foregroundColor(Color(red: 0.9, green: 0.5, blue: 0.1))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                
                if game.prestigeCount > 0 {
                    Text("🎖️ てんせい \(game.prestigeCount) かいめ")
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(.purple)
                }
            }
            Spacer()
            Button { game.isMuted.toggle() } label: { Image(systemName: game.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.title3).foregroundColor(game.isMuted ? .gray : .blue).padding(10).background(Circle().fill(Color.gray.opacity(0.2))) }
            VStack(alignment: .trailing, spacing: 4) { Text("⭐ \(game.stars) スター").font(.headline).bold().foregroundColor(EyeFriendlyTheme.textPrimary(scheme)); Text("✨ \(game.prestigePoints) PP").font(.headline).bold().foregroundColor(.purple) }
        }.padding(.horizontal, 16).padding(.vertical, 14).background(EyeFriendlyTheme.cardBg(scheme)).shadow(color: .black.opacity(0.08), radius: 3, y: 2)
    }
}

// MARK: - 汎用選択ボタン
struct SelectionButton: View {
    let title: String
    let isSelected: Bool
    var activeColors: [Color] = [Color(red: 0.2, green: 0.5, blue: 0.95), Color(red: 0.35, green: 0.3, blue: 0.85)]
    let action: () -> Void
    @Environment(\.colorScheme) var scheme
    
    private var primaryThemeColor: Color { activeColors.first ?? Color.blue }
    private var strokeColor: Color { isSelected ? primaryThemeColor.opacity(0.8) : Color.gray.opacity(scheme == .dark ? 0.3 : 0.15) }
    private var shadowColor: Color { isSelected ? primaryThemeColor.opacity(0.4) : Color.black.opacity(0.04) }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .minimumScaleFactor(0.8)
                .lineLimit(1)
                .foregroundColor(isSelected ? .white : EyeFriendlyTheme.textPrimary(scheme))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    ZStack {
                        if isSelected {
                            LinearGradient(colors: activeColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                        } else {
                            EyeFriendlyTheme.cardBg(scheme)
                        }
                    }
                )
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(strokeColor, lineWidth: isSelected ? 2 : 1))
                .shadow(color: shadowColor, radius: isSelected ? 8 : 3, x: 0, y: isSelected ? 4 : 2)
        }
    }
}

// MARK: - 画面1: バトル設定
struct HomeBattleView: View {
    @EnvironmentObject var game: GameManager
    @Environment(\.colorScheme) var scheme
    
    let purpleTheme: [Color] = [Color(red: 0.55, green: 0.3, blue: 0.9), Color(red: 0.4, green: 0.15, blue: 0.8)]
    let blueTheme: [Color] = [Color(red: 0.2, green: 0.55, blue: 0.95), Color(red: 0.1, green: 0.35, blue: 0.85)]
    let greenTheme: [Color] = [Color(red: 0.2, green: 0.75, blue: 0.4), Color(red: 0.1, green: 0.6, blue: 0.3)]
    let orangeTheme: [Color] = [Color(red: 1.0, green: 0.55, blue: 0.15), Color(red: 0.9, green: 0.4, blue: 0.05)]
    let redTheme: [Color] = [Color(red: 0.95, green: 0.25, blue: 0.3), Color(red: 0.8, green: 0.1, blue: 0.2)]
    let deepPurpleTheme: [Color] = [Color(red: 0.65, green: 0.2, blue: 0.85), Color(red: 0.45, green: 0.1, blue: 0.7)]
    
    private var startButtonColors: [Color] {
        game.playMode == 1 ? [Color(red: 0.65, green: 0.15, blue: 0.9), Color(red: 0.45, green: 0.05, blue: 0.75)] : [Color(red: 1.0, green: 0.35, blue: 0.1), Color(red: 0.85, green: 0.15, blue: 0.05)]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("🎮 ゲームモード").font(.headline).bold().foregroundColor(EyeFriendlyTheme.textPrimary(scheme))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        SelectionButton(title: "のんびり", isSelected: game.playMode == 0, activeColors: purpleTheme) { game.playMode = 0 }
                        SelectionButton(title: "10もんタイム", isSelected: game.playMode == 1, activeColors: purpleTheme) { game.playMode = 1 }
                    }
                }.padding(.horizontal)

                VStack(alignment: .leading, spacing: 12) {
                    Text("📚 ジャンル（カテゴリ）").font(.headline).bold().foregroundColor(EyeFriendlyTheme.textPrimary(scheme))
                    
                    ScrollView(showsIndicators: true) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(0..<game.categoryNames.count, id: \.self) { index in
                                SelectionButton(title: game.categoryNames[index], isSelected: game.selectedCategory == index, activeColors: blueTheme) {
                                    game.selectedCategory = index
                                }
                            }
                            
                            SelectionButton(title: "🎲 ランダム", isSelected: game.selectedCategory == 25, activeColors: deepPurpleTheme) {
                                game.selectedCategory = 25
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                    }
                    .frame(maxHeight: 260)
                    .background(EyeFriendlyTheme.cardBg(scheme))
                    .cornerRadius(16)
                    .overlay(
                        VStack {
                            LinearGradient(colors: [EyeFriendlyTheme.cardBg(scheme), Color.clear], startPoint: .top, endPoint: .bottom).frame(height: 12)
                            Spacer()
                            LinearGradient(colors: [Color.clear, EyeFriendlyTheme.cardBg(scheme)], startPoint: .top, endPoint: .bottom).frame(height: 12)
                        }
                        .allowsHitTesting(false)
                    )
                }.padding(.horizontal)

                VStack(alignment: .leading, spacing: 12) {
                    Text("🔥 むずかしさ").font(.headline).bold().foregroundColor(EyeFriendlyTheme.textPrimary(scheme))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        SelectionButton(title: "🟢 かんたん", isSelected: game.selectedDifficulty == 0, activeColors: greenTheme) { game.selectedDifficulty = 0 }
                        SelectionButton(title: "🟡 ふつう", isSelected: game.selectedDifficulty == 1, activeColors: orangeTheme) { game.selectedDifficulty = 1 }
                        SelectionButton(title: "🔴 むずかしい", isSelected: game.selectedDifficulty == 2, activeColors: redTheme) { game.selectedDifficulty = 2 }
                        SelectionButton(title: "🎲 ランダム", isSelected: game.selectedDifficulty == 3, activeColors: deepPurpleTheme) { game.selectedDifficulty = 3 }
                    }
                }.padding(.horizontal)

                Button { game.startGame() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                        Text(game.playMode == 1 ? "⏱️ タイムアタック スタート！" : "⚔️ バトル スタート！")
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 68)
                    .background(LinearGradient(colors: startButtonColors, startPoint: .top, endPoint: .bottom))
                    .cornerRadius(22)
                    .shadow(color: (game.playMode == 1 ? Color.purple : Color.red).opacity(0.5), radius: 12, x: 0, y: 6)
                }
                .padding(.horizontal)
                .padding(.top, 10)
            }.padding(.vertical, 20)
        }
    }
}

// MARK: - 画面2: にがてノート
struct MistakeNoteView: View {
    @EnvironmentObject var game: GameManager
    @Environment(\.colorScheme) var scheme
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if game.wrongQuestions.isEmpty {
                    VStack(spacing: 16) { Text("🎉").font(.system(size: 80)); Text("にがてな かんじは ないよ！すごい！").font(.title2).bold().foregroundColor(.green) }.padding(40)
                } else {
                    Button { game.playMode = 2; game.startGame() } label: { HStack { Image(systemName: "flame.fill"); Text("にがて を こくふく バトル！ (\(game.wrongQuestions.count)問)") }.font(.title2).bold().foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 64).background(Color.red).cornerRadius(20) }.padding(.horizontal)
                    ForEach(game.wrongQuestions, id: \.self) { q in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("📝 \(q.kanji)").font(.title2).bold().foregroundColor(EyeFriendlyTheme.textPrimary(scheme))
                                Text("よみ: \(q.reading)").font(.headline).foregroundColor(.orange)
                            }
                            Spacer()
                            Text(q.categoryName).font(.subheadline).bold().foregroundColor(.gray)
                        }.padding(20).background(EyeFriendlyTheme.cardBg(scheme)).cornerRadius(16).padding(.horizontal)
                    }
                }
            }.padding(.top, 20)
        }
    }
}

// MARK: - 画面3: モンスターずかん
struct EncyclopediaView: View {
    @EnvironmentObject var game: GameManager
    @Environment(\.colorScheme) var scheme
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(0..<game.monsters.count, id: \.self) { idx in
                    let isUnlocked = game.unlockedMonsters.contains(idx)
                    VStack(spacing: 10) { Text(isUnlocked ? game.monsters[idx] : "❓").font(.system(size: 70)).opacity(isUnlocked ? 1 : 0.3); Text(isUnlocked ? game.monsterNames[idx] : "？？？？？").font(.headline).bold().foregroundColor(isUnlocked ? EyeFriendlyTheme.textPrimary(scheme) : .gray) }.frame(maxWidth: .infinity).frame(height: 130).background(EyeFriendlyTheme.cardBg(scheme)).cornerRadius(18)
                }
            }.padding()
        }
    }
}

// MARK: - 画面4: てんせい ＆ ショップ
struct PrestigeShopView: View {
    @EnvironmentObject var game: GameManager
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Button(action: game.performPrestige) { VStack(spacing: 6) { if game.rank >= 5 { Text("🔄 てんせい（強ニュー）を行う").font(.title2).bold(); Text("ランクはリセット ＆ +\(game.earnedPPOnPrestige) PP かくとく！").font(.headline) } else { Text("🔒 てんせい は ランク5 で解放！").font(.title2).bold(); Text("現在のランク: \(game.rank) / 5").font(.headline) } }.foregroundColor(.white).frame(maxWidth: .infinity).padding(20).background(game.rank >= 5 ? Color.purple : Color.gray).cornerRadius(20) }.disabled(game.rank < 5)
                VStack(spacing: 16) {
                    UpgradeRow(title: "⚔️ こうげきりょくUP (現在: +\(game.ppAttackLevel * 5))", subtitle: "せいかいのダメージ増加", costText: "✨ \(game.ppAttackCost) PP", canAfford: game.prestigePoints >= game.ppAttackCost, action: game.buyPPAttack)
                    UpgradeRow(title: "💥 クリティカルUP (現在: \(Int(game.critRate * 100))%)", subtitle: "2ばいダメージ発動率", costText: "✨ \(game.ppCritCost) PP", canAfford: game.prestigePoints >= game.ppCritCost, action: game.buyPPCrit)
                    UpgradeRow(title: "⭐ スターばいりつUP (現在: \(game.starMultiplier)ばい)", subtitle: "獲得スター量増加", costText: "✨ \(game.ppStarCost) PP", canAfford: game.prestigePoints >= game.ppStarCost, action: game.buyPPStar)
                }
            }.padding()
        }
    }
}

// MARK: - 画面5: 全画面バトルView
struct BattleView: View {
    @EnvironmentObject var game: GameManager
    @Environment(\.colorScheme) var scheme
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: game.isBoss ? [Color.red.opacity(0.8), Color.black.opacity(0.9)] :
                        (game.isFever ? [Color.yellow.opacity(0.8), Color.orange.opacity(0.9)] : EyeFriendlyTheme.bgGradient(scheme)),
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()
            
            VStack(spacing: 12) {
                HStack {
                    Button(action: game.quitGame) {
                        HStack(spacing: 4) {
                            Image(systemName: "house.fill")
                            Text("もどる")
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                        .font(.title3)
                        .bold()
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.red))
                    }
                    Spacer()
                    if game.playMode == 1 { Text(String(format: "⏱️ %.1f秒 (%d/10)", game.timeAttackElapsedTime, game.timeAttackCount)).font(.system(.title3, design: .monospaced)).bold().foregroundColor(.purple).padding(10).background(Capsule().fill(EyeFriendlyTheme.cardBg(scheme))) } else if game.combo > 1 { Text(game.isFever ? "🔥 FEVER 2倍! (\(game.combo)連)" : "🔥 \(game.combo) れんぞく！").font(.title3).bold().foregroundColor(game.isFever ? .red : .orange).padding(8).background(Capsule().fill(Color.yellow.opacity(0.4))) }
                    Spacer()
                    HStack(spacing: 6) { Text("⭐ \(game.stars)"); Text("得点: \(game.score)") }.font(.title3).bold().foregroundColor(EyeFriendlyTheme.textPrimary(scheme)).padding(10).background(Capsule().fill(EyeFriendlyTheme.cardBg(scheme)))
                }.padding(.horizontal).padding(.top, 12)

                ZStack {
                    VStack(spacing: 4) {
                        Text(game.isBoss ? "⚠️ \(game.monsterNames[game.monsterIndex % game.monsters.count]) (BOSS) ⚠️" : game.monsterNames[game.monsterIndex % game.monsters.count]).font(.title).bold().foregroundColor(game.isBoss ? .white : EyeFriendlyTheme.textPrimary(scheme))
                        Text(game.monsters[game.monsterIndex % game.monsters.count]).font(.system(size: game.isBoss ? 150 : 110)).scaleEffect(game.monsterScale).shadow(color: game.isBoss ? .red : .clear, radius: 10)
                        GeometryReader { geo in ZStack(alignment: .leading) { RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.3)); RoundedRectangle(cornerRadius: 12).fill(game.isFever ? Color.orange : Color.green).frame(width: geo.size.width * (CGFloat(max(game.monsterHP, 0)) / CGFloat(game.monsterMaxHP))) } }.frame(width: 260, height: 20)
                    }
                    
                    ForEach(game.damagePopups) { popup in
                        Text("-\(popup.amount)\(popup.isCrit ? "!!" : "")")
                            .font(.system(size: popup.isCrit ? 56 : 40, weight: .black, design: .rounded))
                            .foregroundColor(popup.isCrit ? .orange : .red)
                            .shadow(color: .white, radius: 3)
                            .offset(x: popup.xOffset, y: popup.yOffset)
                            .opacity(popup.opacity)
                            .allowsHitTesting(false)
                    }
                }

                ZStack { if game.showEffect { Text(game.effectText).font(.system(size: 38, weight: .black)).foregroundColor(game.effectColor) } }.frame(height: 50)

                VStack(spacing: 8) {
                    Text("この かんじ の よみかた は？")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.gray)
                    Text(game.currentKanji)
                        .font(.system(size: 72, weight: .black, design: .rounded))
                        .foregroundColor(EyeFriendlyTheme.textPrimary(scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 30)
                .background(RoundedRectangle(cornerRadius: 28).fill(EyeFriendlyTheme.cardBg(scheme)).shadow(radius: 6))

                Spacer()

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                    ForEach(game.choices, id: \.self) { choice in
                        Button { game.checkAnswer(choice) } label: {
                            Text(choice)
                                .font(.system(size: 32, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 84)
                                .background(RoundedRectangle(cornerRadius: 22).fill(game.isFever ? Color.red : Color.orange))
                        }
                    }
                }.padding(.horizontal, 24).padding(.bottom, 36)
            }
            
            if game.showConfetti { ConfettiView() }
        }
    }
}

// MARK: - 光るアップグレード行
struct UpgradeRow: View {
    let title: String; let subtitle: String; let costText: String; let canAfford: Bool; let action: () -> Void
    @Environment(\.colorScheme) var scheme
    @State private var isGlowing = false
    var body: some View {
        Button(action: action) { HStack { VStack(alignment: .leading, spacing: 6) { Text(title).font(.title3).bold().foregroundColor(canAfford ? EyeFriendlyTheme.textPrimary(scheme) : .gray); Text(subtitle).font(.subheadline).foregroundColor(.gray) }; Spacer(); Text(costText).font(.title3).bold().foregroundColor(canAfford ? .orange : .gray) }.padding(20).background(canAfford ? Color.yellow.opacity(scheme == .dark ? 0.2 : 0.15) : EyeFriendlyTheme.cardBg(scheme)).cornerRadius(16).overlay(RoundedRectangle(cornerRadius: 16).stroke(canAfford ? Color.orange.opacity(isGlowing ? 0.8 : 0.2) : Color.clear, lineWidth: 3)).shadow(color: canAfford ? Color.orange.opacity(isGlowing ? 0.4 : 0.0) : Color.black.opacity(0.05), radius: 5, y: 3) }.disabled(!canAfford)
        .onAppear { withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { isGlowing = true } }
    }
}

#Preview { ContentView() }
