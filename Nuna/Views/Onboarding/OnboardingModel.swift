//
//  OnboardingModel.swift
//  Nuna
//

import Foundation

struct OnboardingPage: Codable, Identifiable, Sendable {
    let n: Int
    let image: String
    let title: LocalizedText
    let body: LocalizedText
    let colors: [String]
    let bands: Int

    var id: Int { n }
}

struct OnboardingContent: Codable, Sendable {
    let pages: [OnboardingPage]
    let cta: LocalizedText
    let skip: LocalizedText
    /// Rótulo das telas intermediárias. Cai para um padrão se faltar no JSON.
    let nextRaw: LocalizedText?

    var next: LocalizedText {
        nextRaw ?? ["en": "Next"]
    }

    private enum CodingKeys: String, CodingKey {
        case pages, cta, skip
        case nextRaw = "next"
    }

    static func load(bundle: Bundle = .main) -> OnboardingContent? {
        guard let url = bundle.url(forResource: "onboarding", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(OnboardingContent.self, from: data)
    }
}
