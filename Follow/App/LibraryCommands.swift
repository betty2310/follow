import SwiftUI

/// What the main window lets the menu bar do with groups and students (D43).
struct LibraryActions {
    var newGroup: () -> Void
    var addStudent: () -> Void
    var importStudents: () -> Void
    var toggleCollapsed: () -> Void
    var hasGroups: Bool
    var allCollapsed: Bool
}

extension FocusedValues {
    @Entry var libraryActions: LibraryActions?
}

/// File menu: the sidebar's + menu with shortcuts. View menu: collapse or expand every group.
/// Replaces New Window: Follow is used in one window, and ⌘N fits Add Student better.
struct LibraryCommands: Commands {
    @FocusedValue(\.libraryActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Group…") { actions?.newGroup() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(actions == nil)
            Button("Add Student…") { actions?.addStudent() }
                .keyboardShortcut("n")
                .disabled(actions?.hasGroups != true)
            Button("Import Students from Excel…") { actions?.importStudents() }
                .keyboardShortcut("i")
                .disabled(actions == nil)
        }
        CommandGroup(before: .sidebar) {
            Button(actions?.allCollapsed == true ? "Expand All Groups" : "Collapse All Groups") {
                actions?.toggleCollapsed()
            }
            .disabled(actions?.hasGroups != true)
            Divider()
        }
    }
}
