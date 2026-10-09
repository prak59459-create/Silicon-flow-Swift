#!/usr/bin/env python3
"""Swift Playgrounds（iPad）で確実に・速くビルドできるかを静的にチェックします。

CI の最初に実行され、問題があれば失敗します。

チェック内容
- .swiftpm/Package.swift が Playgrounds 形式（AppleProductTypes / iOSApplication / tools 5.9）であること
- Sources に Swift 以外のファイルが無いこと（Playgrounds が扱えない・ビルドが遅くなるため）
- マクロ（#Preview, @Observable 等）を使っていないこと（マクロ展開はビルド時間とメモリを増やす）
- Swift 6 専用の構文を使っていないこと（Swift 5.9 の Playgrounds 4.4 でもビルドできるように）
- SiliconFlowKit が UI フレームワークに依存していないこと（Linux でテストできるように）
- 1 ファイルが大きすぎないこと（コンパイル単位を小さく保ち、増分ビルドを速くするため）
"""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "SiliconFlowLab.swiftpm"
SOURCES = APP / "Sources"
KIT = SOURCES / "SiliconFlowKit"
UI = SOURCES / "AppModule"

MAX_LINES = 400
GENERATED = {"BundledCatalogSnapshot.swift"}

FORBIDDEN_EVERYWHERE = [
    (re.compile(r"#Preview\b"), "#Preview マクロはビルドを遅くします（PreviewProvider も使わないでください）"),
    (re.compile(r"@Observable\b"), "@Observable マクロではなく ObservableObject を使ってください"),
    (re.compile(r"^\s*import\s+(Observation|SwiftData)\b", re.M), "マクロ依存のフレームワークは使わないでください"),
    (re.compile(r"@Model\b"), "SwiftData の @Model マクロは使わないでください"),
    (re.compile(r"\bthrows\s*\("), "typed throws は Swift 6 専用です"),
    (re.compile(r"@retroactive\b"), "@retroactive は Swift 6 専用です"),
    (re.compile(r"\bnonisolated\(nonsending\)"), "nonisolated(nonsending) は Swift 6.2 専用です"),
    (re.compile(r"\(\s*\w+\s*:\s*sending\b"), "sending パラメータは Swift 6 専用です"),
    (re.compile(r"^\s*@preconcurrency\s+import\s+Foundation", re.M), "Foundation の @preconcurrency import は不要です"),
]
FORBIDDEN_IN_KIT = [
    (re.compile(r"^\s*import\s+(SwiftUI|UIKit|AppKit|PhotosUI|AVFoundation|AVKit)\b", re.M), "SiliconFlowKit は UI に依存してはいけません（Linux でテストするため）"),
]


def main() -> int:
    errors: list[str] = []
    warnings: list[str] = []

    manifest = (APP / "Package.swift").read_text(encoding="utf-8")
    if not manifest.startswith("// swift-tools-version: 5.9"):
        errors.append("Package.swift: swift-tools-version は 5.9 にしてください（Playgrounds 4.4 以降で開けるように）")
    for needle in ("import AppleProductTypes", ".iOSApplication(", 'name: "AppModule"', 'name: "SiliconFlowKit"'):
        if needle not in manifest:
            errors.append(f"Package.swift: {needle} がありません")
    if ".unsafeFlags" in manifest:
        errors.append("Package.swift: unsafeFlags は Playgrounds では使えません")
    if ".package(" in manifest:
        warnings.append("Package.swift: 外部パッケージへの依存はビルドを遅くします")

    for path in sorted(APP.rglob("*")):
        if path.is_dir() or ".build" in path.parts or ".swiftpm" in path.parts[len(APP.parts):]:
            continue
        relative = path.relative_to(ROOT)
        if path.name == "Package.swift" and path.parent == APP:
            continue
        if any(part.endswith(".xcassets") for part in path.parts):
            continue
        if path.suffix != ".swift":
            errors.append(f"{relative}: Swift 以外のファイルは置かないでください")
            continue
        if SOURCES not in path.parents:
            errors.append(f"{relative}: Sources の外に Swift ファイルがあります")
            continue
        text = path.read_text(encoding="utf-8")
        lines = text.count("\n") + 1
        if path.name not in GENERATED and lines > MAX_LINES:
            errors.append(f"{relative}: {lines} 行あります（{MAX_LINES} 行以下に分割してください）")
        rules = FORBIDDEN_EVERYWHERE + (FORBIDDEN_IN_KIT if KIT in path.parents else [])
        for pattern, message in rules:
            for match in pattern.finditer(text):
                line = text.count("\n", 0, match.start()) + 1
                errors.append(f"{relative}:{line}: {message}")

    kit_files = sorted(KIT.rglob("*.swift"))
    ui_files = sorted(UI.rglob("*.swift"))
    if not kit_files or not ui_files:
        errors.append("SiliconFlowKit または AppModule のソースが見つかりません")
    main_count = sum("@main" in f.read_text(encoding="utf-8") for f in ui_files)
    if main_count != 1:
        errors.append(f"AppModule に @main がちょうど 1 つ必要です（{main_count} 個）")

    def summary(files: list[pathlib.Path]) -> str:
        total = sum(f.read_text(encoding="utf-8").count("\n") for f in files)
        return f"{len(files)} files / {total} lines"

    print(f"SiliconFlowKit: {summary(kit_files)}")
    print(f"AppModule:      {summary(ui_files)}")
    for warning in warnings:
        print(f"::warning::{warning}")
    for error in errors:
        print(f"::error::{error}")
    if errors:
        print(f"\n{len(errors)} 件の問題があります")
        return 1
    print("OK: Swift Playgrounds 互換チェックに合格しました")
    return 0


if __name__ == "__main__":
    sys.exit(main())
