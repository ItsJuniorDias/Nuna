//
//  Jornada.swift
//  Nuna
//
//  Onde esta família está na relação com o app, em três faixas: há quanto
//  tempo instalou, quantas vezes já viu o paywall, quantos livros terminou.
//  Vai junto do `paywall_viewed` para o painel responder quem converte —
//  primeira visita ou décima, recém-chegado ou de meses — sem identificar
//  ninguém: não há id, só faixas largas que muitos aparelhos compartilham.
//
//  Os contadores moram só no aparelho (UserDefaults) e nunca saem crus.
//  Só contam com o analytics ligado: o `Analytics.track` é quem chama.
//
//  Instalações de antes desta medição mandam "unknown": o app não sabe há
//  quanto tempo elas existem nem quantas vezes já viram o paywall, e chutar
//  um número misturaria veteranos com recém-chegados no painel.
//

import Foundation

enum Jornada {

    private static let defaults = UserDefaults.standard
    private static let chaveInicio = "analytics.jornada.inicio"
    private static let chaveLegado = "analytics.jornada.legado"
    private static let chavePaywalls = "analytics.jornada.paywallsVistos"
    private static let chaveLivros = "analytics.jornada.livrosConcluidos"

    /// Chamado no `Analytics.start()`, antes de qualquer evento. Na primeira
    /// vez decide se a instalação é nova ou veio de uma versão que não media:
    /// instalação nova ainda não passou pelo onboarding.
    static func iniciar(onboardingConcluido: Bool) {
        guard defaults.object(forKey: chaveInicio) == nil else { return }
        defaults.set(Date.now, forKey: chaveInicio)
        defaults.set(onboardingConcluido, forKey: chaveLegado)
    }

    /// Faixas do `paywall_viewed`. Lê antes de contar esta visualização:
    /// `prior_paywall_views_bucket` "0" quer dizer a primeira.
    static func aoVerPaywall() -> [String: ValorAnalitico] {
        let faixas = propriedades()
        defaults.set(defaults.integer(forKey: chavePaywalls) + 1, forKey: chavePaywalls)
        return faixas
    }

    static func aoConcluirLivro() {
        defaults.set(defaults.integer(forKey: chaveLivros) + 1, forKey: chaveLivros)
    }

    private static func propriedades() -> [String: ValorAnalitico] {
        guard !defaults.bool(forKey: chaveLegado),
              let inicio = defaults.object(forKey: chaveInicio) as? Date else {
            return [
                "install_age_bucket": .texto("unknown"),
                "prior_paywall_views_bucket": .texto("unknown"),
                "books_completed_bucket": .texto("unknown"),
            ]
        }
        return [
            "install_age_bucket": .texto(Faixa.idadeDaInstalacao(Date.now.timeIntervalSince(inicio))),
            "prior_paywall_views_bucket": .texto(Faixa.jornada(defaults.integer(forKey: chavePaywalls))),
            "books_completed_bucket": .texto(Faixa.jornada(defaults.integer(forKey: chaveLivros))),
        ]
    }
}
