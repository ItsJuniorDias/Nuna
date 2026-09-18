//
//  AnalyticsEvent.swift
//  Nuna
//
//  Espelho tipado do catálogo de eventos (events.json, versão 1). Cada caso é
//  um evento; `nome` e `propriedades` traduzem para o formato do catálogo.
//
//  Por que tipado: quem chama não digita nome de evento nem de propriedade,
//  então erro de grafia não compila em vez de virar evento recusado no
//  servidor. E as regras de privacidade moram aqui, num lugar só:
//    - duração entra em segundos e sai em faixa (`Faixa`);
//    - inteiro sai preso ao mínimo e máximo do catálogo;
//    - opcional que não se aplica some do dicionário, nunca vai `null`;
//    - texto é só valor de enum do catálogo ou id de livro. Título, busca,
//      mensagem de erro, pergunta do portão: nada disso tem como entrar.
//
//  Índices de spread entram a partir de 0 (como no `ReaderState`) e saem a
//  partir de 1 (como o contador que a criança vê).
//

import Foundation

// MARK: - Valor

/// Valor de propriedade, gravado como o valor JSON puro.
nonisolated enum ValorAnalitico: Codable, Sendable, Equatable {
    case texto(String)
    case inteiro(Int)
    case booleano(Bool)

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .texto(let v):    try c.encode(v)
        case .inteiro(let v):  try c.encode(v)
        case .booleano(let v): try c.encode(v)
        }
    }

    /// Booleano antes de inteiro: o `JSONDecoder` não converte um no outro,
    /// mas a ordem deixa a leitura da fila à prova disso.
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self) {
            self = .booleano(v)
        } else if let v = try? c.decode(Int.self) {
            self = .inteiro(v)
        } else {
            self = .texto(try c.decode(String.self))
        }
    }
}

// MARK: - Valores do catálogo

enum DirecaoAnalitica: String { case forward, back }

enum MetodoDoOnboarding: String {
    case swipe
    case nextButton = "next_button"
}

enum FonteDoCatalogo: String {
    case manifest
    case bundleFallback = "bundle_fallback"
}

enum FalhaDosProdutos: String {
    case requestError = "request_error"
    case incompleteResponse = "incomplete_response"
}

enum CategoriaDoErro: String {
    case network
    case notAvailableInStorefront = "not_available_in_storefront"
    case purchaseNotAllowed = "purchase_not_allowed"
    case unverified
    case storekitOther = "storekit_other"
    case purchaseErrorOther = "purchase_error_other"
    case unknown
}

enum VarianteDaArte: String { case spread, left, right }

enum GatilhoDaTela: String {
    case initial
    case tabTap = "tab_tap"
}

enum SecaoDaHome: String {
    case continueStrip = "continue_strip"
    case weekCard = "week_card"
    case justArrived = "just_arrived"
    case collection
    case allBooks = "all_books"
    case comingSoon = "coming_soon"
}

enum MotivoDoAcesso: String {
    case premium
    case freeBook = "free_book"
    case storyOfWeek = "story_of_week"
}

enum EstadoDaRetomada: String {
    case start
    case resumed
    case resumedAtEnd = "resumed_at_end"
    case resetInvalid = "reset_invalid"
}

enum EntradaDaVirada: String {
    case tapZone = "tap_zone"
    case button
    case swipe
}

enum LadoDaPagina: String { case left, right, both }

enum GatilhoDoFim: String {
    case pageTurn = "page_turn"
    case layoutChange = "layout_change"
}

enum LayoutDoLeitor: String { case single, spread, unknown }

enum PlanoDaAssinatura: String { case annual, monthly }

enum VarianteDoCTA: String {
    case freeTrial = "free_trial"
    case subscribe
}

enum TelaDoRestaurar: String { case paywall, parents }

enum ResultadoDoRestaurar: String {
    case subscriptionFound = "subscription_found"
    case noSubscriptionFound = "no_subscription_found"
    case cancelled
    case failed
}

enum MotivoDoFechamento: String {
    case dismissed
    case purchaseCompleted = "purchase_completed"
    case restored
    case premiumActivatedElsewhere = "premium_activated_elsewhere"
}

