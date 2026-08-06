import SwiftUI

/// Host/joiner strip showing which phones are live, reconnecting, or gone.
struct ConnectionPresenceStrip: View {
  let presences: [DeviceConnectionPresence]

  private var visible: [DeviceConnectionPresence] {
    let remotes = presences.filter { !$0.isLocal }
    return remotes.isEmpty ? presences : remotes
  }

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: Theme.Spacing.s2) {
        ForEach(visible) { presence in
          presenceChip(presence)
        }
      }
      .padding(.horizontal, Theme.Layout.pageMargin)
    }
  }

  private func presenceChip(_ presence: DeviceConnectionPresence) -> some View {
    HStack(spacing: Theme.Spacing.s1) {
      statusDot(presence.status)
      Text(presence.isLocal ? "You" : presence.name)
        .themeText(.caption)
        .foregroundStyle(Theme.Text.primary)
        .lineLimit(1)
      if presence.status == .reconnecting {
        ProgressView()
          .controlSize(.mini)
          .tint(Theme.Accent.default)
      }
    }
    .padding(.horizontal, Theme.Spacing.s2)
    .padding(.vertical, Theme.Spacing.s1)
    .background(Theme.Paper.beige)
    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .circular))
    .overlay {
      RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .circular)
        .strokeBorder(Theme.Stroke.subtle, lineWidth: Theme.Borders.thin)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel(for: presence))
  }

  private func statusDot(_ status: DeviceConnectionStatus) -> some View {
    Circle()
      .fill(color(for: status))
      .frame(width: 8, height: 8)
  }

  private func color(for status: DeviceConnectionStatus) -> Color {
    switch status {
    case .connected: Theme.Accent.default
    case .reconnecting: Theme.Ink.medium
    case .absent: Theme.Text.tertiary
    }
  }

  private func accessibilityLabel(for presence: DeviceConnectionPresence) -> String {
    let who = presence.isLocal ? "You" : presence.name
    switch presence.status {
    case .connected: return "\(who), connected"
    case .reconnecting: return "\(who), reconnecting"
    case .absent: return "\(who), left"
    }
  }
}

/// Full-screen joiner overlay while hunting for the host after a drop.
struct ReconnectOverlay: View {
  var onLeave: () -> Void
  @State private var spin = false

  var body: some View {
    ZStack {
      Theme.Paper.cream.opacity(0.94)
        .ignoresSafeArea()

      VStack(spacing: Theme.Spacing.s5) {
        PhosphorIcon.arrowsClockwise.image
          .resizable()
          .renderingMode(.template)
          .scaledToFit()
          .frame(width: Theme.Sizing.iconLg, height: Theme.Sizing.iconLg)
          .foregroundStyle(Theme.Accent.default)
          .rotationEffect(.degrees(spin ? 360 : 0))
          .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: spin)

        VStack(spacing: Theme.Spacing.s2) {
          Text("Reconnecting")
            .themeText(.heading)
            .foregroundStyle(Theme.Text.primary)

          Text("Looking for the host on the local network. Keep Doodleoop open — we’ll rejoin automatically for a few seconds.")
            .themeText(.body)
            .foregroundStyle(Theme.Text.secondary)
            .multilineTextAlignment(.center)
            .pageHorizontalPadding()
        }

        ProgressView()
          .tint(Theme.Accent.default)

        Button(DoodleLabel.bracketed("Leave game"), action: onLeave)
          .doodleButton(.secondary)
          .padding(.top, Theme.Spacing.s3)
      }
      .pageHorizontalPadding()
    }
    .onAppear { spin = true }
    .accessibilityElement(children: .contain)
  }
}

/// Shown while electing or seeking a new network host after the previous one dropped.
struct HostMigrationOverlay: View {
  var isBecomingHost: Bool
  var onLeave: () -> Void
  @State private var spin = false

  var body: some View {
    ZStack {
      Theme.Paper.cream.opacity(0.94)
        .ignoresSafeArea()

      VStack(spacing: Theme.Spacing.s5) {
        PhosphorIcon.wifiHigh.image
          .resizable()
          .renderingMode(.template)
          .scaledToFit()
          .frame(width: Theme.Sizing.iconLg, height: Theme.Sizing.iconLg)
          .foregroundStyle(Theme.Accent.default)
          .opacity(spin ? 1 : 0.55)
          .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: spin)

        VStack(spacing: Theme.Spacing.s2) {
          Text(isBecomingHost ? "Taking over as host" : "Host left")
            .themeText(.heading)
            .foregroundStyle(Theme.Text.primary)

          Text(
            isBecomingHost
              ? "This phone is picking up the game so everyone can keep playing."
              : "Looking for another phone to host this game on the local network."
          )
            .themeText(.body)
            .foregroundStyle(Theme.Text.secondary)
            .multilineTextAlignment(.center)
            .pageHorizontalPadding()
        }

        ProgressView()
          .tint(Theme.Accent.default)

        Button(DoodleLabel.bracketed("Leave game"), action: onLeave)
          .doodleButton(.secondary)
          .padding(.top, Theme.Spacing.s3)
      }
      .pageHorizontalPadding()
    }
    .onAppear { spin = true }
    .accessibilityElement(children: .contain)
  }
}
