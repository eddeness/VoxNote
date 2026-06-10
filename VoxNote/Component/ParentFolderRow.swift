import SwiftUI

struct ParentFolderRow: View {
    let onTap: () -> Void
    let onDrop: (UUID) -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.up.left.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("..")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("Move up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
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
    }
}