enum EstadoDaAssinatura: String { case premium, free, unknown }

/// Coleções que o catálogo conhece. Coleção nova em `Featured` sem entrada
/// aqui (e no events.json) sai sem `collection_id`, em vez de mandar um
/// valor que o servidor recusaria.
private enum IdDaColecao: String {
    case amigos
    case foraDeCasa = "fora-de-casa"
    case quintal
    case antesDeDormir = "antes-de-dormir"
    case juntos
}

// MARK: - Eventos

enum AnalyticsEvent {
    // App e sessão
    case appOpened(onboardingConcluido: Bool)
    case appForegrounded(foraPor: TimeInterval, sessaoGirou: Bool)
    case appBackgrounded(ativoPor: TimeInterval)

    // Confiabilidade
    case catalogLoaded(fonte: FonteDoCatalogo, livros: Int, disponiveis: Int,
                       capasFaltando: Int, onboardingCarregado: Bool, duracao: TimeInterval)
    case storeProductsLoaded(contexto: Store.ContextoDaBusca, duracao: TimeInterval, trialEligible: Bool)
    case storeProductsLoadFailed(contexto: Store.ContextoDaBusca, falha: FalhaDosProdutos,
                                 planosRecebidos: Int, erro: CategoriaDoErro?)
    case pageArtFallbackShown(bookId: String, indiceDoSpread: Int, variante: VarianteDaArte)

    // Onboarding
    case onboardingStarted(gatilho: GatilhoDoOnboarding, paginas: Int, imagensFaltando: Int)
    case onboardingPageViewed(indice: Int, paginas: Int, direcao: DirecaoAnalitica, metodo: MetodoDoOnboarding)
    case onboardingCompleted(gatilho: GatilhoDoOnboarding, paginas: Int, mostraPaywall: Bool, duracao: TimeInterval)
    case onboardingSkipped(gatilho: GatilhoDoOnboarding, indice: Int, paginas: Int,
                           mostraPaywall: Bool, duracao: TimeInterval)

    // Navegação e Home
    case screenViewed(tela: RootView.AppTab, anterior: RootView.AppTab?, gatilho: GatilhoDaTela)
    case homeSectionViewed(secao: SecaoDaHome, colecao: String?, duasMetades: Bool)

    // Biblioteca
    case librarySearchPerformed(tamanhoDaBusca: Int, resultados: Int,
                                filtro: LibraryView.Filtro, ordem: LibraryView.Ordem)
    case libraryFilterChanged(filtro: LibraryView.Filtro, anterior: LibraryView.Filtro,
                              resultados: Int, ordem: LibraryView.Ordem, temBusca: Bool)
    case librarySortChanged(ordem: LibraryView.Ordem, anterior: LibraryView.Ordem,
                            filtro: LibraryView.Filtro, temBusca: Bool)

    // Leitura
    /// Página do livro aberta (`BookDetailView`), antes de ler ou de assinar.
    case bookDetailViewed(book: Book, origem: OrigemDaLeitura, bloqueado: Bool,
                          temProgresso: Bool)
    case bookOpened(book: Book, origem: OrigemDaLeitura, acesso: MotivoDoAcesso,
                    retomada: EstadoDaRetomada, indiceInicial: Int, deitado: Bool, duasMetades: Bool)
    case pageTurned(bookId: String, direcao: DirecaoAnalitica, entrada: EntradaDaVirada,
                    indiceDoSpread: Int, lado: LadoDaPagina, spreads: Int, permanencia: TimeInterval)
    case bookCompleted(bookId: String, origem: OrigemDaLeitura, acesso: MotivoDoAcesso,
                       gatilho: GatilhoDoFim, leuDoComeco: Bool, paginasVistas: Int,
                       recuos: Int, spreads: Int, duracao: TimeInterval)
    case readerLayoutChanged(bookId: String, deLadoALado: Bool, paraLadoALado: Bool,
                             deitado: Bool, duasMetades: Bool, indiceDoSpread: Int)
    case readerBackgrounded(bookId: String, origem: OrigemDaLeitura, indiceDoSpread: Int,
                            indiceMaisLonge: Int, spreads: Int, paginasVistas: Int,
                            concluido: Bool, duracao: TimeInterval)
    case readerClosed(bookId: String, origem: OrigemDaLeitura, acesso: MotivoDoAcesso,
                      indiceInicial: Int, indiceFinal: Int, indiceMaisLonge: Int, spreads: Int,
                      paginasVistas: Int, avancos: Int, recuos: Int, empurroes: Int,
                      arrastosIgnorados: Int, trocasDeLayout: Int, concluido: Bool,
                      duracao: TimeInterval)

