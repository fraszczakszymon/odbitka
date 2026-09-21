import SwiftUI

/// Ekran powitalny, pokazywany raz — przed systemowym pytaniem o dostęp do Zdjęć.
///
/// Systemowy prompt pojawia się **dokładnie raz w życiu aplikacji**, a po odmowie
/// użytkownik może ją odblokować wyłącznie w Ustawieniach systemu. Zdanie o tym,
/// po co nam dostęp i że zdjęcia nigdzie nie wychodzą, realnie zmienia odsetek odmów —
/// i jest po prostu prawdą, którą warto powiedzieć.
struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "photo.stack")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .padding(.bottom, 24)

            Text(L.s("welcome.title"))
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            Text(L.s("welcome.subtitle"))
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 18) {
                WelcomePoint(icon: "arrow.triangle.2.circlepath", text: L.s("welcome.point.convert"))
                WelcomePoint(icon: "arrow.down.right.and.arrow.up.left", text: L.s("welcome.point.shrink"))
                WelcomePoint(icon: "textformat.abc", text: L.s("welcome.point.rename"))
                WelcomePoint(icon: "lock.shield", text: L.s("welcome.point.private"))
            }
            .padding(.top, 40)
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Button(action: onContinue) {
                    Text(L.s("welcome.action"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text(L.s("welcome.permissionNote"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }
    }
}

private struct WelcomePoint: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            Text(text)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
