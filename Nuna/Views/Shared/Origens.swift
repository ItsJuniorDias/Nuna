//
//  Origens.swift
//  Nuna
//
//  De onde veio cada abertura: qual capa abriu o livro, qual toque abriu o
//  paywall. A mesma informação serve a duas coisas — o id do zoom capa →
//  leitor e o analytics —, então mora num tipo só em vez de viajar como
//  texto montado em cada tela.
//
//  O id do zoom não leva título: título muda com a tradução, e o id precisa
//  continuar único quando o mesmo livro está em duas prateleiras ("feira" e
//  "banho" estão em duas coleções — por isso a coleção entra no id). A
//  posição fica de fora: não identifica capa nenhuma.
//

import Foundation

enum OrigemDaLeitura {
    /// Posição no carrossel da semana: 0, 1 (a do meio) ou 2.
    case semana(posicao: Int)
    case continuar
    case chegaramAgora(posicao: Int)
    case colecao(id: String, posicao: Int)
    case todos(posicao: Int)
    case biblioteca(posicao: Int, filtro: LibraryView.Filtro, temBusca: Bool)

    /// Id da capa tocada. A capa passa este texto para `origemDoZoom`, e o
    /// `RootView` usa o mesmo para o zoom do leitor.
    func idDoZoom(_ livro: Book) -> String {
        switch self {
        case .semana:             return "semana-\(livro.id)"
        case .continuar:          return "continuar-\(livro.id)"
        case .chegaramAgora:      return "chegaram-\(livro.id)"
        case .colecao(let id, _): return "colecao-\(id)-\(livro.id)"
        case .todos:              return "todos-\(livro.id)"
        case .biblioteca:         return "biblioteca-\(livro.id)"
        }
    }

    /// Valor de `source` no catálogo de eventos.
    var fonte: String {
        switch self {
        case .semana:        return "week_card"
        case .continuar:     return "continue_strip"
        case .chegaramAgora: return "just_arrived"
        case .colecao:       return "collection"
        case .todos:         return "all_books"
        case .biblioteca:    return "library_grid"
        }
    }

    var idDaColecao: String? {
        if case .colecao(let id, _) = self { return id }
        return nil
    }

    /// Carrossel, prateleiras e grade têm posição; o cartão de continuar é
    /// único na tela.
    var posicao: Int? {
        switch self {
        case .continuar:                   return nil
        case .semana(let posicao),
             .chegaramAgora(let posicao),
             .colecao(_, let posicao),
             .todos(let posicao),
             .biblioteca(let posicao, _, _): return posicao
        }
    }

    var filtroDaBiblioteca: LibraryView.Filtro? {
        if case .biblioteca(_, let filtro, _) = self { return filtro }
        return nil
    }

    var temBusca: Bool? {
        if case .biblioteca(_, _, let temBusca) = self { return temBusca }
        return nil
    }
}

/// Prateleira horizontal da Home.
enum TrilhoDaHome {
    case chegaramAgora
    case colecao(String)

    func origem(posicao: Int) -> OrigemDaLeitura {
        switch self {
        case .chegaramAgora:   return .chegaramAgora(posicao: posicao)
        case .colecao(let id): return .colecao(id: id, posicao: posicao)
        }
    }

    var secao: SecaoDaHome {
        switch self {
        case .chegaramAgora: return .justArrived
        case .colecao:       return .collection
        }
    }

    var idDaColecao: String? {
        if case .colecao(let id) = self { return id }
        return nil
    }
}

/// Livro no leitor, com a capa que o abriu. O id é o do livro: o leitor é
/// um só por vez.
struct LeituraAberta: Identifiable {
    let book: Book
    let origem: OrigemDaLeitura
    var id: String { book.id }
}

enum OrigemDoPaywall {
    case posOnboarding(GatilhoDoOnboarding)
    case cabecalhoDaHome
    case livroBloqueado(bookId: String, origem: OrigemDaLeitura, temProgresso: Bool)
    case pais

    /// Valor de `source` no catálogo de eventos.
    var fonte: String {
        switch self {
        case .posOnboarding:   return "post_onboarding"
        case .cabecalhoDaHome: return "home_header"
        case .livroBloqueado:  return "locked_book"
        case .pais:            return "parents"
        }
    }
}

enum GatilhoDoOnboarding: String {
    case primeiraVez = "first_run"
    case replay
}

/// Como o onboarding terminou. Leva o início junto porque quem registra é o
/// `ContentView`, que não sabe quando a primeira tela apareceu.
enum FimDoOnboarding {
    case concluiu(iniciadoEm: Date)
    case pulou(pagina: Int, iniciadoEm: Date)
}

enum PropositoDoPortao: String {
    case subscribe
    case manageSubscription = "manage_subscription"
}