    // Assinatura
    case paywallViewed(origem: OrigemDoPaywall, planosProntos: Bool, trialEligible: Bool)
    case planSelected(plano: PlanoDaAssinatura, trialEligible: Bool, origem: OrigemDoPaywall)
    case subscribeTapped(plano: PlanoDaAssinatura, variante: VarianteDoCTA, origem: OrigemDoPaywall)
    case parentalGateShown(proposito: PropositoDoPortao)
    case parentalGatePassed(proposito: PropositoDoPortao, erros: Int, pausou: Bool, duracao: TimeInterval)
    case parentalGateFailed(proposito: PropositoDoPortao, errosSeguidos: Int, causouPausa: Bool)
    case parentalGateCancelled(proposito: PropositoDoPortao, erros: Int, emPausa: Bool, tinhaResposta: Bool)
    case purchaseCompleted(plano: PlanoDaAssinatura, comTeste: Bool, origem: OrigemDoPaywall)
    case purchasePending(plano: PlanoDaAssinatura, comTeste: Bool, origem: OrigemDoPaywall)
    case purchaseCancelled(plano: PlanoDaAssinatura, comTeste: Bool, origem: OrigemDoPaywall)
    case purchaseFailed(plano: PlanoDaAssinatura, comTeste: Bool, origem: OrigemDoPaywall, erro: CategoriaDoErro)
    case restoreTapped(tela: TelaDoRestaurar, origem: OrigemDoPaywall?)
    case restoreFinished(tela: TelaDoRestaurar, resultado: ResultadoDoRestaurar,
                         erro: CategoriaDoErro?, origem: OrigemDoPaywall?)
    case paywallClosed(origem: OrigemDoPaywall, motivo: MotivoDoFechamento, planosProntos: Bool,
                       plano: PlanoDaAssinatura, pendente: Bool, duracao: TimeInterval)
    case subscriptionStatusChanged(premium: Bool, motivo: Store.MotivoDaConferencia,
                                   plano: PlanoDaAssinatura?, familia: Bool?, emTeste: Bool?)

    // Pais
    case readingProgressReset(livrosEmAndamento: Int)

    // MARK: Nome

    var nome: String {
        switch self {
        case .appOpened:                 return "app_opened"
        case .appForegrounded:           return "app_foregrounded"
        case .appBackgrounded:           return "app_backgrounded"
        case .catalogLoaded:             return "catalog_loaded"
        case .storeProductsLoaded:       return "store_products_loaded"
        case .storeProductsLoadFailed:   return "store_products_load_failed"
        case .pageArtFallbackShown:      return "page_art_fallback_shown"
        case .onboardingStarted:         return "onboarding_started"
        case .onboardingPageViewed:      return "onboarding_page_viewed"
        case .onboardingCompleted:       return "onboarding_completed"
        case .onboardingSkipped:         return "onboarding_skipped"
        case .screenViewed:              return "screen_viewed"
        case .homeSectionViewed:         return "home_section_viewed"
        case .librarySearchPerformed:    return "library_search_performed"
        case .libraryFilterChanged:      return "library_filter_changed"
        case .librarySortChanged:        return "library_sort_changed"
        case .bookDetailViewed:          return "book_detail_viewed"
        case .bookOpened:                return "book_opened"
        case .pageTurned:                return "page_turned"
        case .bookCompleted:             return "book_completed"
        case .readerLayoutChanged:       return "reader_layout_changed"
        case .readerBackgrounded:        return "reader_backgrounded"
        case .readerClosed:              return "reader_closed"
        case .paywallViewed:             return "paywall_viewed"
        case .planSelected:              return "plan_selected"
        case .subscribeTapped:           return "subscribe_tapped"
        case .parentalGateShown:         return "parental_gate_shown"
        case .parentalGatePassed:        return "parental_gate_passed"
        case .parentalGateFailed:        return "parental_gate_failed"
        case .parentalGateCancelled:     return "parental_gate_cancelled"
        case .purchaseCompleted:         return "purchase_completed"
        case .purchasePending:           return "purchase_pending"
        case .purchaseCancelled:         return "purchase_cancelled"
        case .purchaseFailed:            return "purchase_failed"
        case .restoreTapped:             return "restore_tapped"
        case .restoreFinished:           return "restore_finished"
        case .paywallClosed:             return "paywall_closed"
        case .subscriptionStatusChanged: return "subscription_status_changed"
        case .readingProgressReset:      return "reading_progress_reset"
        }
    }

