import SwiftUI

/// Form sheet for adding a new user radio station, or editing an existing one.
/// Pass `existing` to edit; pass nil to add. Submission writes through to
/// `RadioStore` and dismisses the sheet.
struct AddRadioStationSheet: View {
    @ObservedObject private var radioStore = RadioStore.shared
    @Binding var isPresented: Bool

    /// When non-nil, the sheet edits this station in place. When nil, it
    /// creates a new one.
    let existing: RadioStation?

    @State private var name: String = ""
    @State private var streamURLText: String = ""
    @State private var category: RadioCategory = .newsTalk
    @State private var websiteText: String = ""
    @State private var descriptionText: String = ""
    @State private var validationError: String?

    init(isPresented: Binding<Bool>, existing: RadioStation? = nil) {
        self._isPresented = isPresented
        self.existing = existing
        if let existing {
            self._name = State(initialValue: existing.name)
            self._streamURLText = State(initialValue: existing.streamURL.absoluteString)
            self._category = State(initialValue: existing.category)
            self._websiteText = State(initialValue: existing.website?.absoluteString ?? "")
            self._descriptionText = State(initialValue: existing.description)
        }
    }

    private var isEditing: Bool { existing != nil }
    private var headerTitle: String { isEditing ? "Edit Station" : "Add Custom Station" }
    private var primaryActionLabel: String { isEditing ? "Save" : "Add" }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(headerTitle)
                    .font(.headline)
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                Button(primaryActionLabel, action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding()

            Divider()

            Form {
                Section("Station") {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                    TextField("Stream URL", text: $streamURLText, prompt: Text("https://stream.example.com/live"))
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.URL)
                        .autocorrectionDisabled(true)
                    Picker("Category", selection: $category) {
                        ForEach(displayedCategories, id: \.self) { cat in
                            Text(cat.displayName).tag(cat)
                        }
                    }
                }

                Section("Optional") {
                    TextField("Website", text: $websiteText, prompt: Text("https://example.com"))
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.URL)
                        .autocorrectionDisabled(true)
                    TextField("Description", text: $descriptionText, prompt: Text("e.g. Independent jazz radio from Berlin"))
                        .textFieldStyle(.roundedBorder)
                }

                if let validationError {
                    Section {
                        Label(validationError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 460, height: 460)
    }

    /// User-pickable categories. We hide `.aggregator` because that mode is
    /// internal to the bundled catalog and not meaningful for a user-added URL.
    private var displayedCategories: [RadioCategory] {
        RadioCategory.allCases.filter { $0 != .aggregator }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && URL(string: streamURLText.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURLText = streamURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationError = "Name is required."
            return
        }
        guard let streamURL = URL(string: trimmedURLText),
              streamURL.scheme?.lowercased().hasPrefix("http") == true else {
            validationError = "Stream URL must be a valid http(s) URL."
            return
        }
        let website: URL? = {
            let trimmed = websiteText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return URL(string: trimmed)
        }()
        let trimmedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing {
            let updated = RadioStation(
                id: existing.id,
                name: trimmedName,
                category: category,
                genre: category.displayName,
                location: existing.location,
                country: existing.country,
                latitude: existing.latitude,
                longitude: existing.longitude,
                streamURL: streamURL,
                website: website,
                streamType: existing.streamType,
                bitrate: existing.bitrate,
                codec: existing.codec,
                description: trimmedDescription,
                notes: existing.notes,
                isUserAdded: true
            )
            radioStore.updateUserStation(updated)
        } else {
            radioStore.addUserStation(
                name: trimmedName,
                streamURL: streamURL,
                category: category,
                website: website,
                description: trimmedDescription
            )
        }
        isPresented = false
    }
}
