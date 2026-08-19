import XCTest

final class KanjiMonsterAppUITests: XCTestCase {

    @MainActor
    func testGameStartFlow() throws {
        let app = XCUIApplication()
        app.launch()

        // 1. オープニング画面の「ぼうけん を はじめる！」ボタンを探してタップ
        let startAdventureButton = app.buttons["⚔️ ぼうけん を はじめる！"]
        if startAdventureButton.exists {
            startAdventureButton.tap()
        }

        // 2. メイン画面に遷移し、「バトル スタート！」ボタンが現れるか待機
        let battleStartButton = app.buttons["⚔️ バトル スタート！"]
        XCTAssertTrue(battleStartButton.waitForExistence(timeout: 3.0), "メイン画面にバトルスタートボタンが見つかりません")
        
        // 3. バトルスタートボタンをタップ
        battleStartButton.tap()
        
        // 4. バトル画面へ切り替わり、「もどる」ボタンが表示されるか確認
        let backButton = app.buttons["もどる"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 2.0), "バトル画面に正常に遷移していません")
        
        // 5. 「もどる」をタップして無事に設定画面に帰ってこれるか確認
        backButton.tap()
        XCTAssertTrue(battleStartButton.exists, "バトルからメイン画面に戻れませんでした")
    }
}
