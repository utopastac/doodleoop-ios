import Foundation

/// Curated prompts for the host’s “what are we drawing?” sheet.
enum RoundCategories {
  static let all: [String] = [
    "Farm animals",
    "Sea creatures",
    "Zoo animals",
    "Pets",
    "Birds",
    "Bugs and insects",
    "Dinosaurs",
    "Magical creatures",
    "Breakfast foods",
    "Desserts",
    "Fruits",
    "Vegetables",
    "Fast food",
    "Pizza toppings",
    "Things you grill",
    "Jobs",
    "Sports",
    "Winter sports",
    "Olympic events",
    "Musical instruments",
    "Vehicles",
    "Things that fly",
    "Things that float",
    "Things with wheels",
    "Things with wings",
    "Things that are round",
    "Things that make noise",
    "Things in a kitchen",
    "Things in a bathroom",
    "Things at the beach",
    "Things in space",
    "Things at a circus",
    "School supplies",
    "Tools",
    "Furniture",
    "Clothing",
    "Hats",
    "Shoes",
    "Holidays",
    "Weather",
    "Emotions",
    "Hobbies",
    "Outdoor activities",
    "Board games",
    "Video game characters",
    "Superheroes",
    "Fairy tale characters",
    "Movie monsters",
    "Famous landmarks",
    "Flowers",
  ]

  static func random(excluding current: String = "") -> String {
    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
    let pool = all.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
    return (pool.randomElement() ?? all.randomElement()) ?? "Animals"
  }
}