    // MARK: Propriedades

    var propriedades: [String: ValorAnalitico] {
        var p: [String: ValorAnalitico] = [:]

        switch self {
        case .appOpened(let concluido):
            p["onboarding_completed"] = .booleano(concluido)

        case .appForegrounded(let fora, let girou):
            p["background_duration_bucket"] = .texto(Faixa.segundoPlano(fora))
            p["session_rotated"] = .booleano(girou)

        case .appBackgrounded(let ativo):
            p["foreground_duration_bucket"] = .texto(Faixa.primeiroPlano(ativo))

        case .catalogLoaded(let fonte, let livros, let disponiveis, let capas, let onboarding, let duracao):
            p["catalog_source"] = .texto(fonte.rawValue)
            p["books_total"] = Self.inteiro(livros, 0...500)
            p["books_available"] = Self.inteiro(disponiveis, 0...500)
            p["missing_cover_count"] = Self.inteiro(capas, 0...500)
            p["onboarding_content_loaded"] = .booleano(onboarding)
            p["load_duration_bucket"] = .texto(Faixa.cargaDoCatalogo(duracao))

        case .storeProductsLoaded(let contexto, let duracao, let elegivel):
            p["fetch_context"] = .texto(contexto.rawValue)
            p["duration_bucket"] = .texto(Faixa.buscaDeProdutos(duracao))
            p["trial_eligible"] = .booleano(elegivel)

        case .storeProductsLoadFailed(let contexto, let falha, let recebidos, let erro):
            p["fetch_context"] = .texto(contexto.rawValue)
            p["failure_kind"] = .texto(falha.rawValue)
            p["returned_count"] = Self.inteiro(recebidos, 0...2)
            if let erro { p["error_category"] = .texto(erro.rawValue) }

        case .pageArtFallbackShown(let bookId, let indice, let variante):
            p["book_id"] = .texto(bookId)
            p["spread_number"] = Self.spread(indice)
            p["asset_variant"] = .texto(variante.rawValue)

        case .onboardingStarted(let gatilho, let paginas, let faltando):
            p["trigger"] = .texto(gatilho.rawValue)
            p["page_count"] = Self.inteiro(paginas, 1...20)
            p["missing_image_count"] = Self.inteiro(faltando, 0...20)

        case .onboardingPageViewed(let indice, let paginas, let direcao, let metodo):
            p["page_index"] = Self.inteiro(indice, 0...19)
            p["page_count"] = Self.inteiro(paginas, 1...20)
            p["direction"] = .texto(direcao.rawValue)
            p["method"] = .texto(metodo.rawValue)

        case .onboardingCompleted(let gatilho, let paginas, let paywall, let duracao):
            p["trigger"] = .texto(gatilho.rawValue)
            p["page_count"] = Self.inteiro(paginas, 1...20)
            p["will_show_paywall"] = .booleano(paywall)
            p["duration_bucket"] = .texto(Faixa.curta(duracao))

        case .onboardingSkipped(let gatilho, let indice, let paginas, let paywall, let duracao):
            p["trigger"] = .texto(gatilho.rawValue)
            p["skipped_at_page_index"] = Self.inteiro(indice, 0...19)
            p["page_count"] = Self.inteiro(paginas, 1...20)
            p["will_show_paywall"] = .booleano(paywall)
            p["duration_bucket"] = .texto(Faixa.curta(duracao))

        case .screenViewed(let tela, let anterior, let gatilho):
            p["screen"] = .texto(tela.rawValue)
            if let anterior { p["previous_screen"] = .texto(anterior.rawValue) }
            p["trigger"] = .texto(gatilho.rawValue)

        case .homeSectionViewed(let secao, let colecao, let duasMetades):
            p["section"] = .texto(secao.rawValue)
            if let id = colecao.flatMap(IdDaColecao.init(rawValue:)) {
                p["collection_id"] = .texto(id.rawValue)
            }
            p["two_halves"] = .booleano(duasMetades)

        case .librarySearchPerformed(let tamanho, let resultados, let filtro, let ordem):
            p["query_length_bucket"] = .texto(Faixa.tamanhoDaBusca(tamanho))
            p["result_count"] = Self.inteiro(resultados, 0...500)
            p["filter"] = .texto(filtro.analitico)
            p["sort"] = .texto(ordem.analitico)

        case .libraryFilterChanged(let filtro, let anterior, let resultados, let ordem, let temBusca):
            p["filter"] = .texto(filtro.analitico)
            p["previous_filter"] = .texto(anterior.analitico)
            p["result_count"] = Self.inteiro(resultados, 0...500)
            p["sort"] = .texto(ordem.analitico)
            p["has_query"] = .booleano(temBusca)

        case .librarySortChanged(let ordem, let anterior, let filtro, let temBusca):
            p["sort"] = .texto(ordem.analitico)
            p["previous_sort"] = .texto(anterior.analitico)
            p["filter"] = .texto(filtro.analitico)
            p["has_query"] = .booleano(temBusca)

        case .bookDetailViewed(let book, let origem, let bloqueado, let temProgresso):
            p["book_id"] = .texto(book.id)
            p["book_version"] = Self.inteiro(book.version, 0...10000)
            Self.origem(origem, em: &p)
            if let filtro = origem.filtroDaBiblioteca { p["library_filter"] = .texto(filtro.analitico) }
            if let temBusca = origem.temBusca { p["has_query"] = .booleano(temBusca) }
            p["locked"] = .booleano(bloqueado)
            p["has_progress"] = .booleano(temProgresso)
            p["spread_count"] = Self.inteiro(book.spreads.count, 1...200)

        case .bookOpened(let book, let origem, let acesso, let retomada, let inicial, let deitado, let duasMetades):
            p["book_id"] = .texto(book.id)
            p["book_version"] = Self.inteiro(book.version, 0...10000)
            Self.origem(origem, em: &p)
            if let filtro = origem.filtroDaBiblioteca { p["library_filter"] = .texto(filtro.analitico) }
            if let temBusca = origem.temBusca { p["has_query"] = .booleano(temBusca) }
            p["access_reason"] = .texto(acesso.rawValue)
            p["resume_state"] = .texto(retomada.rawValue)
            p["start_spread"] = Self.spread(inicial)
            p["spread_count"] = Self.inteiro(book.spreads.count, 1...200)
            p["orientation"] = Self.orientacao(deitado)
            p["two_halves"] = .booleano(duasMetades)

        case .pageTurned(let bookId, let direcao, let entrada, let indice, let lado, let spreads, let permanencia):
            p["book_id"] = .texto(bookId)
            p["direction"] = .texto(direcao.rawValue)
            p["input"] = .texto(entrada.rawValue)
            p["spread_number"] = Self.spread(indice)
            p["page_side"] = .texto(lado.rawValue)
            p["spread_count"] = Self.inteiro(spreads, 1...200)
            p["dwell_bucket"] = .texto(Faixa.permanencia(permanencia))

        case .bookCompleted(let bookId, let origem, let acesso, let gatilho, let doComeco,
                            let vistas, let recuos, let spreads, let duracao):
            p["book_id"] = .texto(bookId)
            p["source"] = .texto(origem.fonte)
            p["access_reason"] = .texto(acesso.rawValue)
            p["trigger"] = .texto(gatilho.rawValue)
            p["read_from_start"] = .booleano(doComeco)
            p["pages_viewed"] = Self.inteiro(vistas, 0...400)
            p["back_turns"] = Self.contador(recuos)
            p["spread_count"] = Self.inteiro(spreads, 1...200)
            p["duration_bucket"] = .texto(Faixa.leitura(duracao))

        case .readerLayoutChanged(let bookId, let de, let para, let deitado, let duasMetades, let indice):
            p["book_id"] = .texto(bookId)
            p["from_layout"] = Self.layout(de)
            p["to_layout"] = Self.layout(para)
            p["orientation"] = Self.orientacao(deitado)
            p["two_halves"] = .booleano(duasMetades)
            p["spread_number"] = Self.spread(indice)

        case .readerBackgrounded(let bookId, let origem, let indice, let maisLonge, let spreads,
                                 let vistas, let concluido, let duracao):
            p["book_id"] = .texto(bookId)
            p["source"] = .texto(origem.fonte)
            p["spread_number"] = Self.spread(indice)
            p["furthest_spread"] = Self.spread(maisLonge)
            p["spread_count"] = Self.inteiro(spreads, 1...200)
            p["pages_viewed"] = Self.inteiro(vistas, 0...400)
            p["completed"] = .booleano(concluido)
            p["duration_bucket"] = .texto(Faixa.leitura(duracao))

        case .readerClosed(let bookId, let origem, let acesso, let inicial, let fim, let maisLonge,
                           let spreads, let vistas, let avancos, let recuos, let empurroes,
                           let ignorados, let trocas, let concluido, let duracao):
            p["book_id"] = .texto(bookId)
            p["source"] = .texto(origem.fonte)
            p["access_reason"] = .texto(acesso.rawValue)
            p["start_spread"] = Self.spread(inicial)
            p["end_spread"] = Self.spread(fim)
            p["furthest_spread"] = Self.spread(maisLonge)
            p["spread_count"] = Self.inteiro(spreads, 1...200)
            p["pages_viewed"] = Self.inteiro(vistas, 0...400)
            p["forward_turns"] = Self.contador(avancos)
            p["back_turns"] = Self.contador(recuos)
            p["edge_nudges"] = Self.contador(empurroes)
            p["ignored_swipes"] = Self.contador(ignorados)
            p["layout_changes"] = Self.contador(trocas)
            p["completed"] = .booleano(concluido)
            p["duration_bucket"] = .texto(Faixa.leitura(duracao))

        case .paywallViewed(let origem, let prontos, let elegivel):
            Self.paywall(origem, em: &p)
            switch origem {
            case .livroBloqueado(let bookId, let leitura, let temProgresso):
                p["book_id"] = .texto(bookId)
                p["book_source"] = .texto(leitura.fonte)
                p["has_saved_progress"] = .booleano(temProgresso)
            case .posOnboarding(let gatilho):
                p["onboarding_trigger"] = .texto(gatilho.rawValue)
            case .cabecalhoDaHome, .pais:
                break
            }
            p["products_ready"] = .booleano(prontos)
            p["trial_eligible"] = .booleano(elegivel)

        case .planSelected(let plano, let elegivel, let origem):
            p["plan"] = .texto(plano.rawValue)
            p["trial_eligible"] = .booleano(elegivel)
            Self.paywall(origem, em: &p)

        case .subscribeTapped(let plano, let variante, let origem):
            p["plan"] = .texto(plano.rawValue)
            p["cta_variant"] = .texto(variante.rawValue)
            Self.paywall(origem, em: &p)

        case .parentalGateShown(let proposito):
            p["purpose"] = .texto(proposito.rawValue)

        case .parentalGatePassed(let proposito, let erros, let pausou, let duracao):
            p["purpose"] = .texto(proposito.rawValue)
            p["failed_attempts"] = Self.contador(erros)
            p["was_paused"] = .booleano(pausou)
            p["duration_bucket"] = .texto(Faixa.curta(duracao))

        case .parentalGateFailed(let proposito, let seguidos, let causouPausa):
            p["purpose"] = .texto(proposito.rawValue)
            p["consecutive_errors"] = Self.inteiro(seguidos, 1...3)
            p["caused_pause"] = .booleano(causouPausa)

        case .parentalGateCancelled(let proposito, let erros, let emPausa, let tinhaResposta):
            p["purpose"] = .texto(proposito.rawValue)
            p["failed_attempts"] = Self.contador(erros)
            p["while_paused"] = .booleano(emPausa)
            p["had_partial_answer"] = .booleano(tinhaResposta)

        case .purchaseCompleted(let plano, let comTeste, let origem),
             .purchasePending(let plano, let comTeste, let origem),
             .purchaseCancelled(let plano, let comTeste, let origem):
            p["plan"] = .texto(plano.rawValue)
            p["with_trial"] = .booleano(comTeste)
            Self.paywall(origem, em: &p)

        case .purchaseFailed(let plano, let comTeste, let origem, let erro):
            p["plan"] = .texto(plano.rawValue)
            p["with_trial"] = .booleano(comTeste)
            Self.paywall(origem, em: &p)
            p["error_category"] = .texto(erro.rawValue)

        case .restoreTapped(let tela, let origem):
            p["screen"] = .texto(tela.rawValue)
            if let origem { Self.paywall(origem, em: &p) }

        case .restoreFinished(let tela, let resultado, let erro, let origem):
            p["screen"] = .texto(tela.rawValue)
            p["result"] = .texto(resultado.rawValue)
            if let erro { p["error_category"] = .texto(erro.rawValue) }
            if let origem { Self.paywall(origem, em: &p) }

        case .paywallClosed(let origem, let motivo, let prontos, let plano, let pendente, let duracao):
            Self.paywall(origem, em: &p)
            p["reason"] = .texto(motivo.rawValue)
            p["plans_ready"] = .booleano(prontos)
            p["selected_plan"] = .texto(plano.rawValue)
            p["purchase_pending"] = .booleano(pendente)
            p["duration_bucket"] = .texto(Faixa.curta(duracao))

        case .subscriptionStatusChanged(let premium, let motivo, let plano, let familia, let emTeste):
            p["new_state"] = .texto(premium ? "premium" : "free")
            p["trigger"] = .texto(motivo.rawValue)
            if let plano { p["plan"] = .texto(plano.rawValue) }
            if let familia { p["is_family_shared"] = .booleano(familia) }
            if let emTeste { p["in_free_trial"] = .booleano(emTeste) }

        case .readingProgressReset(let emAndamento):
            p["books_in_progress_bucket"] = .texto(Faixa.livrosEmAndamento(emAndamento))
        }

        return p
    }

