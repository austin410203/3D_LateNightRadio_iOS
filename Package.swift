// swift-tools-version:5.9
// 純 Swift 核心（規則、離線劇本、安全檢查）：Linux 的 Docker 也能編，coretest 用網頁匯出的 golden.json 對照。
// App 本身用 XcodeGen（project.yml），直接把 Sources/LNRCore 編進去。
import PackageDescription

let package = Package(
    name: "LNRCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "LNRCore", targets: ["LNRCore"])],
    targets: [
        .target(name: "LNRCore", path: "Sources/LNRCore"),
        .executableTarget(name: "coretest", dependencies: ["LNRCore"], path: "Sources/coretest"),
    ]
)
