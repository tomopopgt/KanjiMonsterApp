import XCTest
@testable import KanjiMonsterApp

@MainActor
final class KanjiMonsterAppTests: XCTestCase {

    // ① 正解した時のスコア・コンボ・HP計算のテスト
    func testCorrectAnswer() throws {
        let game = GameManager()
        
        // 過去のセーブデータの影響を受けないように、テスト開始時点の数値を記録！
        let initialScore = game.score
        let initialCorrect = game.correctQuestions
        
        game.kanjiDatabase = [
            KanjiQuestion(kanji: "犬", reading: "いぬ", category: 0, difficulty: 0)
        ]
        
        game.startGame()
        let initialMonsterHP = game.monsterHP
        
        // 正解の文字列を選択
        game.checkAnswer("いぬ")
        
        // --- 検証 ---
        XCTAssertEqual(game.combo, 1, "正解したらコンボが1になること")
        XCTAssertTrue(game.score > initialScore, "正解したらスコアが増えること")
        XCTAssertEqual(game.correctQuestions, initialCorrect + 1, "累計正解数が今の状態から1増えること")
        XCTAssertTrue(game.monsterHP < initialMonsterHP, "モンスターのHPがダメージを受けて減ること")
    }

    // ② 不正解した時のペナルティと「にがてノート」追加のテスト
    func testWrongAnswer() throws {
        let game = GameManager()
        
        // ノートの件数も、テスト開始時点の数値を記録
        let initialWrongCount = game.wrongQuestions.count
        
        game.kanjiDatabase = [
            KanjiQuestion(kanji: "犬", reading: "いぬ", category: 0, difficulty: 0)
        ]
        game.startGame()
        game.combo = 3
        
        // 不正解の文字列を選択
        game.checkAnswer("ねこ")
        
        // --- 検証 ---
        XCTAssertEqual(game.combo, 0, "間違えたらコンボが0にリセットされること")
        XCTAssertFalse(game.isFever, "フィーバー状態が解除されること")
        XCTAssertEqual(game.wrongQuestions.count, initialWrongCount + 1, "にがてノートに1件追加されること")
        XCTAssertEqual(game.wrongQuestions.last?.kanji, "犬", "間違えた漢字が一番最後に記録されること")
    }
}
