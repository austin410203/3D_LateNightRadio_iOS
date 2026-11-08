import SwiftUI
import UniformTypeIdentifiers
import LNRCore

struct SheetHost: View {
    @EnvironmentObject var m: GameModel
    let kind: SheetKind
    var body: some View {
        ZStack {
            Color.night.ignoresSafeArea()
            switch kind {
            case .history: HistoryView()
            case .settings: SettingsView()
            case .help(let fromStop): HelpView(fromStop: fromStop)
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color.night)
    }
}

private struct SheetHeader: View {
    @EnvironmentObject var m: GameModel
    let title: String
    var body: some View {
        HStack {
            Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(Color.paper)
            Spacer()
            Button { m.sheet = nil } label: { Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.paper).frame(width: 36, height: 36).background(Circle().fill(Color.white.opacity(0.1))) }
                .accessibilityLabel(m.t("close"))
        }.padding(.horizontal, 18).padding(.top, 18)
    }
}

/// 通話紀錄：每通電話的完整對話，依「第幾檔節目・第幾集」分組，可以分享成文字檔
struct HistoryView: View {
    @EnvironmentObject var m: GameModel
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: m.t("history"))
            let list = Array(m.saves.slot.transcripts.reversed())
            if list.isEmpty {
                Spacer(); Text(m.t("historyEmpty")).foregroundStyle(Color.dim).padding(30).multilineTextAlignment(.center); Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, r in
                            let head = m.t("showEp", ["s": "\(r.show)", "e": "\(r.ep)"])
                            if i == 0 || m.t("showEp", ["s": "\(list[i - 1].show)", "e": "\(list[i - 1].ep)"]) != head {
                                Text(head).font(.system(size: 13, weight: .semibold)).tracking(1.5).foregroundStyle(Color.dim).padding(.top, 8)
                            }
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(r.lines.enumerated()), id: \.offset) { _, l in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text(l[0] == "h" ? m.t("host") : l[0] == "c" ? r.name : "").font(.system(size: 12.5)).foregroundStyle(l[0] == "h" ? Color(red: 1, green: 0.6, blue: 0.64) : Color.amber).frame(width: 64, alignment: .leading)
                                            Text(l.count > 1 ? l[1] : "").font(.system(size: 14)).foregroundStyle(l[0] == "s" ? Color.dim : Color.paper)
                                        }
                                    }
                                }.padding(.top, 6)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.name).bold().foregroundStyle(Color.paper)
                                    Text("\(r.job)・\(r.phase == "callback" ? m.t("callbackCall") + (r.res.map { "・" + m.t("res_\($0)") } ?? "") : m.t("firstCall") + (r.plan.isEmpty ? "" : "・" + m.t("planLabel") + r.plan))・\(r.at.formatted(date: .numeric, time: .shortened))")
                                        .font(.system(size: 12)).foregroundStyle(Color.dim)
                                }
                            }
                            .tint(Color.amber).padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
                        }
                    }.padding(.horizontal, 16).padding(.bottom, 20)
                }
                ShareLink(item: m.historyText()) { Label(m.t("exportTxt"), systemImage: "square.and.arrow.up") }
                    .buttonStyle(SoftButton(big: true)).padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
    }
}

