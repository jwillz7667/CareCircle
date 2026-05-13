import OSLog
import PDFKit
import SwiftData
import SwiftUI

// MARK: - DocumentDetailView

/// Detail screen for an encrypted document. Decrypts the payload on appear
/// using `DocumentVault`, holds plaintext only in `@State` (gets discarded
/// when the view goes away), and renders an inline image or PDF preview.
/// Share writes a short-lived temp file scoped to the app sandbox; delete
/// soft-deletes the row and zeroes the stored ciphertext so an out-of-band
/// CloudKit cached copy is also defanged.
struct DocumentDetailView: View {
    let document: Document
    let viewerAppleUserID: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var decryptedData: Data?
    @State private var decryptionError: String?
    @State private var isDecrypting = false
    @State private var shareURL: URL?
    @State private var isPreparingShare = false
    @State private var shareError: String?
    @State private var isConfirmingDelete = false
    @State private var deleteError: String?

    var body: some View {
        List {
            previewSection
            metadataSection
            uploaderSection

            if let decryptionError {
                Section {
                    Label(decryptionError, systemImage: "lock.trianglebadge.exclamationmark.fill")
                        .foregroundStyle(Color.ccDanger)
                }
            }

            if decryptedData != nil {
                shareSection
            }

            if let deleteError {
                Section {
                    Label(deleteError, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(Color.ccDanger)
                }
            }

            deleteSection
        }
        .scrollContentBackground(.hidden)
        .background(Color.ccBackground)
        .navigationTitle(displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.ccBackground, for: .navigationBar)
        .task { await decryptIfNeeded() }
        .onDisappear {
            DocumentShareArtifact.remove(at: shareURL)
            shareURL = nil
        }
        .confirmationDialog(
            "Delete this document?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The encrypted copy is removed from this Circle. This can't be undone.")
        }
    }

    private var displayTitle: String {
        document.title.isEmpty ? document.type.displayName : document.title
    }

    private var previewSection: some View {
        Section {
            if isDecrypting {
                HStack(spacing: Theme.spacing) {
                    ProgressView()
                    Text("Decrypting…")
                        .font(.subheadline)
                        .foregroundStyle(Color.ccSecondary)
                }
                .padding(.vertical, Theme.tightSpacing)
            } else if let data = decryptedData {
                previewContent(for: data)
            } else if decryptionError == nil {
                placeholderPreview
            }
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func previewContent(for data: Data) -> some View {
        if document.mimeType.hasPrefix("image/"), let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .background(Color.ccSurface)
                .accessibilityLabel("Document preview")
        } else if document.mimeType == "application/pdf" {
            PDFPreview(data: data)
                .frame(height: 420)
                .background(Color.ccSurface)
                .accessibilityLabel("PDF preview")
        } else {
            Label("Preview not available for this file type.", systemImage: "doc")
                .foregroundStyle(Color.ccSecondary)
                .padding(Theme.spacing)
        }
    }

    private var placeholderPreview: some View {
        ZStack {
            Color.ccSurface
            Image(systemName: document.type.systemImageName)
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(Color.ccPrimary)
        }
        .frame(height: 220)
        .accessibilityLabel("Encrypted preview")
    }

    private var metadataSection: some View {
        Section("Details") {
            LabeledContent("Type", value: document.type.displayName)
            LabeledContent("Size", value: sizeDescription)
            if let issuedAt = document.issuedAt {
                LabeledContent("Issued", value: issuedAt.formatted(date: .abbreviated, time: .omitted))
            }
            if let expiresAt = document.expiresAt {
                LabeledContent {
                    Text(expiresAt.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(expiryColor(from: expiresAt))
                } label: {
                    Text(expiresAt < Date() ? "Expired" : "Expires")
                }
            }
            LabeledContent("Added", value: document.createdAt.formatted(date: .abbreviated, time: .shortened))
        }
    }

    @ViewBuilder
    private var uploaderSection: some View {
        let trimmed = document.uploadedByDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            Section("Uploaded by") {
                Label(trimmed, systemImage: "person.crop.circle.fill")
                    .foregroundStyle(Color.ccText)
            }
        }
    }

    private var shareSection: some View {
        Section("Share") {
            if let url = shareURL {
                ShareLink(item: url) {
                    Label("Share decrypted copy", systemImage: "square.and.arrow.up")
                }
            } else {
                Button {
                    Task { await prepareShareArtifact() }
                } label: {
                    HStack {
                        Label("Prepare share", systemImage: "square.and.arrow.up")
                        Spacer()
                        if isPreparingShare {
                            ProgressView()
                        }
                    }
                }
                .disabled(isPreparingShare)
            }
            if let shareError {
                Text(shareError)
                    .font(.footnote)
                    .foregroundStyle(Color.ccDanger)
            }
            Text("The shared copy lives in this app's temporary folder until you leave this screen.")
                .font(.footnote)
                .foregroundStyle(Color.ccSecondary)
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Delete document", systemImage: "trash")
            }
        }
    }

    private var sizeDescription: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(document.sizeBytes))
    }

    private func expiryColor(from date: Date) -> Color {
        date < Date() ? Color.ccDanger : Color.ccText
    }

    private func decryptIfNeeded() async {
        guard decryptedData == nil, document.isReadable else { return }
        guard let circleID = document.circle?.id else {
            decryptionError = "This document isn't linked to a Circle."
            return
        }
        isDecrypting = true
        defer { isDecrypting = false }

        let payload = DocumentVault.SealedPayload(
            ciphertext: document.ciphertext,
            nonce: document.nonce,
            tag: document.tag
        )
        do {
            decryptedData = try DocumentVault.shared.open(payload: payload, circleID: circleID)
            decryptionError = nil
        } catch let error as DocumentVault.VaultError {
            decryptionError = error.errorDescription
        } catch {
            decryptionError = "Couldn't decrypt this document."
            AppLogger.persistence.error(
                "Document decrypt failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func prepareShareArtifact() async {
        guard let data = decryptedData else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }

        let suggestion = document.title.isEmpty ? document.type.rawValue : document.title
        do {
            shareURL = try DocumentShareArtifact.write(
                data,
                suggestedFilename: suggestion,
                mimeType: document.mimeType
            )
            shareError = nil
        } catch {
            shareError = "Couldn't prepare a shareable copy."
            AppLogger.persistence.error(
                "Document share prep failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func delete() {
        document.deletedAt = .now
        document.ciphertext = Data()
        document.nonce = Data()
        document.tag = Data()
        document.updatedAt = .now
        do {
            try modelContext.save()
            DocumentShareArtifact.remove(at: shareURL)
            shareURL = nil
            dismiss()
        } catch {
            deleteError = "Couldn't delete the document. Please try again."
            AppLogger.persistence.error(
                "Document delete failed: \(String(describing: error), privacy: .public)"
            )
        }
    }
}

// MARK: - PDFPreview

private struct PDFPreview: UIViewRepresentable {
    let data: Data

    func makeUIView(context _: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: PDFView, context _: Context) {
        if view.document?.dataRepresentation() != data {
            view.document = PDFDocument(data: data)
        }
    }
}
