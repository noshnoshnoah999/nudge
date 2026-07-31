// WidgetBackgroundView.swift — pick a custom background image for the Today widget.
//
// WHY THIS SCREEN EXISTS IN THE APP AND NOT IN WIDGET EDIT MODE:
// The widget's own Edit mode (long-press → Edit Widget) is driven by an AppIntent, and an
// AppIntent parameter can't present a photo picker. So the *choice* of "My Wallpaper
// Screenshot" is made in widget Edit mode, but the actual image is picked here.
//
// HOW IT REACHES THE WIDGET:
// Via the shared Keychain access group — see WidgetBackgroundImageStore. There is no App
// Group on this project (free Apple team), so the Keychain is the only store both targets
// can read. The image never leaves the device and is never uploaded or synced.

import SwiftUI
import PhotosUI
import WidgetKit

struct WidgetBackgroundView: View {
    @State private var picked: PhotosPickerItem?
    @State private var preview: UIImage?
    @State private var error: String?
    @State private var savedConfirmation = false
    @State private var loading = false

    var body: some View {
        List {
            Section {
                if let preview {
                    // Shown on a checkerboard-ish neutral so a pure-black image is still
                    // visibly *there* rather than looking like an empty row.
                    Image(uiImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radius(12), style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radius(12), style: .continuous)
                                .stroke(.secondary.opacity(0.35), lineWidth: 1)
                        )
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                } else {
                    Label("No image set", systemImage: "photo.on.rectangle.angled")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Current image")
            } footer: {
                Text("A pure black image looks like an empty box here — that's expected.")
            }
            .listRowBackground(Theme.surface)

            Section {
                PhotosPicker(selection: $picked, matching: .screenshots) {
                    Label(preview == nil ? "Choose screenshot" : "Replace screenshot",
                          systemImage: "photo.badge.plus")
                }
                if preview != nil {
                    Button(role: .destructive) {
                        WidgetBackgroundImageStore.clear()
                        preview = nil
                        error = nil
                        reloadWidgets()
                    } label: {
                        Label("Remove image", systemImage: "trash")
                    }
                }
            } header: {
                Text("Image")
            } footer: {
                Text("Filtered to screenshots. Pick a screenshot of an empty Home Screen page — "
                   + "the widget will use it as its background so it blends into your wallpaper.")
            }
            .listRowBackground(Theme.surface)

            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .listRowBackground(Theme.surface)
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    step(1, "Swipe to an empty Home Screen page — no icons, no widgets.")
                    step(2, "Screenshot it (side button + volume up).")
                    step(3, "Choose that screenshot above.")
                    step(4, "Long-press the Today widget → Edit Widget → set Background to "
                          + "“My Wallpaper Screenshot”.")
                }
                .font(.footnote)
                .padding(.vertical, 4)
            } header: {
                Text("How to set it up")
            } footer: {
                Text("The image is stored only on this iPhone. It isn't uploaded to Supabase "
                   + "and won't sync to your MacBook.")
            }
            .listRowBackground(Theme.surface)
        }
        .navigationTitle("Widget Background")
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .onAppear { preview = WidgetBackgroundImageStore.loadImage() }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .overlay {
            if loading { ProgressView().controlSize(.large) }
        }
        .alert("Saved", isPresented: $savedConfirmation) {
            Button("OK") { }
        } message: {
            Text("The widget will pick this up on its next refresh. If it looks unchanged, "
               + "check Edit Widget → Background is set to “My Wallpaper Screenshot”.")
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n).").monospacedDigit().foregroundStyle(.secondary)
            Text(text)
        }
    }

    @MainActor
    private func load(_ item: PhotosPickerItem) async {
        loading = true
        defer { loading = false }
        error = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            error = "Couldn't read that image. Try another screenshot."
            return
        }
        if let reason = WidgetBackgroundImageStore.save(image) {
            error = reason
            return
        }
        preview = WidgetBackgroundImageStore.loadImage()
        reloadWidgets()
        savedConfirmation = true
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: "NudgeToday")
    }
}
