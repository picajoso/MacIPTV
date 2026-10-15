import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Darwin
import MacIPTVCore

/// Asistente para configurar la fuente: M3U (URL o archivo) o Xtream.
struct SourceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @ObservedObject var viewModel: SourceFormModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PROVEEDOR").font(Archivo.font(10, weight: .semibold)).tracking(1.4)
                .foregroundStyle(Theme.accentText)
            Text("Configurar fuente").font(Archivo.font(22, weight: .heavy))
                .padding(.top, 5).padding(.bottom, 22)
            Text("Tipo de fuente").font(Archivo.font(12)).foregroundStyle(Theme.muted)
                .padding(.bottom, 7)
            HStack(spacing: 0) {
                sourceKind("Lista M3U", .m3uURL)
                sourceKind("Archivo M3U", .m3uFile)
                sourceKind("Servidor Xtream", .xtream)
            }
            .overlay { Rectangle().stroke(Theme.divider, lineWidth: 1) }
            .padding(.bottom, 20)

            switch viewModel.kind {
            case .m3uURL:
                sourceField("URL de la lista", placeholder: "https://…", text: $viewModel.m3uURL)
                xmltvField
            case .m3uFile:
                Text("Archivo de lista").font(Archivo.font(12)).foregroundStyle(Theme.muted)
                    .padding(.bottom, 7)
                HStack(spacing: 0) {
                    inputField("Ruta del archivo .m3u", text: $viewModel.m3uPath)
                    Button("Elegir…") { viewModel.pickFile() }
                        .font(Archivo.font(12.5, weight: .semibold))
                        .frame(width: 82, height: 36)
                        .background(Theme.chip)
                        .overlay { Rectangle().stroke(Theme.divider, lineWidth: 1) }
                }
                .padding(.bottom, 14)
                xmltvField
            case .xtream:
                sourceField("Dirección del servidor", placeholder: "host o host:puerto", text: $viewModel.xtreamBase)
                sourceField("Usuario", placeholder: "Usuario", text: $viewModel.xtreamUser)
                Text("Contraseña").font(Archivo.font(12)).foregroundStyle(Theme.muted)
                    .padding(.bottom, 7)
                SecureField("Contraseña", text: $viewModel.xtreamPass)
                    .textFieldStyle(.plain).font(Archivo.font(13.5))
                    .padding(.horizontal, 10).frame(height: 36)
                    .background(Theme.surface)
                    .overlay { Rectangle().stroke(Theme.divider, lineWidth: 1) }
                Text("La programación (XMLTV) se obtiene automáticamente del propio servidor.")
                    .font(Archivo.font(11.5)).foregroundStyle(Theme.muted).padding(.top, 7)
            }
            Button { viewModel.allowHTTP.toggle() } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Rectangle().fill(viewModel.allowHTTP ? Theme.accent : Theme.surface)
                        Rectangle().stroke(viewModel.allowHTTP ? Theme.accent : Theme.divider, lineWidth: 1)
                        if viewModel.allowHTTP { LucideIcon(name: "check", size: 13).foregroundStyle(.white) }
                    }.frame(width: 18, height: 18)
                    Text("Permitir HTTP sin cifrar para esta fuente")
                        .font(Archivo.font(12.5)).foregroundStyle(Theme.fg)
                }
            }
            .buttonStyle(.plain).padding(.top, 22).padding(.bottom, 9)
            if viewModel.allowHTTP {
                Text("HTTP puede exponer tu suscripción a quien intercepte la conexión. Usa HTTPS si tu proveedor lo admite.")
                    .font(Archivo.font(11.5)).foregroundStyle(Theme.accentText)
                    .padding(.bottom, 10)
            }
            sourceField("Servidor local autorizado (opcional)", placeholder: "http://192.168.1.10:8080",
                        text: $viewModel.localServer)
            Text("Déjalo vacío para bloquear la red local. Autoriza solo una IP y un puerto de confianza.")
                .font(Archivo.font(11.5)).foregroundStyle(Theme.muted)

            if let error = viewModel.validationError {
                HStack(spacing: 8) { LucideIcon(name: "triangle-alert", size: 15); Text(error) }
                    .font(Archivo.font(12.5)).foregroundStyle(Theme.accentText).padding(.top, 12)
            }
            if viewModel.loading {
                ProgressView("Cargando canales…").padding(.top, 12)
            }
            Spacer(minLength: 16)
            HStack(spacing: 0) {
                Button("Cancelar") { dismiss() }.disabled(viewModel.loading)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Theme.surface)
                    .keyboardShortcut(.cancelAction)
                Button("Conectar") {
                    if viewModel.submit(store: store) { dismiss() }
                }
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(Theme.accent).foregroundStyle(Theme.onRed)
                .keyboardShortcut(.defaultAction).disabled(viewModel.loading)
            }
            .buttonStyle(.plain).font(Archivo.font(13, weight: .heavy))
        }
        .padding(24)
        .frame(width: 540, height: 580)
        .background(Theme.bg).foregroundStyle(Theme.fg)
        .onAppear { viewModel.restore(from: store) }
    }

    private var xmltvField: some View {
        sourceField("URL XMLTV (opcional)", placeholder: "https://…", text: $viewModel.xmltvURL)
    }

    private func sourceKind(_ title: String, _ kind: SourceFormModel.Kind) -> some View {
        Button { viewModel.kind = kind } label: {
            Text(title).font(Archivo.font(12.5, weight: .semibold))
                .frame(maxWidth: .infinity).frame(height: 38)
                .background(viewModel.kind == kind ? Theme.accent : Theme.surface)
                .foregroundStyle(viewModel.kind == kind ? Theme.onRed : Theme.fg)
        }.buttonStyle(.plain)
    }

    private func sourceField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(Archivo.font(12)).foregroundStyle(Theme.muted)
            inputField(placeholder, text: text)
        }.padding(.bottom, 14)
    }

    private func inputField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain).font(Archivo.font(13.5))
            .padding(.horizontal, 10).frame(height: 36)
            .background(Theme.surface)
            .overlay { Rectangle().stroke(Theme.divider, lineWidth: 1) }
    }
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
