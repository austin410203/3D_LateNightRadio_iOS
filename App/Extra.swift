// 原生 App 專用的字串（網頁 i18n.js 沒有的：麥克風權限、存檔欄位、隱私說明）。五語。
enum Extra {
    static let s: [String: [String: String]] = [
        "zh": [
            "micDenied": "需要麥克風和語音辨識權限：到 iPhone「設定 › 深夜電台」打開，或直接打字。",
            "autosaved": "已自動存檔（存檔 {n}）", "saves": "存檔", "slotN": "存檔 {n}", "inUse": "使用中", "emptySlot": "空的存檔欄位",
            "useSlot": "使用這個存檔", "exportS": "匯出", "importS": "匯入", "del": "刪除", "sure": "再按一次確定", "lastSave": "最後存檔：{d}",
            "impOk": "已匯入到存檔 {n}", "errBad": "這不是有效的存檔檔案", "slotInfo": "第 {e} 集・最多 {n} 人收聽",
            "saveTip": "進度會自動存到「使用中」的欄位。匯出成 .json 檔可以備份或換手機繼續玩。",
            "privacyApp": "按住麥克風時，語音辨識由 iPhone 處理（支援的語言在手機上完成，不經過網路）；我們的伺服器收不到你的聲音。即時模式只會送出文字（你這一句和最近幾句），這些文字用匿名代號保存 90 天，用來改進遊戲和檢查安全，不記聲音、不記 IP。",
            "share": "分享", "credits": "Empty Office 出品",
        ],
        "en": [
            "micDenied": "Microphone and speech recognition access are needed: turn them on in iPhone Settings › Late Night Radio, or just type.",
            "autosaved": "Auto-saved (slot {n})", "saves": "Saves", "slotN": "Slot {n}", "inUse": "In use", "emptySlot": "Empty slot",
            "useSlot": "Use this slot", "exportS": "Export", "importS": "Import", "del": "Delete", "sure": "Tap again to confirm", "lastSave": "Last saved: {d}",
            "impOk": "Imported into slot {n}", "errBad": "That isn’t a valid save file", "slotInfo": "Episode {e} · peak {n} listeners",
            "saveTip": "Progress saves automatically to the slot in use. Export a .json file to back up or move to another phone.",
            "privacyApp": "When you hold the mic, speech recognition is handled by your iPhone (on the device for supported languages); our server never receives your voice. Live mode sends only text (your line and the last few), kept for 90 days under an anonymous ID to improve the game and check safety; no audio and no IP address.",
            "share": "Share", "credits": "Made by Empty Office",
        ],
        "ja": [
            "micDenied": "マイクと音声認識の許可が必要です。iPhoneの「設定 › 深夜ラジオ」でオンにするか、入力してください。",
            "autosaved": "自動保存しました（スロット {n}）", "saves": "セーブ", "slotN": "スロット {n}", "inUse": "使用中", "emptySlot": "空きスロット",
            "useSlot": "このスロットを使う", "exportS": "書き出し", "importS": "読み込み", "del": "削除", "sure": "もう一度押して確定", "lastSave": "最終保存：{d}",
            "impOk": "スロット {n} に読み込みました", "errBad": "有効なセーブファイルではありません", "slotInfo": "第{e}回・最高 {n} 人",
            "saveTip": "進行状況は使用中のスロットに自動保存されます。.json に書き出すとバックアップや機種変更に使えます。",
            "privacyApp": "マイクを押している間の音声認識は iPhone が行います（対応言語は端末内で処理）。私たちのサーバーに声は届きません。ライブモードでは文字だけを送り、匿名IDで90日間保存してゲームの改善と安全確認に使います。音声とIPアドレスは保存しません。",
            "share": "共有", "credits": "Empty Office 制作",
        ],
        "ko": [
            "micDenied": "마이크와 음성 인식 권한이 필요해요. iPhone ‘설정 › 심야 라디오’에서 켜거나 직접 입력하세요.",
            "autosaved": "자동 저장했어요 (슬롯 {n})", "saves": "저장", "slotN": "슬롯 {n}", "inUse": "사용 중", "emptySlot": "빈 슬롯",
            "useSlot": "이 슬롯 사용", "exportS": "내보내기", "importS": "가져오기", "del": "삭제", "sure": "한 번 더 누르면 확정", "lastSave": "마지막 저장: {d}",
            "impOk": "슬롯 {n}에 가져왔어요", "errBad": "올바른 저장 파일이 아니에요", "slotInfo": "{e}회・최고 {n}명",
            "saveTip": "진행 상황은 사용 중인 슬롯에 자동 저장돼요. .json으로 내보내면 백업하거나 다른 폰에서 이어서 할 수 있어요.",
            "privacyApp": "마이크를 누르고 있을 때 음성 인식은 iPhone이 처리해요(지원 언어는 기기 안에서). 저희 서버는 목소리를 받지 않아요. 라이브 모드에서는 텍스트만 보내고, 익명 ID로 90일간 보관해 게임 개선과 안전 확인에 써요. 음성과 IP 주소는 저장하지 않아요.",
            "share": "공유", "credits": "Empty Office 제작",
        ],
        "es": [
            "micDenied": "Se necesita acceso al micrófono y al reconocimiento de voz: actívalo en Ajustes del iPhone › Radio de Medianoche, o escribe.",
            "autosaved": "Guardado automático (ranura {n})", "saves": "Partidas", "slotN": "Ranura {n}", "inUse": "En uso", "emptySlot": "Ranura vacía",
            "useSlot": "Usar esta ranura", "exportS": "Exportar", "importS": "Importar", "del": "Borrar", "sure": "Toca otra vez para confirmar", "lastSave": "Último guardado: {d}",
            "impOk": "Importado en la ranura {n}", "errBad": "No es un archivo de partida válido", "slotInfo": "Episodio {e} · máximo {n} oyentes",
            "saveTip": "El progreso se guarda solo en la ranura en uso. Exporta un .json para hacer copia o seguir en otro teléfono.",
            "privacyApp": "Mientras mantienes el micrófono, el reconocimiento de voz lo hace tu iPhone (en el dispositivo para los idiomas compatibles); nuestro servidor nunca recibe tu voz. El modo en vivo envía solo texto, que se guarda 90 días con un identificador anónimo para mejorar el juego y revisar la seguridad; sin audio ni dirección IP.",
            "share": "Compartir", "credits": "Hecho por Empty Office",
        ],
    ]
}
