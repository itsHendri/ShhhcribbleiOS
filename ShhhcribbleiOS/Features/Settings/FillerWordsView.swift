import SwiftUI

struct FillerWordsView: View {
    @AppStorage("filterFillerWords") private var filterFillerWords = true
    @State private var words: [String] = []
    @State private var newWord: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Form {
            Section {
                Toggle("Remove filler words", isOn: $filterFillerWords)
            } footer: {
                Text("Removes \"um\", \"uh\", \"hmm\", \"er\", \"erm\", \"you know\", and \"like\" from transcriptions.")
            }

            Section {
                HStack(spacing: 8) {
                    TextField("Word", text: $newWord)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .focused($fieldFocused)
                        .submitLabel(.done)
                        .onSubmit { addWord() }

                    Button(action: addWord) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(canAdd ? Color.accentColor : .secondary)
                    }
                    .disabled(!canAdd || !filterFillerWords)
                    .buttonStyle(.plain)
                }
                .opacity(filterFillerWords ? 1 : 0.5)
            } header: {
                Text("Add custom filler word")
            }

            if !words.isEmpty {
                Section {
                    ForEach(words, id: \.self) { word in
                        Text(word)
                    }
                    .onDelete(perform: delete)
                } header: {
                    Text("Custom fillers")
                } footer: {
                    Text("Removed in addition to the built-in list. Whole-word, case-insensitive.")
                }
            } else {
                Section {
                    Text("Add personal filler words like \"basically\", \"literally\", \"honestly\".")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Filler Words")
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
        let arr = (UserDefaults.standard.array(forKey: "customFillerWords") as? [String]) ?? []
        words = arr.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func save() {
        UserDefaults.standard.set(words, forKey: "customFillerWords")
    }
}
