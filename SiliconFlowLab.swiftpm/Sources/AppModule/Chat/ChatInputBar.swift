import PhotosUI
import SwiftUI
import SiliconFlowKit

/// メッセージ入力欄（画像添付・送信・停止）
struct ChatInputBar: View {
    @ObservedObject var session: ChatSession
    let allowsImages: Bool
    let onSend: () -> Void

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isLoadingPhotos = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !session.attachments.isEmpty || isLoadingPhotos {
                AttachmentStrip(session: session, isLoading: isLoadingPhotos)
            }
            HStack(alignment: .bottom, spacing: 10) {
                if allowsImages {
                    photoButton
                }
                textField
                actionButton
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
        .onChange(of: photoItems) {
            Task { await loadPhotos() }
        }
    }

    private var photoButton: some View {
        PhotosPicker(selection: $photoItems, maxSelectionCount: 4, matching: .images) {
            Image(systemName: "photo.badge.plus")
                .font(.title2)
        }
        .disabled(session.isGenerating)
        .accessibilityLabel("画像を添付")
    }

    private var textField: some View {
        TextField("メッセージを入力", text: $session.draft, axis: .vertical)
            .lineLimit(1...6)
            .focused($isFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
    }

    @ViewBuilder
    private var actionButton: some View {
        if session.isGenerating {
            Button {
                session.stop()
            } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 30))
            }
            .tint(.red)
            .accessibilityLabel("停止")
        } else {
            Button {
                onSend()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
            }
            .disabled(!session.canSend)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel("送信")
        }
    }

    private func loadPhotos() async {
        guard !photoItems.isEmpty else { return }
        isLoadingPhotos = true
        defer { isLoadingPhotos = false }
        let items = photoItems
        photoItems = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let dataURL = ImageEncoder.dataURL(from: data)
            else { continue }
            session.attachments.append(dataURL)
        }
    }
}

/// 送信前の添付画像
private struct AttachmentStrip: View {
    @ObservedObject var session: ChatSession
    let isLoading: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(session.attachments.enumerated()), id: \.offset) { index, url in
                    AttachmentThumbnail(dataURL: url) { session.removeAttachment(at: index) }
                }
                if isLoading {
                    ProgressView()
                        .frame(width: 64, height: 64)
                }
            }
        }
    }
}

private struct AttachmentThumbnail: View {
    let dataURL: String
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = ImageEncoder.image(fromDataURL: dataURL) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .offset(x: 6, y: -6)
            .accessibilityLabel("添付を削除")
        }
    }
}
