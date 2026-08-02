import SwiftUI

struct HomeView: View {
  @EnvironmentObject private var session: GameSession
  @State private var nameDraft = ""

  var body: some View {
    NavigationStack {
      VStack(spacing: 28) {
        Spacer()

        Text("Doodleoop")
          .font(.system(size: 48, weight: .black, design: .rounded))
          .foregroundStyle(Theme.ink)

        Text("Draw, pass left, guess — pictorial Chinese whispers.")
          .font(.title3)
          .multilineTextAlignment(.center)
          .foregroundStyle(Theme.ink.opacity(0.7))
          .padding(.horizontal, 32)

        TextField("Your name", text: $nameDraft)
          .textFieldStyle(.roundedBorder)
          .padding(.horizontal, 40)
          .onAppear { nameDraft = session.localDisplayName }
          .onSubmit { session.updateDisplayName(nameDraft) }

        VStack(spacing: 12) {
          Button("Create game") {
            session.updateDisplayName(nameDraft)
            session.hostGame()
          }
          .buttonStyle(PrimaryButtonStyle(color: Theme.coral))

          Button("Join game") {
            session.updateDisplayName(nameDraft)
            session.startBrowsing()
          }
          .buttonStyle(PrimaryButtonStyle(color: Theme.teal))
        }
        .padding(.horizontal, 40)

        Spacer()
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Theme.paper.ignoresSafeArea())
    }
  }
}

struct PrimaryButtonStyle: ButtonStyle {
  var color: Color

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline.weight(.bold))
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 14)
      .background(color.opacity(configuration.isPressed ? 0.8 : 1))
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}
