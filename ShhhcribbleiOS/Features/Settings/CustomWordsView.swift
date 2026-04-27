import SwiftUI

struct CustomWordsView: View {
    @State private var words: [String] = []
    @State private var newWord: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    TextField("Word or phrase", text: $newWord)
                        .autocorrectionDisabled(true)
                        .focused($fieldFocused)
                        .submitLabel(.done)
                        .onSubmit { addWord() }

                    Button(action: addWord) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(canAdd ? Color.accentColor : .secondary)
                    }
                    .disabled(!canAdd)
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Add word")
            } footer: {
                Text("Type the word with the casing you want — e.g. \"GitHub\", \"iPhone\", \"FluidAudio\".")
            }

            if words.isEmpty {
                Section {
                    Text("No custom words yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(words, id: \.self) { word in
                        Text(word)
                    }
                    .onDelete(perform: delete)
                } header: {
                    Text("Words")
                } footer: {
                    Text("Auto-corrects the casing of these words in transcripts. Best for proper nouns and brand names that Parakeet hears correctly but doesn't capitalise. For mis-transcribed words, use Substitutions instead.")
                }
            }
        }
        .navigationTitle("Custom Words")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private var canAdd: Bool {
        !newWord.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func addWord() {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { return }
        words.removeAll { $0.caseInsensitiveCompare(word) == .orderedSame }
        words.append(word)
        words.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        newWord = ""
        fieldFocused = true
        save()
    }

    private func delete(at offsets: IndexSet) {
        words.remove(atOffsets: offsets)
        save()
    }

    private func load() {
        let arr = (UserDefaults.standard.array(forKey: "customHotwords") as? [String]) ?? []
        words = arr.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func save() {
        UserDefaults.standard.set(words, forKey: "customHotwords")
    }
}
