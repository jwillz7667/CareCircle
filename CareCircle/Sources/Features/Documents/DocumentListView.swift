import SwiftData
import SwiftUI

// MARK: - DocumentListView

/// Circle-scoped documents list. Filters out documents the viewer's role
/// shouldn't see and groups the rest by type. Floating add button drives
/// the upload sheet.
struct DocumentListView: View {
    let circle: Circle
    let viewerAppleUserID: String

    @Environment(BackendRealtimeClient.self) private var realtimeClient
    @Environment(\.modelContext) private var modelContext
    @State private var isAdding = false
    @State private var pickerSource: AddDocumentSheet?

    private var viewerRole: MemberRole? {
        circle.members.first(where: { $0.appleUserID == viewerAppleUserID })?.role
    }

    private var visibleDocuments: [Document] {
        let role = viewerRole
        return circle.documents
            .filter { $0.deletedAt == nil && ($0.isReadable || $0.isBackendPlaceholder) }
            .filter { document in
                guard let role else { return false }
                return document.visibilityRoles.contains(role)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var grouped: [(type: DocumentType, items: [Document])] {
        let byType = Dictionary(grouping: visibleDocuments, by: { $0.type })
        return byType
            .map { ($0.key, $0.value) }
            .sorted { $0.0.sortOrder < $1.0.sortOrder }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            content

            addButton
                .padding(.trailing, Theme.spacing)
                .padding(.bottom, Theme.spacing)
        }
        .background(Color.ccBackground)
        .navigationTitle("Documents")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.ccBackground, for: .navigationBar)
        .confirmationDialog("Add a document", isPresented: $isAdding, titleVisibility: .visible) {
            Button("Photo") { pickerSource = .photo }
            Button("PDF / File") { pickerSource = .file }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $pickerSource) { source in
            AddDocumentView(circle: circle, viewerAppleUserID: viewerAppleUserID, source: source)
        }
    }

    @ViewBuilder
    private var content: some View {
        if visibleDocuments.isEmpty {
            ScrollView {
                EmptyStateView(
                    systemImage: "doc.fill.badge.plus",
                    title: "No documents yet",
                    message: "Add insurance cards, advance directives, or lab results so the Circle has them when it counts."
                )
                .containerRelativeFrame(.vertical)
            }
            .refreshable {
                await realtimeClient.snapshotResync(
                    circleIds: [circle.id],
                    modelContext: modelContext
                )
            }
        } else {
            List {
                ForEach(grouped, id: \.type) { group in
                    Section(group.type.displayName) {
                        ForEach(group.items) { document in
                            NavigationLink {
                                DocumentDetailView(document: document, viewerAppleUserID: viewerAppleUserID)
                            } label: {
                                DocumentRowView(document: document)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .refreshable {
                await realtimeClient.snapshotResync(
                    circleIds: [circle.id],
                    modelContext: modelContext
                )
            }
        }
    }

    private var addButton: some View {
        Button {
            isAdding = true
        } label: {
            Label("Add document", systemImage: "plus")
                .font(.body.weight(.semibold))
                .padding(.horizontal, Theme.spacing)
                .padding(.vertical, 12)
                .foregroundStyle(Color.white)
                .background(Capsule().fill(Color.ccPrimary))
                .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 4)
        }
        .accessibilityHint("Encrypt and add a document to this Circle.")
    }
}

// MARK: - AddDocumentSheet

enum AddDocumentSheet: Identifiable, Hashable {
    case photo
    case file

    var id: Self {
        self
    }
}
