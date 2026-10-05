import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MacIPTVCore

/// Asistente para configurar la fuente: M3U (URL o archivo) o Xtream.
struct SourceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: SourceFormModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Tipo de fuente", selection: $viewModel.kind) {
                Text("Lista M3U").tag(SourceFormModel.Kind.m3uURL)
                Text("Archivo M3U").tag(SourceFormModel.Kind.m3uFile)
                Text("Servidor Xtream").tag(SourceFormModel.Kind.xtream)
            }
            .pickerStyle(.segmented)

            switch viewModel.kind {
            case .m3uURL:
                TextField("URL de la lista (https://...)", text: $viewModel.m3uURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                xmltvField
            case .m3uFile:
                HStack {
                    TextField("Ruta del archivo .m3u", text: $viewModel.m3uPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Elegir...") { viewModel.pickFile() }
                }
                xmltvField
            case .xtream:
                TextField("Direccion del servidor (host o host:puerto)", text: $viewModel.xtreamBase)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                TextField("Usuario", text: $viewModel.xtreamUser)
                    .textFieldStyle(.roundedBorder)
                SecureField("Contrasena", text: $viewModel.xtreamPass)
                    .textFieldStyle(.roundedBorder)
                Text("La programacion (XMLTV) se obtiene automaticamente del propio servidor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = viewModel.validationError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            if viewModel.loading {
                ProgressView("Cargando canales...")
            }

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                    .disabled(viewModel.loading)
                Button("Conectar") {
                    if viewModel.submit(store: store) { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.loading)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { viewModel.restore(from: store) }
    }

    private var xmltvField: some View {
        TextField("URL XMLTV opcional (programacion)", text: $viewModel.xmltvURL)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
    }

    @Environment(AppStore.self) private var store
}

/// Contenedor de la hoja: mantiene el modelo del formulario vivo durante toda
/// la edicion (un SourceFormModel inline se recrearia en cada render).
struct SourceSettingsSheet: View {
    @State private var viewModel = SourceFormModel()

    var body: some View {
        SourceSettingsView(viewModel: viewModel)
    }
}

@MainActor
final class SourceFormModel: ObservableObject {
    enum Kind { case m3uURL, m3uFile, xtream }

    @Published var kind: Kind = .m3uURL
    @Published var m3uURL = ""
    @Published var m3uPath = ""
    @Published var xmltvURL = ""
    @Published var xtreamBase = ""
    @Published var xtreamUser = ""
    @Published var xtreamPass = ""
    @Published var validationError: String?
    @Published var loading = false

    func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["m3u", "m3u8", "txt"].compactMap { UTType(filenameExtension: $0) } + [.plainText]
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            m3uPath = url.path
        }
    }

    /// Precarga lo guardado (menos la contrasena, que no se muestra nunca).
    func restore(from store: AppStore) {
        // Al abrir la pantalla se permite una nueva importacion.
        loading = false
        validationError = nil
        // Solo preajusta el tipo; los secretos permanecen en el Llavero.
        if store.sourceSummary?.hasPrefix("Xtream") == true { kind = .xtream }
        else if store.sourceSummary?.hasPrefix("Archivo") == true { kind = .m3uFile }
    }

    func submit(store: AppStore) -> Bool {
        validationError = nil
        let source: SourceConfiguration
        switch kind {
        case .m3uURL:
            let trimmed = m3uURL.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else {
                validationError = "La URL debe empezar por http:// o https://"
                return false
            }
            source = .m3uURL(url: trimmed, xmltvURL: optional(xmltvURL))
        case .m3uFile:
            let trimmed = m3uPath.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                validationError = "Elige un archivo de lista."
                return false
            }
            source = .m3uFile(path: trimmed, xmltvURL: optional(xmltvURL))
        case .xtream:
            let base = xtreamBase.trimmingCharacters(in: .whitespaces)
            guard !base.isEmpty, !xtreamUser.isEmpty, !xtreamPass.isEmpty else {
                validationError = "Faltan datos del servidor Xtream."
                return false
            }
            // Validacion con componentes de URL: rechaza ftp u otros esquemas
            // explicitos en lugar de prefijar http.
            do {
                _ = try XtreamEndpoints.validatedBaseURL(base)
            } catch let error as IPTVError {
                validationError = error.errorDescription
                return false
            } catch {
                validationError = "La direccion del servidor no es valida."
                return false
            }
            source = .xtream(baseURL: base, username: xtreamUser, password: xtreamPass)
        }
        loading = true
        validationError = nil
        store.load(source)
        // La pantalla se cierra; el estado y los errores se ven en la ventana.
        return true
    }

    private func optional(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }
}
