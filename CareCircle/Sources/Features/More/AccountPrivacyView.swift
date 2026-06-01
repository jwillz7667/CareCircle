import OSLog
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - AccountPrivacyView

/// In-app account controls required by App Store 5.1.1(v) and the product
/// spec: export your data, and permanently delete your account. Deletion
/// calls the backend (which runs the cascading teardown), wipes the local
/// SwiftData store, and signs out.
struct AccountPrivacyView: View {
    let authState: AuthState

    @Environment(\.modelContext) private var modelContext

    @State private var exportState: ExportState = .idle
    @State private var isConfirmingDelete = false
    @State private var deleteState: DeleteState = .idle

    private enum ExportState {
        case idle
        case exporting
        case ready(CareCircleDataArchive)
        case failed(String)
    }

    private enum DeleteState: Equatable {
        case idle
        case deleting
        case failed(String)
    }

    var body: some View {
        List {
            exportSection
            deleteSection
        }
        .scrollContentBackground(.hidden)
        .background(Color.ccBackground)
        .navigationTitle("Account & Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.ccBackground, for: .navigationBar)
        .confirmationDialog(
            "Delete your account?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) {
                Task { await performDelete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This permanently deletes your account and the data in circles you own. Other members lose access. This cannot be undone."
            )
        }
    }

    private var exportSection: some View {
        Section {
            switch exportState {
            case .idle, .failed:
                Button {
                    Task { await performExport() }
                } label: {
                    Label("Export my data", systemImage: "square.and.arrow.up")
                        .foregroundStyle(Color.ccText)
                }
            case .exporting:
                HStack(spacing: Theme.tightSpacing) {
                    ProgressView()
                    Text("Preparing export…")
                        .foregroundStyle(Color.ccSecondary)
                }
            case let .ready(archive):
                ShareLink(
                    item: archive,
                    preview: SharePreview(archive.filename, image: Image(systemName: "doc.zipper"))
                ) {
                    Label("Share export", systemImage: "square.and.arrow.up")
                        .foregroundStyle(Color.ccPrimary)
                }
            }

            if case let .failed(message) = exportState {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.ccDanger)
            }
        } header: {
            Text("Your data")
        } footer: {
            Text(
                "Downloads a ZIP of your profile and the records in your circles. Encrypted documents and media stay on your devices and aren't included."
            )
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                if deleteState == .deleting {
                    HStack(spacing: Theme.tightSpacing) {
                        ProgressView()
                        Text("Deleting…")
                    }
                } else {
                    Label("Delete account", systemImage: "trash")
                }
            }
            .foregroundStyle(Color.ccDanger)
            .disabled(deleteState == .deleting)

            if case let .failed(message) = deleteState {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.ccDanger)
            }
        } header: {
            Text("Danger zone")
        } footer: {
            Text(
                "Care Recipients own their data. Deleting removes your account and the circles you own from this device and the backend."
            )
        }
    }

    private func performExport() async {
        exportState = .exporting
        do {
            let data = try await authState.exportData()
            exportState = .ready(CareCircleDataArchive(data: data, filename: "carecircle-export.zip"))
        } catch {
            exportState = .failed("Couldn't prepare your export. Please try again.")
            AppLogger.backend.error(
                "Data export failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func performDelete() async {
        deleteState = .deleting
        do {
            try await authState.deleteAccount {
                do {
                    try LocalStoreEraser.eraseAll(in: modelContext)
                } catch {
                    AppLogger.persistence.error(
                        "Local store wipe after account deletion failed: \(String(describing: error), privacy: .public)"
                    )
                }
            }
            // status flipped to .signedOut inside deleteAccount → RootView
            // swaps back to the sign-in flow and this view tears down.
        } catch {
            deleteState = .failed("Couldn't delete your account. Check your connection and try again.")
            AppLogger.backend.error(
                "Account deletion failed: \(String(describing: error), privacy: .public)"
            )
        }
    }
}

// MARK: - CareCircleDataArchive

/// Transferable wrapper so `ShareLink` writes a real `.zip` file to the
/// share target instead of a raw `Data` blob.
private struct CareCircleDataArchive: Transferable {
    let data: Data
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .zip) { archive in
            archive.data
        }
        .suggestedFileName { $0.filename }
    }
}
