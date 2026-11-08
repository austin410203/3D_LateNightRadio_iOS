import SwiftUI
import UIKit
import LNRCore

// 深夜藍＋錄音燈紅＋VU 綠（照網頁 style.css）
extension Color {
    static let night = Color(red: 0.043, green: 0.063, blue: 0.125)
    static let glass = Color(red: 0.04, green: 0.055, blue: 0.10).opacity(0.84)
    static let paper = Color(red: 0.953, green: 0.929, blue: 0.878)
    static let dim = Color(red: 0.604, green: 0.639, blue: 0.710)
    static let amber = Color(red: 0.957, green: 0.635, blue: 0.380)
    static let onair = Color(red: 0.902, green: 0.224, blue: 0.275)
    static let vu = Color(red: 0.502, green: 0.929, blue: 0.600)
    static let lineC = Color.white.opacity(0.10)
}

/// Resources/Art 裡的圖（dj.jpg、booth.jpg、callers/p00–p15.jpg）
enum Art {
    static var cache: [String: UIImage] = [:]
    static func img(_ name: String) -> UIImage {
        if let i = cache[name] { return i }
        let path = Bundle.main.path(forResource: name, ofType: "jpg", inDirectory: "Art") ?? Bundle.main.path(forResource: name, ofType: "jpg", inDirectory: "Art/callers")
        let i = path.flatMap(UIImage.init(contentsOfFile:)) ?? UIImage()
        cache[name] = i
        return i
    }
}

struct Portrait: View {
    let name: String
    var size: CGFloat = 48
    var radius: CGFloat = 12
    var body: some View {
        Image(uiImage: Art.img(name)).resizable().scaledToFill()
            .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct PrimaryButton: ButtonStyle {
    var color: Color = .onair
    var big = true
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.system(size: big ? 19 : 15, weight: .bold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: big ? 56 : 44)
            .background(Capsule().fill(color.opacity(c.isPressed ? 0.8 : 1)))
            .shadow(color: color.opacity(0.45), radius: 10, y: 3)
            .scaleEffect(c.isPressed ? 0.97 : 1)
    }
}
struct SoftButton: ButtonStyle {
    var big = false
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.system(size: big ? 18 : 14, weight: .semibold)).foregroundStyle(Color.amber)
            .frame(maxWidth: big ? .infinity : nil, minHeight: big ? 56 : 40).padding(.horizontal, big ? 0 : 14)
            .background(Capsule().fill(Color.amber.opacity(c.isPressed ? 0.25 : 0.14)))
            .overlay(Capsule().stroke(Color.amber.opacity(0.4)))
    }
}
struct ToolButton: View {
    let icon: String, label: String, action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) { Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Color.amber); Text(label).font(.system(size: 13)).foregroundStyle(Color.paper) }
                .frame(maxWidth: .infinity, minHeight: 62)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.09)))
        }.buttonStyle(.plain)
    }
}
struct Card<C: View>: View {
    @ViewBuilder var content: C
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.glass))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.lineC))
    }
}

/// 背景：錄音室窗外的夜景（網頁的 booth.jpg）
struct Backdrop: View {
    var body: some View {
        GeometryReader { g in
            Image(uiImage: Art.img("booth")).resizable().scaledToFill().frame(width: g.size.width, height: g.size.height).clipped()
                .overlay(LinearGradient(colors: [Color.night.opacity(0.55), Color.night.opacity(0.25), Color.night.opacity(0.75)], startPoint: .top, endPoint: .bottom))
        }.ignoresSafeArea()
    }
}

/// 今晚主題選單（標題、結算各一份）：隨機＋五種＋自訂（自訂按「送出」就馬上生成來電者）
struct ThemePicker: View {
    @EnvironmentObject var m: GameModel
    var go: () -> Void
    @FocusState private var focus: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(m.t("themeAsk")).font(.system(size: 13.5)).foregroundStyle(Color.dim)
            FlowLayout(spacing: 6) {
                ForEach(GameData.themeOrder + ["custom"], id: \.self) { k in
                    let on = m.settings.theme == k
                    Button {
                        m.settings.theme = k
                        if k == "custom" { focus = true }
                    } label: {
                        HStack(spacing: 4) {
                            if k == "custom" { Image(systemName: "pencil").font(.system(size: 12)) }
                            Text(m.t("theme_\(k)"))
                        }
                        .font(.system(size: 13.5, weight: on ? .bold : .regular))
                        .foregroundStyle(on ? Color(red: 0.1, green: 0.08, blue: 0.03) : Color.paper)
                        .padding(.horizontal, 12).frame(minHeight: 36)
                        .background(Capsule().fill(on ? Color.amber : Color.clear))
                        .overlay(Capsule().stroke(on ? Color.amber : Color.paper.opacity(0.3)))
                    }.buttonStyle(.plain).accessibilityIdentifier("theme_\(k)")
                }
            }
            if m.settings.theme == "custom" {
                HStack(spacing: 8) {
                    TextField(m.t("customPh"), text: Binding(get: { m.settings.custom }, set: { m.setCustom($0) }))
                        .focused($focus).submitLabel(.send).onSubmit { if !m.settings.custom.isEmpty { go() } }
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.25)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.amber.opacity(0.5)))
                        .foregroundStyle(Color.paper)
                    Button(m.t("customGo")) { focus = false; if !m.settings.custom.trimmingCharacters(in: .whitespaces).isEmpty { go() } else { focus = true } }
                        .buttonStyle(PrimaryButton(big: false)).frame(width: 84)
                }
                Text(m.t(m.live ? "customTip" : "customOff")).font(.system(size: 12)).foregroundStyle(Color.dim)
            }
        }
    }
}

/// 會自動換行的橫排（主題膠囊）
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x + z.width > w && x > 0 { x = 0; y += row + spacing; row = 0 }
            x += z.width + spacing; row = max(row, z.height)
        }
        return CGSize(width: w, height: y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, row: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x + z.width > b.maxX && x > b.minX { x = b.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(z))
            x += z.width + spacing; row = max(row, z.height)
        }
    }
}
