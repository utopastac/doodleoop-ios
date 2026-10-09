import SwiftUI

/// How a round works — opened from Home in place of a system alert.
struct RulesSheet: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 0) {
      DoodleSheetHeader(title: "The rules", onDone: { dismiss() })
        .gridBand()
        .sheetHeaderInset()

      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          Text("A drawing relay. One category starts every pad, then the story drifts as it passes left.")
            .themeText(.label)
            .foregroundStyle(Theme.Text.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .pageHorizontalPadding()
            .padding(.top, Theme.Spacing.s6)
            .padding(.bottom, Theme.Spacing.s4)
            .accessibilityIdentifier("rules-sheet")

          ForEach(Array(RuleStep.all.enumerated()), id: \.element.id) { index, step in
            if index > 0 {
              GridLine(axis: .horizontal)
            }
            ruleRow(number: index + 1, step: step)
          }
        }
        .padding(.bottom, Theme.Spacing.s6)
      }
      .scrollBounceBehavior(.basedOnSize)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .paperBackground()
    .pageMargins()
  }

  private func ruleRow(number: Int, step: RuleStep) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s4) {
      Text("\(number)")
        .themeText(.subheading)
        .foregroundStyle(Theme.Text.tertiary)
        .frame(width: Theme.Spacing.s7, alignment: .leading)

      VStack(alignment: .leading, spacing: Theme.Spacing.s1) {
        Text(step.title)
          .themeText(.body)
          .foregroundStyle(Theme.Text.primary)

        Text(step.detail)
          .themeText(.label)
          .foregroundStyle(Theme.Text.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .pageHorizontalPadding()
    .padding(.vertical, Theme.Spacing.s4)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("rules-step-\(step.id)")
  }
}

private struct RuleStep: Identifiable {
  let id: String
  let title: String
  let detail: String

  static let all: [RuleStep] = [
    RuleStep(
      id: "category",
      title: "Name a category",
      detail: "The host picks what everyone draws."
    ),
    RuleStep(
      id: "draw",
      title: "Everyone draws it",
      detail: "Same prompt, on every pad."
    ),
    RuleStep(
      id: "pass",
      title: "Pass left",
      detail: "Each pad moves one seat around the table."
    ),
    RuleStep(
      id: "guess",
      title: "Guess the drawing",
      detail: "Write what you think is in front of you."
    ),
    RuleStep(
      id: "draw-guess",
      title: "Draw that guess",
      detail: "The next person sketches the description."
    ),
    RuleStep(
      id: "around",
      title: "Once around",
      detail: "Alternate draw and guess until the pad comes home. You never draw on your own pad again."
    ),
    RuleStep(
      id: "reveal",
      title: "Reveal",
      detail: "Walk each pad one step at a time, then start another category."
    ),
  ]
}
