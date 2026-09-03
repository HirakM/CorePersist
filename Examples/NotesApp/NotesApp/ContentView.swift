import CorePersist
import SwiftUI

struct ContentView: View {
    @Environment(\.persistentStore) private var store
    @FetchRequest(sortDescriptors: [SortDescriptor(\Note.createdAt, order: .reverse)])
    private var notes: FetchedResults<Note>

    @State private var draft = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(notes) { note in
                    Button {
                        togglePin(note)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(note.title)
                                    .foregroundStyle(.primary)
                                Text(note.createdAt, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if note.isPinned {
                                Image(systemName: "pin.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("Notes")
            .overlay {
                if notes.isEmpty {
                    ContentUnavailableView(
                        "No notes yet",
                        systemImage: "note.text",
                        description: Text("Add one with the field below.")
                    )
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    TextField("New note", text: $draft)
                        .textFieldStyle(.roundedBorder)
                    Button("Add", action: add)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
                .background(.bar)
            }
        }
    }

    private func add() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        try? store?.create(Note.self) { note in
            note.title = title
            note.createdAt = Date()
        }
        try? store?.save()
        draft = ""
    }

    private func togglePin(_ note: Note) {
        note.isPinned.toggle()
        try? store?.save()
    }

    private func delete(at offsets: IndexSet) {
        offsets.map { notes[$0] }.forEach { store?.delete($0) }
        try? store?.save()
    }
}

#Preview {
    ContentView()
        .persistentStore(
            .preview(modelName: "Notes") { context in
                let note = Note(context: context)
                note.title = "Sample note"
                note.createdAt = Date()
                note.isPinned = true
            }
        )
}