    // MARK: Auxiliares

    private static func inteiro(_ valor: Int, _ faixa: ClosedRange<Int>) -> ValorAnalitico {
        .inteiro(min(max(valor, faixa.lowerBound), faixa.upperBound))
    }

    /// Contadores de sessão param em 99: acima disso é criança batendo na
    /// tela, e o número exato não diz nada novo.
    private static func contador(_ valor: Int) -> ValorAnalitico {
        inteiro(valor, 0...99)
    }

    /// Índice a partir de 0 vira número a partir de 1.
    private static func spread(_ indice: Int) -> ValorAnalitico {
        inteiro(indice + 1, 1...200)
    }

    private static func orientacao(_ deitado: Bool) -> ValorAnalitico {
        .texto(deitado ? "landscape" : "portrait")
    }

    private static func layout(_ ladoALado: Bool) -> ValorAnalitico {
        .texto(ladoALado ? LayoutDoLeitor.spread.rawValue : LayoutDoLeitor.single.rawValue)
    }

    private static func origem(_ origem: OrigemDaLeitura, em p: inout [String: ValorAnalitico]) {
        p["source"] = .texto(origem.fonte)
        if let id = origem.idDaColecao.flatMap(IdDaColecao.init(rawValue:)) {
            p["collection_id"] = .texto(id.rawValue)
        }
        if let posicao = origem.posicao { p["position"] = inteiro(posicao, 0...499) }
    }

    private static func paywall(_ origem: OrigemDoPaywall, em p: inout [String: ValorAnalitico]) {
        p["source"] = .texto(origem.fonte)
    }
}
