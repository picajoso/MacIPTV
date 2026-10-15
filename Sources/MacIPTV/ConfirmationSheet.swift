import SwiftUI

struct ConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(Archivo.font(20, weight: .heavy)).padding(.bottom, 12)
            Text(message).font(Archivo.font(14)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 24)
            HStack(spacing: 0) {
                Button("Cancelar") { dismiss() }
                    .frame(maxWidth: .infinity).frame(height: 52).background(Theme.surface)
                    .keyboardShortcut(.cancelAction)
                Button(actionTitle) {
                    dismiss()
                    action()
                }
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(Theme.accent).foregroundStyle(Theme.onRed)
                .keyboardShortcut(.defaultAction)
            }
            .buttonStyle(.plain).font(Archivo.font(13, weight: .heavy))
        }
        .padding(24).frame(width: 460, height: 200)
        .background(Theme.bg).foregroundStyle(Theme.fg)
    }
}
