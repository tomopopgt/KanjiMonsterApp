import XCTest
@testable import KanjiMonsterApp

@MainActor
final class KanjiMonsterAppTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // テスト前に過去のセーブデータ（にがてノート等）を消去する
        UserDefaults.standard.removeObject(forKey: "KanjiGame_Save")
    }

    // ① 正解した時のスコア・コンボ・HP計算のテスト
    func testCorrectAnswer() throws {
        let game = GameManager()
        game.isMuted = true
        
        // 💡 無限ループを回避するため、最低4つのダミーデータを用意する！
        game.kanjiDatabase = [
            KanjiQuestion(kanji: "犬", reading: "いぬ", category: 0, difficulty: 0),
            KanjiQuestion(kanji: "猫", reading: "ねこ", category: 0, difficulty: 0),
            KanjiQuestion(kanji: "牛", reading: "うし", category: 0, difficulty: 0),
            KanjiQuestion(kanji: "馬", reading: "うま", category: 0, difficulty: 0)
        ]
        
        game.startGame() // ここでランダムな1問が出題される
        
        let initialScore = game.score
        let initialMonsterHP = game.monsterHP
        
        // 出題された問題の「正解の読み」をそのまま回答する
        let correctReading = game.currentCorrectReading
        game.checkAnswer(correctReading)
        
        // --- 検証 ---
        XCTAssertEqual(game.combo, 1, "正解したらコンボが1になること")
        XCTAssertTrue(game.score > initialScore, "正解したらスコアが増えること")
        XCTAssertEqual(game.correctQuestions, 1, "累計正解数が1になること")
        XCTAssertTrue(game.monsterHP < initialMonsterHP, "モンスターのHPがダメージを受けて減ること")
    }

    // ② 不正解した時のペナルティと「にがてノート」追加のテスト
    func testWrongAnswer() throws {
        let game = GameManager()
        game.isMuted = true
        
        game.kanjiDatabase = [
            KanjiQuestion(kanji: "犬", reading: "いぬ", category: 0, difficulty: 0),
            KanjiQuestion(kanji: "猫", reading: "ねこ", category: 0, difficulty: 0),
            KanjiQuestion(kanji: "牛", reading: "うし", category: 0, difficulty: 0),
            KanjiQuestion(kanji: "馬", reading: "うま", category: 0, difficulty: 0)
        ]
        
        game.startGame()
        game.combo = 3 // すでに3連続正解している状態をシミュレート
        
        // 現在の正解が「いぬ」なら「ねこ」、「ねこ」なら「いぬ」という風に、わざと間違った回答を生成する
        let wrongReading = game.currentCorrectReading == "いぬ" ? "ねこ" : "いぬ"
        game.checkAnswer(wrongReading)
        
        // --- 検証 ---
        XCTAssertEqual(game.combo, 0, "間違えたらコンボが0にリセットされること")
        XCTAssertFalse(game.isFever, "フィーバー状態が解除されること")
        XCTAssertEqual(game.wrongQuestions.count, 1, "にがてノートに1件追加されること")
        XCTAssertEqual(game.wrongQuestions.last?.kanji, game.currentKanji, "出題されていた漢字が記録されること")
    }
}
