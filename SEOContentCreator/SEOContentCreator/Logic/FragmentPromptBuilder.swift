import Foundation

struct FragmentPromptBuilder {
    func build(roleContext: String, instruction: String, fragment: String) -> (system: String, user: String) {
        let system = roleContext.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = """
        \(instruction.trimmingCharacters(in: .whitespacesAndNewlines))

        Вот фрагмент текста:
        \(fragment)

        Верни только переписанный фрагмент, без пояснений, кавычек и заголовков.
        """
        return (system, user)
    }
}
