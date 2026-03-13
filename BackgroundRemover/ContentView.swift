import PhotosUI
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @StateObject private var viewModel = BackgroundRemoverViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let selectedImage = viewModel.selectedImage {
                        previewCard(selectedImage: selectedImage)
                    } else {
                        emptyState
                    }

                    actions

                    if let statusMessage = viewModel.statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("Background Remover")
        }
        .sheet(isPresented: $viewModel.showPaywall) {
            PaywallView()
                .environmentObject(purchaseManager)
        }
    }

    @ViewBuilder
    private func previewCard(selectedImage: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.processedImage != nil {
                Picker("Preview", selection: $viewModel.compareMode) {
                    ForEach(BackgroundRemoverViewModel.CompareMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            ZStack {
                CheckerboardBackground()

                Image(uiImage: activeImage(fallback: selectedImage))
                    .resizable()
                    .scaledToFit()
                    .padding(10)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.quaternary, lineWidth: 1)
            )

            if !purchaseManager.isPremiumUnlocked {
                Text("Free removals left: \(purchaseManager.remainingFreeUses)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            PhotosPicker(selection: $viewModel.selectedPhotoItem, matching: .images) {
                Label("Select Photo", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .onChange(of: viewModel.selectedPhotoItem) { _, _ in
                Task { await viewModel.loadSelectedPhoto() }
            }

            Button {
                Task { await viewModel.removeBackground(using: purchaseManager) }
            } label: {
                if viewModel.isProcessing {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Remove Background", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isProcessing)

            HStack {
                Button {
                    Task { await viewModel.saveResult() }
                } label: {
                    Label("Save PNG", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.processedImage == nil)

                if let data = viewModel.sharePNGData {
                    ShareLink(item: PNGShareItem(data: data), preview: SharePreview("Cutout.png")) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text("Select a photo")
                .font(.title3.bold())

            Text("Pick an image to quickly remove the background and export a transparent PNG.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func activeImage(fallback: UIImage) -> UIImage {
        guard let processed = viewModel.processedImage else { return fallback }
        return viewModel.compareMode == .cutout ? processed : fallback
    }
}

private struct CheckerboardBackground: View {
    var body: some View {
        GeometryReader { geometry in
            let size: CGFloat = 16
            let columns = Int(geometry.size.width / size)
            let rows = Int(geometry.size.height / size)

            Canvas { context, _ in
                for row in 0...rows {
                    for column in 0...columns where (row + column).isMultiple(of: 2) {
                        let rect = CGRect(
                            x: CGFloat(column) * size,
                            y: CGFloat(row) * size,
                            width: size,
                            height: size
                        )
                        context.fill(
                            Path(rect),
                            with: .color(Color(.systemGray5))
                        )
                    }
                }
            }
        }
        .background(Color(.systemGray6))
    }
}

#Preview {
    ContentView()
        .environmentObject(PurchaseManager())
}
