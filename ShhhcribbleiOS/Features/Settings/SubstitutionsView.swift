import SwiftUI

struct SubstitutionsView: View {
    @State private var rules: [Rule] = []
    @State private var newFind: String = ""
    @State private var newReplace: String = ""
    @FocusState private var newFocused: NewField?

    private enum NewField { case find, replace }

    private struct Rule: Identifiable, Equatable {
        let id = UUID()
        var find: String
        var replace: String
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    TextField("Find", text: $newFind)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .focused($newFocused, equals: .find)
                        .submitLabel(.next)
                        .onSubmit { newFocused = .replace }

                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Replace with", text: $newReplace)
                        .focused($newFocused, equals: .replace)
                        .submitLabel(.done)
                        .onSubmit { addRule() }

                    Button(action: addRule) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(canAdd ? Color.accentColor : .secondary)
                    }
                    .disabled(!canAdd)
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Add rule")
            }

            if rules.isEmpty {
                Section {
                    Text("Replace recurring words automatically — e.g. \"github\" → \"GitHub\".")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(rules) { rule in
                        HStack(spacing: 8) {
                            Text(rule.find)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(rule.replace)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: delete)
                } header: {
                    Text("Rules")
                } footer: {
                    Text("Whole-word, case-insensitive. Applied after filler-word removal.")
                }
            }
        }
        .navigationTitle("Substitutions")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private var canAdd: Bool {
        !newFind.trimmingCharacters(in: .whitespaces).isEmpty
            && !newReplace.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func addRule() {
        let find = newFind.trimmingCharacters(in: .whitespaces)
        let replace = newReplace.trimmingCharacters(in: .whitespaces)
        guard !find.isEmpty, !replace.isEmpty else { return }
        rules.removeAll { $0.find.caseInsensitiveCompare(find) == .orderedSame }
        rules.append(Rule(find: find, replace: replace))
        rules.sort { $0.find.localizedCaseInsensitiveCompare($1.find) == .orderedAscending }
        newFind = ""
        newReplace = ""
        newFocused = .find
        save()
    }

    private func delete(at offsets: IndexSet) {
        rules.remove(atOffsets: offsets)
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: "substitutionRules"),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            rules = []
            return
        }
        rules = dict
            .map { Rule(find: $0.key, replace: $0.value) }
            .sorted { $0.find.localizedCaseInsensitiveCompare($1.find) == .orderedAscending }
    }

    private func save() {
        var dict: [String: String] = [:]
        for rule in rules { dict[rule.find] = rule.replace }
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: "substitutionRules")
        }
    }
}
