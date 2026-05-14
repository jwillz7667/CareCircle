import OSLog
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - AddDocumentView

/// Sheet for adding a new document. Source is either a PHPicker (photo) or
/// the system file importer (PDF). Plaintext bytes are encrypted in-memory
/// via `DocumentVault.sealForOwner(plaintext:circleID:)` before the model
/// row is inserted, so SwiftData / CloudKit only ever sees ciphertext.
struct AddDocumentView: View {
    let circle: Circle
    let viewerAppleUserID: String
    let source: AddDocumentSheet

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var syncEngine

    @State private var draft = DocumentDraft()
    @State private var plaintext: Data?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var photoSelection: PhotosPickerItem?
    @State private var isPresentingFileImporter = false
    @State private var hasIssuedAt = false
    @State private var hasExpiresAt = false

    private var canSave: Bool {
        !isSaving && draft.isValid && plaintext != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
                identitySection
                visibilitySection
                datesSection

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(Color.ccDanger)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ccBackground)
            .navigationTitle("Add document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.ccBackground, for: .navigationBar)
            .toolbar { toolbar }
            .interactiveDismissDisabled(isSaving)
            .onChange(of: photoSelection) { _, newValue in
                Task { await loadPhoto(item: newValue) }
            }
            .fileImporter(
                isPresented: $isPresentingFileImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .onAppear {
                if source == .file {
                    isPresentingFileImporter = true
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }.disabled(isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") { save() }.disabled(!canSave)
        }
    }

    private var sourceSection: some View {
        Section("Source") {
            switch source {
            case .photo:
                PhotosPicker(
                    selection: $photoSelection,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label(photoButtonLabel, systemImage: "photo.fill")
                }
            case .file:
                Button {
                    isPresentingFileImporter = true
                } label: {
                    Label(fileButtonLabel, systemImage: "doc.fill")
                }
            }
            if let plaintext, let size = AddDocumentView.sizeString(for: plaintext.count) {
                Text("Selected \(size). Encrypted on save.")
                    .font(.footnote)
                    .foregroundStyle(Color.ccSecondary)
            }
        }
    }

    private var photoButtonLabel: String {
        plaintext == nil ? "Choose a photo" : "Replace photo"
    }

    private var fileButtonLabel: String {
        plaintext == nil ? "Choose a PDF" : "Replace PDF"
    }

    private var identitySection: some View {
        Section("Identity") {
            LabeledContent("Title") {
                TextField("e.g., Mom's Medicare card", text: $draft.title)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Document title")
            }
            Picker("Type", selection: $draft.type) {
                ForEach(DocumentType.allCases) { type in
                    Label(type.displayName, systemImage: type.systemImageName).tag(type)
                }
            }
        }
    }

    private var visibilitySection: some View {
        Section {
            ForEach(MemberRole.allCases, id: \.self) { role in
                Toggle(role.displayName, isOn: visibilityBinding(for: role))
            }
        } header: {
            Text("Who can view")
        } footer: {
            Text("Only members in the selected roles can decrypt and preview this document.")
                .font(.footnote)
                .foregroundStyle(Color.ccSecondary)
        }
    }

    private func visibilityBinding(for role: MemberRole) -> Binding<Bool> {
        Binding(
            get: { draft.visibilityRoles.contains(role) },
            set: { newValue in
                if newValue {
                    draft.visibilityRoles.insert(role)
                } else {
                    draft.visibilityRoles.remove(role)
                }
            }
        )
    }

    private var datesSection: some View {
        Section("Dates") {
            Toggle("Issued date", isOn: $hasIssuedAt)
                .onChange(of: hasIssuedAt) { _, newValue in
                    draft.issuedAt = newValue ? (draft.issuedAt ?? .now) : nil
                }
            if hasIssuedAt {
                DatePicker(
                    "Issued on",
                    selection: Binding(
                        get: { draft.issuedAt ?? .now },
                        set: { draft.issuedAt = $0 }
                    ),
                    displayedComponents: .date
                )
            }
            Toggle("Expiration date", isOn: $hasExpiresAt)
                .onChange(of: hasExpiresAt) { _, newValue in
                    draft.expiresAt = newValue ? (draft.expiresAt ?? .now) : nil
                }
            if hasExpiresAt {
                DatePicker(
                    "Expires on",
                    selection: Binding(
                        get: { draft.expiresAt ?? .now },
                        set: { draft.expiresAt = $0 }
                    ),
                    displayedComponents: .date
                )
            }
        }
    }

    // MARK: - Source handling

    private func loadPhoto(item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            let candidate = try await DocumentCandidatePipeline.loadPhoto(item)
            accept(candidate)
        } catch let error as DocumentCandidateError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Couldn't read the selected photo."
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            do {
                let candidate = try DocumentCandidatePipeline.loadPDF(from: url)
                accept(candidate)
            } catch let error as DocumentCandidateError {
                errorMessage = error.errorDescription
            } catch {
                errorMessage = "Couldn't read that PDF."
            }
        case let .failure(error):
            errorMessage = error.localizedDescription
        }
    }

    private func accept(_ candidate: DocumentCandidate) {
        plaintext = candidate.data
        draft.mimeType = candidate.mimeType
        draft.sizeBytes = candidate.data.count
        draft.sourceFilename = candidate.filename
        if draft.trimmedTitle.isEmpty {
            draft.title = candidate.filename
        }
        errorMessage = nil
    }

    private static func sizeString(for bytes: Int) -> String? {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    // MARK: - Save

    private func save() {
        guard canSave, let plaintext else { return }
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        let circleID = circle.id
        let isOwner = circle.ownerAppleUserID == viewerAppleUserID

        do {
            let payload: DocumentVault.SealedPayload = if isOwner {
                try DocumentVault.shared.sealForOwner(plaintext: plaintext, circleID: circleID)
            } else {
                try DocumentVault.shared.sealForMember(plaintext: plaintext, circleID: circleID)
            }
            let uploaderName = circle.members
                .first(where: { $0.appleUserID == viewerAppleUserID })?.displayName ?? ""
            let document = Document(
                title: draft.trimmedTitle,
                type: draft.type,
                mimeType: draft.mimeType,
                sizeBytes: draft.sizeBytes,
                ciphertext: payload.ciphertext,
                nonce: payload.nonce,
                tag: payload.tag,
                issuedAt: draft.issuedAt,
                expiresAt: draft.expiresAt,
                visibilityRoles: Array(draft.visibilityRoles),
                uploadedByAppleUserID: viewerAppleUserID,
                uploadedByDisplayName: uploaderName
            )
            document.circle = circle
            modelContext.insert(document)
            try modelContext.save()
            syncEngine.enqueueDocumentCreate(document)
            dismiss()
        } catch let error as DocumentVault.VaultError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Couldn't save the document. Please try again."
            AppLogger.persistence.error(
                "Document save failed: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
