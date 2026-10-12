import Foundation

/// The animal emoji each student gets, just for fun (docs/DECISIONS.md D35).
enum AnimalEmoji {
    /// Single-scalar emoji only (no variation selectors), so they render the same everywhere.
    static let all: [String] = [
        "🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯",
        "🦁", "🐮", "🐷", "🐸", "🐵", "🐔", "🐧", "🐦", "🐤", "🦆",
        "🦅", "🦉", "🦇", "🐺", "🐗", "🐴", "🦄", "🐝", "🐛", "🦋",
        "🐌", "🐞", "🐢", "🐍", "🦎", "🦖", "🦕", "🐙", "🦑", "🦀",
        "🐡", "🐠", "🐬", "🐳", "🦈", "🐊", "🦓", "🦍", "🐘", "🦛",
        "🦏", "🐪", "🦒", "🦘", "🦬", "🐄", "🐑", "🦙", "🐐", "🦌",
        "🐈", "🐓", "🦃", "🦚", "🦜", "🦢", "🦩", "🐇", "🦝", "🦡",
        "🦫", "🦦", "🦥", "🦔", "🐉", "🦭", "🪿", "🪼", "🦣",
    ].filter { $0.unicodeScalars.count == 1 }

    /// A random animal, preferring one nobody in `used` has yet (e.g. the rest of the group).
    static func random(avoiding used: some Sequence<String> = [String](),
                       using rng: inout some RandomNumberGenerator) -> String {
        let used = Set(used)
        let free = all.filter { !used.contains($0) }
        return (free.isEmpty ? all : free).randomElement(using: &rng)!
    }

    static func random(avoiding used: some Sequence<String> = [String]()) -> String {
        var rng = SystemRandomNumberGenerator()
        return random(avoiding: used, using: &rng)
    }
}
