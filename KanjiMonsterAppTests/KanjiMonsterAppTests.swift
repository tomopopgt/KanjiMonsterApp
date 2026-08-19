import XCTest
@testable import KanjiMonsterApp

@MainActor
final class KanjiMonsterAppTests: XCTestCase {

    // ① 正解した時のスコア・コンボ・HP計算のテスト
    func testCorrectAnswer() throws {
        let game = GameManager()
        
        // テスト用に確実に「犬（いぬ）」が出題されるようにデータをセット
        game.kanjiDatabase = [
            KanjiQuestion(kanji: "犬", reading: "いぬ", category: 0, difficulty: 0)
        ]
        
        game.startGame()
        
        let initialScore = game.score
        let initialMonsterHP = game.monsterHP
        
        // 正解の文字列を選択したと仮定
        game.checkAnswer("いぬ")
        
        // --- XCTAssert を使って結果を検証 ---
        XCTAssertEqual(game.combo, 1, "正解したらコンボが1になること")
        XCTAssertTrue(game.score > initialScore, "正解したらスコアが増えること")
        XCTAssertEqual(game.correctQuestions, 1, "累計正解数が1増えること")
        XCTAssertTrue(game.monsterHP < initialMonsterHP, "モンスターのHPがダメージを受けて減ること")
    }

    // ② 不正解した時のペナルティと「にがてノート」追加のテスト
    func testWrongAnswer() throws {
        let game = GameManager()
        
        game.kanjiDatabase = [
            KanjiQuestion(kanji: "犬", reading: "いぬ", category: 0, difficulty: 0)
        ]
        game.startGame()
        game.combo = 3 // すでに3連続正解している状態をシミュレート
        
        // 不正解の文字列を選択したと仮定
        game.checkAnswer("ねこ")
        
        // --- 検証 ---
        XCTAssertEqual(game.combo, 0, "間違えたらコンボが0にリセットされること")
        XCTAssertFalse(game.isFever, "フィーバー状態が解除されること")
        XCTAssertEqual(game.wrongQuestions.count, 1, "にがてノートに追加されること")
        XCTAssertEqual(game.wrongQuestions.first?.kanji, "犬", "間違えた漢字が記録されること")
    }
}
