import SwiftUI
import UIKit
import SiliconFlowKit

/// 接続診断：どこまで通信できているかを順番に確認します。
struct DiagnosticsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ModelStore
    @EnvironmentObject private var diagnostics: DiagnosticsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DiagnosticsSummary()
                    Button {
                        diagnostics.run(settings: settings, models: store.models)
                    } label: {
                        Label(diagnostics.isRunning ? "診断中…" : "もう一度診断する", systemImage: "stethoscope")
                    }
                    .disabled(diagnostics.isRunning)
                }
                Section("確認項目") {
                    ForEach(DiagnosticStep.allCases) { step in
                        DiagnosticStepRow(step: step, outcome: diagnostics.outcomes[step], isRunning: diagnostics.runningStep == step)
                    }
                }
                if let match = diagnostics.otherRegionMatch {
                    RegionMatchSection(match: match)
                }
                failureSections
                EnvironmentSection()
            }
            .navigationTitle("接続診断")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task {
                if diagnostics.outcomes.isEmpty, !diagnostics.isRunning {
                    diagnostics.run(settings: settings, models: store.models)
                }
            }
        }
    }

    @ViewBuilder
    private var failureSections: some View {
        ForEach(DiagnosticStep.allCases) { step in
            if case .failed(let error)? = diagnostics.outcomes[step] {
                Section("「\(step.title)」の原因と直し方") {
                    ErrorCardView(error: error, retry: {
                        diagnostics.run(settings: settings, models: store.models)
                    })
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }
            }
        }
    }
}

private struct DiagnosticsSummary: View {
    @EnvironmentObject private var diagnostics: DiagnosticsStore

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let date = diagnostics.finishedAt {
                    Text("最終実行: \(DisplayFormat.dateTime(date))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        if diagnostics.isRunning { return "診断しています…" }
        if diagnostics.outcomes.isEmpty { return "まだ診断していません" }
        if diagnostics.failedCount == 0 { return "問題は見つかりませんでした" }
        return "\(diagnostics.failedCount) 件の問題が見つかりました"
    }

    private var icon: String {
        if diagnostics.isRunning { return "hourglass" }
        return diagnostics.failedCount == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
    }

    private var color: Color {
        if diagnostics.isRunning || diagnostics.outcomes.isEmpty { return .secondary }
        return diagnostics.failedCount == 0 ? .green : .orange
    }
}

private struct DiagnosticStepRow: View {
    let step: DiagnosticStep
    let outcome: DiagnosticOutcome?
    let isRunning: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            statusIcon
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Label(step.title, systemImage: step.systemImage)
                    .font(.subheadline.weight(.semibold))
                if let outcome {
                    Text(outcome.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isRunning {
            ProgressView()
        } else {
            switch outcome {
            case .passed?:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .warning?:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .failed?:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case .skipped?:
                Image(systemName: "minus.circle").foregroundStyle(.secondary)
            case nil:
                Image(systemName: "circle").foregroundStyle(.tertiary)
            }
        }
    }
}

private struct RegionMatchSection: View {
    let match: RegionDetector.Result
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var diagnostics: DiagnosticsStore
    @EnvironmentObject private var store: ModelStore

    var body: some View {
        Section("見つかりました") {
            Label("この API キーは「\(match.region.displayName)」のキーです。", systemImage: "lightbulb")
            Button("\(match.region.shortName)に切り替える") {
                if let key = settings.currentAPIKey {
                    settings.saveAPIKey(key, for: match.region)
                }
                settings.region = match.region
                diagnostics.run(settings: settings, models: store.models)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// 問い合わせ用の環境情報
private struct EnvironmentSection: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var diagnostics: DiagnosticsStore

    var body: some View {
        Section("環境") {
            LabeledContent("リージョン", value: settings.region.displayName)
            LabeledContent("接続先", value: settings.makeClient().configuration.baseURL.absoluteString)
            LabeledContent("タイムアウト", value: "\(Int(settings.requestTimeout)) 秒")
            LabeledContent("iPadOS", value: UIDevice.current.systemVersion)
            CopyButton(text: report, title: "診断結果をコピー")
        }
    }

    private var report: String {
        var lines = [
            "SiliconFlow Lab 接続診断",
            "リージョン: \(settings.region.displayName)",
            "接続先: \(settings.makeClient().configuration.baseURL.absoluteString)",
            "OS: iPadOS \(UIDevice.current.systemVersion)",
        ]
        for step in DiagnosticStep.allCases {
            guard let outcome = diagnostics.outcomes[step] else { continue }
            lines.append("- \(step.title): \(outcome.summary)")
            if case .failed(let error) = outcome {
                lines.append(error.technicalReport.split(separator: "\n").map { "    " + $0 }.joined(separator: "\n"))
            }
        }
        return lines.joined(separator: "\n")
    }
}
