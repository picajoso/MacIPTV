import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Darwin
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

            Toggle("Permitir HTTP sin cifrar para esta fuente", isOn: $viewModel.allowHTTP)
            if viewModel.allowHTTP {
                Text("HTTP puede exponer tu suscripción a quien intercepte la conexión. Usa HTTPS si tu proveedor lo admite.")
                    .font(.caption).foregroundStyle(.orange)
            }
            TextField("URL con IP del servidor local autorizado (opcional)", text: $viewModel.localServer)
                .textFieldStyle(.roundedBorder)
            Text("Déjalo vacío para bloquear accesos a otros servicios de tu ordenador y tu red. Autoriza solo tu servidor IPTV local.")
                .font(.caption).foregroundStyle(.secondary)

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
    @Published var allowHTTP = false
    @Published var localServer = ""
    private var fileBookmark: Data?
    private var bookmarkedPath: String?

    func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["m3u", "m3u8", "txt"].compactMap { UTType(filenameExtension: $0) } + [.plainText]
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                fileBookmark = try SavedSource.bookmark(for: url)
                bookmarkedPath = url.path
                m3uPath = url.path
            } catch { validationError = "No se pudo autorizar el archivo seleccionado." }
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
            guard fileBookmark != nil, trimmed == bookmarkedPath else {
                validationError = "Usa Elegir para autorizar el acceso al archivo de lista."
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
        var policy = NetworkPolicy(allowHTTP: allowHTTP)
        if let local = optional(localServer) {
            do {
                let url = try XtreamEndpoints.validatedBaseURL(local)
                guard let host = url.host, NetworkPolicy.isPublicAddress(host) || isLocalIPLiteral(host),
                      let port = UInt16(exactly: url.port ?? (url.scheme == "http" ? 80 : 443)), port > 0 else {
                    validationError = "Autoriza una IP concreta y su puerto, por ejemplo http://192.168.1.10:8080."
                    return false
                }
                policy.localEndpoints.insert(NetworkPolicy.endpointKey(host: host, port: port))
            } catch { validationError = "La URL del servidor local no es válida."; return false }
        }
        loading = true
        validationError = nil
        store.load(source, policy: policy, fileBookmark: kind == .m3uFile ? fileBookmark : nil)
        // La pantalla se cierra; el estado y los errores se ven en la ventana.
        return true
    }

    private func optional(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    private func isLocalIPLiteral(_ host: String) -> Bool {
        let address = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        var v4 = in_addr(); var v6 = in6_addr()
        return inet_pton(AF_INET, address, &v4) == 1 || inet_pton(AF_INET6, address, &v6) == 1
    }
}
