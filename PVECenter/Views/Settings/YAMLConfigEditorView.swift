import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct YAMLConfigEditorView: View {
    public var viewModel: AppViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentTheme) private var accentTheme

    @State private var yamlText: String = ""
    @State private var originalYamlText: String = ""
    @State private var currentHash: String = ""
    @State private var parsedSummary: [String: JSONValue] = [:]

    @State private var isLoading: Bool = true
    @State private var isValidating: Bool = false
    @State private var isSaving: Bool = false
    @State private var validationResult: YAMLValidationResponse?
    @State private var exportText: String = ""
    @State private var copiedFeedback: Bool = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    private var hasUnsavedChanges: Bool {
        yamlText != originalYamlText
    }

    private var lineCount: Int {
        yamlText.isEmpty ? 0 : yamlText.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    public var body: some View {
        NavigationStack {
            Group {
                #if os(tvOS)
                tvOSLayout
                #else
                standardLayout
                #endif
            }
            .navigationTitle("Configuration YAML")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                #if !os(tvOS)
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Task { await loadConfig() }
                    } label: {
                        Label("Recharger", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading || isSaving)

                    #if os(iOS) || os(macOS)
                    ShareLink(
                        item: YAMLTransferableFile(content: exportText.isEmpty ? yamlText : exportText),
                        preview: SharePreview("config.yaml", image: Image(systemName: "doc.plaintext"))
                    ) {
                        Label("Exporter", systemImage: "square.and.arrow.up")
                    }
                    .disabled(yamlText.isEmpty)
                    #endif
                }
                #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 640, idealWidth: 740, minHeight: 560)
        #endif
        .task {
            await loadConfig()
        }
    }

    // MARK: - iOS & macOS Layout

    #if !os(tvOS)
    private var standardLayout: some View {
        VStack(spacing: 0) {
            metadataHeaderBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)

            Divider()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView("Chargement de config.yaml…")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        summaryBadgesStrip

                        TextEditor(text: $yamlText)
                            .font(.system(.callout, design: .monospaced))
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .scrollContentBackground(.hidden)
                            .padding(12)
                            .frame(minHeight: 340)
                            .background(
                                editorBackground,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(DesignTokens.hairBorder(colorScheme), lineWidth: 1)
                            )
                            .onChange(of: yamlText) { _, _ in
                                if validationResult != nil {
                                    validationResult = nil
                                }
                            }

                        validationPanel
                    }
                    .padding(16)
                }

                Divider()
                actionBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.bar)
            }
        }
    }

    private var editorBackground: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.28)
            : Color.black.opacity(0.035)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                Task { await copyYAML() }
            } label: {
                Label(copiedFeedback ? "Copié" : "Copier", systemImage: copiedFeedback ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .disabled(yamlText.isEmpty)

            Button {
                Task { await validateSchema() }
            } label: {
                if isValidating {
                    ProgressView()
                        .adaptiveSmallControlSize()
                } else {
                    Label("Valider le schéma", systemImage: "checkmark.shield")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isValidating || isSaving || yamlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()

            Button {
                Task { await saveAndHotReload() }
            } label: {
                if isSaving {
                    ProgressView()
                        .adaptiveSmallControlSize()
                } else {
                    Label("Enregistrer et recharger à chaud", systemImage: "flame.fill")
                        .fontWeight(.semibold)
                }
            }
            .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme), prominent: true, cornerRadius: 10)
            .disabled(isSaving || isValidating || yamlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    #endif

    // MARK: - tvOS Read-Only Scrollable Fallback

    #if os(tvOS)
    private var tvOSLayout: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Configuration YAML")
                                .font(.largeTitle.weight(.bold))
                                .foregroundStyle(DesignTokens.primaryText(colorScheme))
                            Text("config.yaml en lecture seule sur Apple TV")
                                .font(.callout)
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                        }
                        Spacer()
                        Button {
                            Task { await loadConfig() }
                        } label: {
                            Label("Recharger", systemImage: "arrow.clockwise")
                                .font(.callout.weight(.semibold))
                        }
                        .adaptivePillButtonStyle()

                        Button {
                            guard !(isValidating || yamlText.isEmpty) else { return }
                            Task { await validateSchema() }
                        } label: {
                            Label("Valider le schéma", systemImage: "checkmark.shield")
                                .font(.callout.weight(.semibold))
                                .opacity((isValidating || yamlText.isEmpty) ? 0.45 : 1.0)
                        }
                        .adaptivePillButtonStyle(tint: DesignTokens.accent(accentTheme, colorScheme), prominent: true)

                        Button {
                            dismiss()
                        } label: {
                            Label("Fermer", systemImage: "xmark.circle.fill")
                                .font(.callout.weight(.semibold))
                        }
                        .adaptivePillButtonStyle()
                    }
                    .focusSection()

                    metadataHeaderBar
                    summaryBadgesStrip
                    validationPanel

                    GlassCard(padding: 24, cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(
                                "Mode lecture seule sur Apple TV — éditez la configuration YAML depuis iPhone, iPad, Mac ou le panneau web.",
                                systemImage: "info.circle.fill"
                            )
                            .font(.callout)
                            .foregroundStyle(DesignTokens.accent(accentTheme, colorScheme))

                            if isLoading {
                                ProgressView("Chargement de config.yaml…")
                                    .frame(maxWidth: .infinity, minHeight: 160)
                            } else {
                                Text(yamlText.isEmpty ? "Configuration YAML vide." : yamlText)
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 32)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
    #endif

    // MARK: - Shared Header & Validation Views

    private var metadataHeaderBar: some View {
        HStack(spacing: 10) {
            Label("\(lineCount) lignes", systemImage: "text.alignleft")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            if !currentHash.isEmpty {
                Text("SHA \(String(currentHash.prefix(10)))")
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.14), in: Capsule())
            }

            if hasUnsavedChanges {
                StatusPill("Modifié", color: DesignTokens.caution(colorScheme), systemImage: "pencil.circle.fill")
            }

            Spacer()

            if viewModel.isDemoMode {
                StatusPill("Mode Démo", color: .indigo, systemImage: "sparkles")
            }
        }
    }

    @ViewBuilder
    private var summaryBadgesStrip: some View {
        if !parsedSummary.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(parsedSummary.keys.sorted(), id: \.self) { key in
                        if let val = parsedSummary[key] {
                            HStack(spacing: 4) {
                                Text(key)
                                    .foregroundStyle(.secondary)
                                Text(val.displayString)
                                    .fontWeight(.semibold)
                            }
                            .font(.system(.caption2, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.secondary.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var validationPanel: some View {
        if let result = validationResult {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    StatusPill(
                        result.valid ? "Schéma valide" : "Erreurs détectées",
                        color: result.valid ? DesignTokens.nominal(colorScheme) : DesignTokens.critical(colorScheme),
                        systemImage: result.valid ? "checkmark.seal.fill" : "xmark.octagon.fill"
                    )
                    if let message = result.message, !message.isEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if !result.errors.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(result.errors, id: \.self) { err in
                            Label(err, systemImage: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                if !result.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(result.warnings, id: \.self) { warn in
                            Label(warn, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .padding(12)
            .background(
                (result.valid ? Color.green : Color.red).opacity(0.08),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder((result.valid ? Color.green : Color.red).opacity(0.3), lineWidth: 1)
            )
        }
    }

    // MARK: - Actions

    private func loadConfig() async {
        isLoading = true
        if let response = await viewModel.fetchYAMLConfig() {
            yamlText = response.yaml
            originalYamlText = response.yaml
            currentHash = response.hash
            parsedSummary = response.parsedSummary ?? [:]
            exportText = (await viewModel.exportYAMLConfig()) ?? response.yaml
        }
        isLoading = false
    }

    private func validateSchema() async {
        isValidating = true
        validationResult = await viewModel.validateYAMLConfig(yamlText)
        isValidating = false
    }

    private func saveAndHotReload() async {
        isSaving = true
        if let result = await viewModel.saveYAMLConfig(yamlText) {
            validationResult = result
            if result.valid {
                originalYamlText = yamlText
                if let hash = result.hash {
                    currentHash = hash
                }
                exportText = (await viewModel.exportYAMLConfig()) ?? yamlText
            }
        }
        isSaving = false
    }

    #if !os(tvOS)
    private func copyYAML() async {
        let content = (await viewModel.exportYAMLConfig()) ?? yamlText
        #if os(iOS)
        UIPasteboard.general.string = content
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        #endif
        copiedFeedback = true
        try? await Task.sleep(for: .seconds(2))
        copiedFeedback = false
    }
    #endif
}

private struct YAMLTransferableFile: Transferable, Sendable {
    let content: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: UTType(filenameExtension: "yaml") ?? .plainText) { item in
            Data(item.content.utf8)
        }
        .suggestedFileName("config.yaml")
    }
}
