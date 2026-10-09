#!/usr/bin/env bash
# SiliconFlowLab.swiftpm（Swift Playgrounds のアプリ）を Xcode で iOS シミュレータ向けにビルドします。
# UI を含むすべてのコードがコンパイルできることを CI で保証するためのスクリプトです。
#
# あわせて、型チェックに時間がかかっている関数・式を報告します（iPad でのビルドを速く保つため）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/SiliconFlowLab.swiftpm"
LOGS="$ROOT/build-logs"
DERIVED="$ROOT/.derived-data"
SLOW_MS="${SLOW_TYPECHECK_MS:-150}"
mkdir -p "$LOGS"

cd "$APP"
echo "::group::xcodebuild -list"
xcodebuild -list -json | tee "$LOGS/list.json"
echo "::endgroup::"

SCHEME="$(python3 - "$LOGS/list.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
container = data.get("workspace") or data.get("project") or {}
schemes = container.get("schemes", [])
preferred = [s for s in schemes if s == "SiliconFlow Lab"]
print((preferred or schemes or [""])[0])
PY
)"
if [ -z "$SCHEME" ]; then
  echo "::error::ビルドできるスキームが見つかりませんでした"
  exit 1
fi
echo "Scheme: $SCHEME"

START=$(date +%s)
set +e
xcodebuild build \
  -scheme "$SCHEME" \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$DERIVED" \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  ONLY_ACTIVE_ARCH=YES \
  OTHER_SWIFT_FLAGS="\$(inherited) -Xfrontend -warn-long-function-bodies=$SLOW_MS -Xfrontend -warn-long-expression-type-checking=$SLOW_MS" \
  > "$LOGS/build.log" 2>&1
STATUS=$?
set -e
END=$(date +%s)

# エラーは GitHub の注釈として表示（grep が 0 件でもスクリプトを止めない）
{ grep -E "error:" "$LOGS/build.log" || true; } | sort -u | head -50 > "$LOGS/errors.txt"
while IFS= read -r line; do
  echo "::error::${line#"$ROOT"/}"
done < "$LOGS/errors.txt"

echo "::group::型チェックが遅い箇所 (>${SLOW_MS}ms)"
{ grep -E "warning: .*(took [0-9]+ms to type-check|type-checking)" "$LOGS/build.log" || true; } | sort -u > "$LOGS/slow-typecheck.txt"
cat "$LOGS/slow-typecheck.txt"
echo "::endgroup::"
SLOW_COUNT=$(wc -l < "$LOGS/slow-typecheck.txt" | tr -d ' ')
if [ "$SLOW_COUNT" != "0" ]; then
  echo "::warning::型チェックに ${SLOW_MS}ms 以上かかる箇所が ${SLOW_COUNT} 件あります（build-logs/slow-typecheck.txt）"
fi

echo "::group::警告"
{ grep -E "warning:" "$LOGS/build.log" || true; } | { grep -v -e "type-check" -e "appintentsmetadataprocessor" || true; } | sort -u | head -80
echo "::endgroup::"

if [ $STATUS -ne 0 ]; then
  echo "::group::ビルドログの末尾"
  tail -120 "$LOGS/build.log"
  echo "::endgroup::"
  echo "::error::iOS アプリのビルドに失敗しました (exit $STATUS)"
  exit $STATUS
fi
echo "ビルド成功: $((END - START)) 秒（クリーンビルド）"
