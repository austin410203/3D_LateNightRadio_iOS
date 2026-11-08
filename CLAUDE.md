# 深夜電台 Late Night Radio — iOS 原生版（SwiftUI）

網頁版 `Gaming/LateNightRadio` 的原生 App（沒有 WebView）。規則、離線劇本、安全檢查是純 Swift（`Sources/LNRCore`，Linux Docker 也能編）；
畫面 SwiftUI；對話、即時生成來電者、語音都打同一個 Worker（https://radio.emptyoffice.app，標頭 `X-EO-App` 通過內部測試鎖，金鑰只在 Worker）。
Bundle ID `com.austin410203.latenightradio`。repo `austin410203/3D_LateNightRadio_iOS`（私人；跑 CI 時暫時公開，跑完改回私人：`python -I tools/gh.py visibility public|private`）。
commit 作者一律 Empty Office <hello@emptyoffice.app>。

**安全規則先讀網頁版 `LateNightRadio/docs/SAFETY.md`**（心理健康題材：三層危機偵測、求助專線、固定停止台詞、不提供醫療法律建議）。

## 結構
| 路徑 | 內容 |
|---|---|
| `Sources/LNRCore/Data.swift` | game.json 的資料型別、lineHash（預錄 mp3 檔名） |
| `Sources/LNRCore/Mock.swift` | JS 正規表示式轉換（\b 只認 ASCII）、安全檢查、離線劇本（mockllm.js 的 classify／mockReply／mockFollowup） |
| `Sources/LNRCore/Rules.swift` | 節目狀態 Show、數值規則（applyReply／outcomeOf／相遇）、抽池子、送給 LLM 的請求 |
| `Sources/coretest` | 用網頁匯出的 `Tests/golden.json` 對照（1047 項全過） |
| `App/Model.swift` | 節目流程（game.js 的原生版）：開播／繼續／換主題重新生成、接電話、主持人說話、聽眾簡訊、危機停止、收播 |
| `App/Net.swift` | Worker API：/api/health、/api/night、/api/llm、/api/tts、/audio/<hash>.mp3（快取） |
| `App/Voice.swift` | 台詞排隊播放（預錄 → Google 神經語音 → 手機語音）、電話音色、合成音效、合成 lo-fi 歌 |
| `App/Speech.swift` | 按住麥克風（SFSpeechRecognizer，支援的語言在手機上辨識）→ 文字進輸入框，改完再送出 |
| `App/Screens.swift` `Live.swift` `Sheets.swift` | 標題、集數卡、結算；播出中（場景＋線路抽屜＋通話面板）；通話紀錄、設定＋存檔、求助 |
| `App/Store.swift` | 設定、3 個存檔欄位（進度、統計、通話紀錄、遊玩紀錄），匯出／匯入 .json |
| `App/Extra.swift` | 原生專用的五語字串（其他字串在 game.json 的 ui） |
| `App/Autopilot.swift` | `-autotest tour`：離線劇本跑完一集＋第二集回電＋危機停止，截圖存 Documents/shots |
| `Resources/GameData/game.json` | 網頁匯出（`node ../LateNightRadio/tools/export_native.mjs`）：來電者、池子、離線劇本、安全、五語介面 |
| `Resources/Art` | dj.jpg、booth.jpg、callers/p00–p15.jpg（ChatGPT 4×4 頭像表切的） |

## 資料更新
網頁的 callers／mockllm／safety／i18n／lang_es 改了 → `C:\Users\Administrator\tools\node-v22.23.4-win-x64\node.exe ..\LateNightRadio\tools\export_native.mjs`
（寫 game.json＋Tests/golden.json）→ `sh tools/swift.sh`（Docker swift:6.2-noble 跑 coretest，CORE TEST PASS）。

## 測試
- 核心：`sh tools/swift.sh` → CORE TEST PASS。
- App 只能在雲端 Mac 編：repo 公開 → push → 結果在 `ci` 分支（errors.txt、shots/、es/、sim/）→ `sh tools/ci_fetch.sh` → 改回私人。
- 啟動參數：`-lang zh|en|ja|ko|es`、`-mock`（不連 Worker）、`-novoice`、`-fast`、`-autotest tour`。

## 語言
五語（繁中／英／日／韓／西），跟著手機語言（zh* → 繁中，其他沒有的 → 英文）。西語：介面、固定三位來電者、離線劇本、求助專線都有；
池子來電者只有四語，西語用英文頂替；即時生成（Haiku）直接寫西語。