/// 設定＝選單：語言、語音、存檔欄位（使用／匯出／匯入／刪除）、隱私說明、回標題
struct SettingsView: View {
    @EnvironmentObject var m: GameModel
    @State private var sureDel = 0
    @State private var importInto = 0
    @State private var importing = false
    @State private var note = ""
    static let langNames = [("zh", "繁體中文"), ("en", "English"), ("ja", "日本語"), ("ko", "한국어"), ("es", "Español")]
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: m.t("settings"))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    row(m.t("language")) {
                        Picker("", selection: $m.settings.lang) { ForEach(Self.langNames, id: \.0) { Text($0.1).tag($0.0) } }.tint(Color.amber)
                    }
                    row(m.t("voiceOn")) { Toggle("", isOn: $m.settings.voice).tint(Color.onair).labelsHidden() }
                    Button { m.sheet = .history } label: { Label(m.t("history"), systemImage: "text.bubble.fill") }.buttonStyle(SoftButton())
                    Text(m.t("saves")).font(.system(size: 13, weight: .semibold)).tracking(1.5).foregroundStyle(Color.dim).padding(.top, 4)
                    ForEach(1...SaveStore.slots, id: \.self) { n in slot(n) }
                    Text(m.t("saveTip")).font(.system(size: 12)).foregroundStyle(Color.dim)
                    if !note.isEmpty { Text(note).font(.system(size: 13)).foregroundStyle(Color.vu) }
                    Text(m.t("privacyApp")).font(.system(size: 12.5)).foregroundStyle(Color.dim).fixedSize(horizontal: false, vertical: true)
                    if m.screen != .title {
                        Button(m.t("toTitle")) { m.sheet = nil; m.toTitle() }.buttonStyle(SoftButton(big: true))
                    }
                    Text(m.t("credits")).font(.system(size: 11)).foregroundStyle(Color.dim.opacity(0.7)).frame(maxWidth: .infinity)
                }.padding(18)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { r in
            guard case .success(let url) = r else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            if let d = try? Data(contentsOf: url), m.saves.importData(d, into: importInto) { note = m.t("impOk", ["n": "\(importInto)"]) } else { note = m.t("errBad") }
        }
    }
    func row<C: View>(_ label: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack { Text(label).foregroundStyle(Color.paper); Spacer(); c() }
            .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }
    func slot(_ n: Int) -> some View {
        let info = m.saves.summary(n)
        let active = m.saves.active == n
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(m.t("slotN", ["n": "\(n)"])).bold().foregroundStyle(Color.paper)
                if active { Text(m.t("inUse")).font(.system(size: 11, weight: .bold)).padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(Color.vu.opacity(0.2))).foregroundStyle(Color.vu) }
                Spacer()
            }
            Text(info.has ? m.t("slotInfo", ["e": "\(info.ep)", "n": "\(info.peak)"]) : m.t("emptySlot")).font(.system(size: 13)).foregroundStyle(Color.dim)
            if let d = info.saved { Text(m.t("lastSave", ["d": d.formatted(date: .numeric, time: .shortened)])).font(.system(size: 12)).foregroundStyle(Color.dim) }
            HStack(spacing: 6) {
                if !active { Button(m.t("useSlot")) { m.voice.stop(); m.saves.use(n); m.S = nil; m.screen = .title }.buttonStyle(SoftButton()) }
                if let d = m.saves.exportData(n), info.has || active {
                    ShareLink(item: ExportFile(data: d, name: "LateNightRadio_slot\(n).json"), preview: SharePreview("LateNightRadio_slot\(n).json")) { Text(m.t("exportS")) }.buttonStyle(SoftButton())
                }
                Button(m.t("importS")) { importInto = n; importing = true }.buttonStyle(SoftButton())
                if info.has {
                    Button(sureDel == n ? m.t("sure") : m.t("del")) {
                        if sureDel != n { sureDel = n; return }
                        sureDel = 0; m.saves.delete(n); if active { m.S = nil; m.screen = .title }
                    }.buttonStyle(SoftButton())
                }
            }
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(active ? 0.08 : 0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(active ? Color.vu.opacity(0.4) : Color.lineC))
    }
}

/// 存檔匯出成 .json 檔分享
struct ExportFile: Transferable {
    let data: Data
    let name: String
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { f in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(f.name)
            try f.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

/// 求助資訊（危機偵測停下電話時、或玩家自己按「需要協助？」）
struct HelpView: View {
    @EnvironmentObject var m: GameModel
    let fromStop: Bool
    var body: some View {
        let R = m.E.safety.resources(m.lang)
        VStack(spacing: 0) {
            SheetHeader(title: R.title)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(fromStop ? R.lead : R.note).foregroundStyle(Color.paper).fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(R.items.enumerated()), id: \.offset) { _, it in
                        if it.count >= 4, let url = URL(string: it[3]) {
                            Link(destination: url) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) { Text(it[0]).foregroundStyle(Color.paper); Text(it[2]).font(.system(size: 12)).foregroundStyle(Color.dim) }
                                    Spacer()
                                    Text(it[1]).font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(Color.vu)
                                }
                                .padding(14).background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
                            }
                        }
                    }
                    Text(R.emergency).font(.system(size: 14)).foregroundStyle(Color.amber)
                    if fromStop { Text(R.note).font(.system(size: 12)).foregroundStyle(Color.dim) }
                    Button(m.screen == .live ? m.t("helpBack") : m.t("helpClose")) { m.sheet = nil }.buttonStyle(PrimaryButton())
                    if m.screen == .live { Button(m.t("helpRest")) { m.sheet = nil; m.toTitle() }.buttonStyle(SoftButton(big: true)) }
                }.padding(18)
            }
        }
    }
}
