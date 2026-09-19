//
//  NunaApp.swift
//  Nuna
//
//  Created by Alexandre Junior on 16/09/26.
//

import SwiftUI

@main
struct NunaApp: App {
    @Environment(\.scenePhase) private var fase

    /// Roda uma vez por processo. Só abre a fila do analytics: o sistema pode
    /// pré-aquecer o app e rodar este `init` sem ele nunca aparecer, então o
    /// `app_opened` espera a primeira fase ativa.
    init() {
        // Antes de qualquer coisa: o que vier depois pode cair, e o gancho
        // precisa estar armado para contar por quê.
        Diagnostico.instalar()
        // Antes de qualquer vídeo ou voz: a sessão de áudio é fixa em
        // `.playback` e nunca troca (ver `SessaoDeAudio`).
        SessaoDeAudio.configurar()
        Analytics.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // A loja sobe junto com o app, não com o paywall: a escuta de
                // transações precisa estar de pé antes de chegar a aprovação
                // de um responsável, e livro já pago tem que abrir sem ninguém
                // passar pela tela de assinatura.
                .task { await Store.shared.start() }
                // Assinatura que vence com o app em segundo plano não gera
                // transação nova. Voltar ao app confere de novo.
                .onChange(of: fase) { _, nova in
                    guard nova == .active else { return }
                    Task { await Store.shared.atualizarAssinatura(motivo: .foreground) }
                }
        }
        // Na cena, não no conteúdo: aqui `fase` é a do app inteiro, e com duas
        // janelas no iPad a entrada e a saída contam uma vez só.
        .onChange(of: fase, initial: true) { _, nova in
            Diagnostico.rastro("cena: \(nova)")
            switch nova {
            case .active:     Analytics.shared.cenaAtiva()
            case .background: Analytics.shared.foiParaSegundoPlano()
            default:          break
            }
        }
    }
}
