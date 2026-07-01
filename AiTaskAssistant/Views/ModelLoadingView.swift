import SwiftUI

struct ModelLoadingView: View {
    @State private var llm = LLMState.shared

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "brain.head.profile")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text("TaskMind AI")
                    .font(.largeTitle.bold())
                Text("Downloading AI model (~700 MB)\nOne-time download, runs fully offline")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            if let err = llm.errorMessage {
                VStack(spacing: 12) {
                    Text("Download failed")
                        .fontWeight(.semibold)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Retry") {
                        Task { await ExtractionService.shared.load() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .foregroundStyle(.red)
            } else {
                VStack(spacing: 8) {
                    ProgressView(value: llm.progress)
                        .padding(.horizontal, 48)
                        .tint(.blue)
                    Text(llm.progress > 0
                         ? "\(Int(llm.progress * 100))%"
                         : "Connecting…")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .task {
            await ExtractionService.shared.load()
        }
    }
}
