//
//  Catalog.swift
//  Nuna
//
//  Livros do catálogo, com JSON completo (spreads e capa) ou ainda como
//  placeholder.
//
//  A UI precisa saber quais livros existem antes das histórias ficarem prontas:
//  sem isso a Biblioteca fica vazia por semanas e a Home não tem o que
//  agrupar em seções. Cada placeholder vira um `Book` com spreads=[], e cada
//  vez que um JSON de história aparece em `Resources/`, ele SUBSTITUI o
//  placeholder pelo livro completo.
//

import Foundation

struct CatalogEntry: Codable, Sendable {
    let id: String
    let order: Int
    let title: LocalizedText
    let theme: String
    /// Elenco do livro (`["nuna", "theo"]`). Vem do catálogo porque o livro
    /// sem arte não tem spread, e é no spread que mora o elenco. Sem ele, os
    /// "Em breve" não teriam como entrar na mistura.
    var characters: [String]? = nil
    /// Este livro tem as páginas em movimento (pacote `motion-spreads-<slug>`).
    ///
    /// Quem escreve é o pipeline, na hora de exportar os clipes: assim a
    /// marca não pode discordar do que está no `Assets.xcassets`. Nada no app
    /// consegue descobrir isso sozinho — tag de ODR que não existe só se
    /// revela quando o download falha, e aí já é tarde para montar a seção.
    var motion: Bool? = nil
}

enum Catalog {
    /// A última carga não achou o catalog.json e caiu só nos livros do
    /// bundle. Lido pelo analytics (`catalog_loaded`); o catálogo não sabe
    /// de analytics.
    static private(set) var usouReserva = false

    /// Ids com páginas em movimento, como o catálogo declarou na última carga.
    /// Estático pelo mesmo motivo do `usouReserva`: é um fato do catálogo, e
    /// carregá-lo de novo em cada tela que precisa dele seria pior.
    static private(set) var animados: Set<String> = []

    /// `primeiros`: livros que abrem a lista antes da mistura (o grátis).
    /// `semente`: gira a ordem; por padrão, a da semana corrente.
    static func loadAll(bundle: Bundle = .main, primeiros: Set<String> = [],
                        semente: UInt64 = sementeDaSemana()) -> [Book] {
        usouReserva = false
        animados = []
        let livros = BookLoader.loadAll(bundle: bundle)
        let porId = Dictionary(uniqueKeysWithValues: livros.map { ($0.id, $0) })

        guard let url = bundle.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let cat = try? JSONDecoder().decode(Catalogo.self, from: data)
        else {
            usouReserva = true
            return misturar(livros, primeiros: primeiros, semente: semente)
        }

        // ordem do catálogo, com JSON completo onde existir
        let emOrdem = cat.books.map { entry in
            porId[entry.id] ?? placeholder(from: entry)
        }
        animados = Set(cat.books.filter { $0.motion == true }.map(\.id))
        let comAmigos = Set(cat.books
            .filter { ($0.characters ?? []).contains { $0 != "nuna" } }
            .map(\.id))
        return misturar(emOrdem, primeiros: primeiros, comAmigos: comAmigos,
                        semente: semente)
    }

    // MARK: Mistura
    //
    // As capas só da Nuna são parecidas: a mesma menina, no mesmo
    // enquadramento. Na ordem do catálogo elas vinham em fila, e a prateleira
    // parecia uma capa repetida. A ordem final é:
    //   1. os `primeiros` (o livro grátis, o primeiro que quem não assina abre);
    //   2. os livros prontos, com os de amigos espalhados entre os só da Nuna;
    //   3. os "Em breve", misturados do mesmo jeito.
    // Dentro de cada grupo a ordem é embaralhada pela semente da SEMANA: a
    // prateleira muda de cara toda segunda-feira e fica parada nos sete dias
    // seguintes — tempo de sobra para a criança achar o livro onde deixou. A
    // ordem nova só entra no próximo lançamento do app: virar a lista com o
    // app aberto tiraria o livro do lugar embaixo do dedo dela.

    /// A mesma semana ISO da `Featured`: as duas coisas viram no mesmo dia.
    static func sementeDaSemana(on date: Date = .now) -> UInt64 {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let semana = cal.component(.weekOfYear, from: date)
        let ano = cal.component(.yearForWeekOfYear, from: date)
        return UInt64(abs(ano &* 53 &+ semana))
    }

    /// `comAmigos`: ids que o catálogo marca como livro com amigo. Serve para
    /// os "Em breve", que ainda não têm spread de onde tirar o elenco.
    static func misturar(_ livros: [Book], primeiros: Set<String> = [],
                         comAmigos: Set<String> = [],
                         semente: UInt64 = sementeDaSemana()) -> [Book] {
        let fixos = livros.filter { primeiros.contains($0.id) }
        let resto = livros.filter { !primeiros.contains($0.id) }
        func temAmigo(_ livro: Book) -> Bool {
            livro.temAmigos || comAmigos.contains(livro.id)
        }
        func misturado(_ grupo: [Book]) -> [Book] {
            intercalar(embaralhar(grupo.filter { !temAmigo($0) }, semente),
                       embaralhar(grupo.filter(temAmigo), semente))
        }
        return fixos
            + misturado(resto.filter(\.isAvailable))
            + misturado(resto.filter { !$0.isAvailable })
    }

    /// Ordem pseudoaleatória, pelo FNV-1a da semente com o slug: sorteada de
    /// verdade, mas igual em todo aparelho na mesma semana. O `hashValue` do
    /// Swift muda a cada lançamento e não serve aqui.
    private static func embaralhar(_ livros: [Book], _ semente: UInt64) -> [Book] {
        livros.sorted { chave($0.id, semente) < chave($1.id, semente) }
    }

    private static func chave(_ slug: String, _ semente: UInt64) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "nuna:\(semente):\(slug)".utf8 {
            h ^= UInt64(byte)
            h &*= 0x0000_0100_0000_01b3
        }
        return h
    }

    /// Espalha `b` por igual dentro de `a`: cada item entra na posição
    /// proporcional à dele no próprio grupo. 25 e 4 dão um livro com amigo a
    /// cada seis ou sete; 25 e 25 alternam um a um.
    private static func intercalar(_ a: [Book], _ b: [Book]) -> [Book] {
        var saida: [Book] = []
        saida.reserveCapacity(a.count + b.count)
        var i = 0, j = 0
        while i < a.count || j < b.count {
            let vezDeA = i < a.count ? (Double(i) + 0.5) / Double(a.count) : .infinity
            let vezDeB = j < b.count ? (Double(j) + 0.5) / Double(b.count) : .infinity
            if vezDeB < vezDeA {
                saida.append(b[j]); j += 1
            } else {
                saida.append(a[i]); i += 1
            }
        }
        return saida
    }

    /// Livro "vazio", sem spreads, só com identidade. `available` fica false.
    private static func placeholder(from e: CatalogEntry) -> Book {
        Book(id: e.id, version: 0, title: e.title, spreads: [])
    }

    private struct Catalogo: Codable {
        let version: Int
        let books: [CatalogEntry]
    }
}

extension Book {
    /// Um livro só é jogável quando tem spreads dentro.
    var isAvailable: Bool { !spreads.isEmpty }

    /// As páginas deste livro se mexem. Vem do catálogo (`Catalog.animados`),
    /// que o pipeline escreve ao exportar os clipes dos spreads.
    var animado: Bool { Catalog.animados.contains(id) }
}
