import SwiftUI

struct FolderRowView: View {
    let folder: RecordingFolder
    let onTap: () -> Void
    let onDelete: () -> Void
    let onRename: (String) -> Void
    let onDrop: (UUID) -> Void
    
    @State private var showRenameSheet = false
    @State private var newName = ""
    @State private var showDeleteConfirm = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(folder.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .dropDestination(for: String.self) { items, _ in
            guard let idString = items.first,
                  let id = UUID(uuidString: idString) else { return false }
            onDrop(id)
            return true
        }
        .contextMenu {
            Button {
                newName = folder.name
                showRenameSheet = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showRenameSheet) {
            RenameSheet(
                title: "Rename Folder",
                initialName: folder.name,
                onSave: { name in
                    onRename(name)
                    showRenameSheet = false
                },
                onCancel: { showRenameSheet = false }
            )
        }
        .confirmationDialog("Delete folder?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Recordings in this folder will move to the parent folder.")
        }
    }
}

// MARK: - Rename sheet (reusable)

struct RenameSheet: View {
    let title: String
    let initialName: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { save() }

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { name = initialName }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard NameValidator.isValid(trimmed) else {
            errorMessage = "Name must be 1-50 characters and cannot contain / \\ : * ? \" < > |"
            return
        }
        onSave(trimmed)
    }
}
