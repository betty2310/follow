import SwiftUI

/// The student's animal emoji (D35). Click it to pick another one, or roll the dice.
struct StudentEmojiButton: View {
    @Environment(\.appDatabase) private var db
    let student: Student?
    var size: CGFloat = 20
    @State private var picking = false

    var body: some View {
        Button { picking = true } label: {
            Text(student?.emoji ?? "")
                .font(.system(size: size))
                .frame(width: size * 1.3, height: size * 1.3)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(student == nil)
        .help("Change the emoji")
        .popover(isPresented: $picking, arrowEdge: .trailing) {
            AnimalEmojiPicker(current: student?.emoji ?? "") { emoji in
                set(emoji)
                picking = false
            }
        }
    }

    private func set(_ emoji: String) {
        guard let id = student?.id, emoji != student?.emoji else { return }
        try? db.setEmoji(studentId: id, emoji)
    }
}

private struct AnimalEmojiPicker: View {
    let current: String
    var onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 4), count: 9), spacing: 4) {
                ForEach(AnimalEmoji.all, id: \.self) { emoji in
                    Button { onPick(emoji) } label: {
                        Text(emoji)
                            .font(.system(size: 22))
                            .frame(width: 32, height: 32)
                            .background(emoji == current ? Color.accentColor.opacity(0.25) : .clear,
                                        in: .rect(cornerRadius: 6))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("Random", systemImage: "dice") {
                onPick(AnimalEmoji.random(avoiding: [current]))
            }
        }
        .padding(12)
    }
}
