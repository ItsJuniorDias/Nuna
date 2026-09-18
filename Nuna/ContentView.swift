//
//  ContentView.swift
//  Nuna
//
//  Created by Alexandre Junior on 16/09/26.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("onboardingConcluido") private var onboardingDone = false

    @State private var books: [Book] = []
    @State private var onboarding: OnboardingContent?
    @State private var carregando = true
    /// Paywall de boas-vindas: sobe uma vez, no fim do onboarding, por cima
    /// da Home. Fechar cai direto na Home, com as histórias da semana liberadas.
    @State private var paywallPosOnboarding = false
    /// A intro já tinha sido vista antes: o próximo onboarding é o "Replay
    /// the intro". Não dá para ler de `onboardingDone` na hora — no replay ele
    /// já voltou a `false`.
    @State private var introJaVista = false
    @State private var gatilhoDoPaywall: GatilhoDoOnboarding = .primeiraVez

    var body: some View {
        Group {
            if carregando {
                ProgressView().tint(UITokens.inkSecondary)
            } else if !onboardingDone, let onboarding {
                OnboardingView(content: onboarding,
                               gatilho: introJaVista ? .replay : .primeiraVez,
                               onFinish: concluirOnboarding)
                .medirPostura()
            } else {
                RootView(books: books)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(UITokens.surface)
        .task {
            // A tarefa mora no Group e roda de novo a cada troca de ramo
            // (carregando → onboarding → Home, e no replay da intro). Carregar
            // de novo não mudava nada; registrar de novo duplicaria o evento.
            guard carregando else { return }
            let inicio = Date()
            books = Catalog.loadAll(primeiros: Store.livrosGratis)
            Store.shared.catalogo = books
            onboarding = OnboardingContent.load()
            let duracao = Date.now.timeIntervalSince(inicio)
            introJaVista = onboardingDone
            carregando = false

            Analytics.shared.track(.catalogLoaded(
                fonte: Catalog.usouReserva ? .bundleFallback : .manifest,
                livros: books.count,
                disponiveis: books.filter(\.isAvailable).count,
                capasFaltando: books.filter { $0.isAvailable && UIImage(named: $0.coverImageName) == nil }.count,
                onboardingCarregado: onboarding != nil,
                duracao: duracao))
        }
        // Nada de portão aqui: ver os planos não compra nada. O portão
        // continua no botão Subscribe do próprio paywall.
        .fullScreenCover(isPresented: $paywallPosOnboarding) {
            PaywallView(origem: .posOnboarding(gatilhoDoPaywall)) { paywallPosOnboarding = false }
                .medirPostura()
        }
    }

    /// Vale para "Start reading", para "Skip" e para o fim do "Replay the
    /// intro" da área dos pais. Quem já assina não vê planos de novo.
    private func concluirOnboarding(_ fim: FimDoOnboarding) {
        // Segundo toque durante a transição de 0,35 s.
        guard !onboardingDone else { return }
        let gatilho: GatilhoDoOnboarding = introJaVista ? .replay : .primeiraVez
        let mostraPaywall = !Store.shared.isPremium
        let paginas = onboarding?.pages.count ?? 0

        switch fim {
        case .concluiu(let inicio):
            Analytics.shared.track(.onboardingCompleted(
                gatilho: gatilho, paginas: paginas, mostraPaywall: mostraPaywall,
                duracao: Date.now.timeIntervalSince(inicio)))
        case .pulou(let pagina, let inicio):
            Analytics.shared.track(.onboardingSkipped(
                gatilho: gatilho, indice: pagina, paginas: paginas,
                mostraPaywall: mostraPaywall, duracao: Date.now.timeIntervalSince(inicio)))
        }

        introJaVista = true
        withAnimation(.easeInOut(duration: 0.35)) { onboardingDone = true }
        if mostraPaywall {
            gatilhoDoPaywall = gatilho
            paywallPosOnboarding = true
        }
    }
}

#Preview("App") { ContentView() }
