//
//  Featured.swift
//  Nuna
//
//  Escolhas curadas do catálogo: histórias da semana e coleções por tema.
//
//  Nada é aleatório entre sessões. Sorteio a cada abertura faria as
//  "histórias da semana" mudarem quando a criança fecha e abre, e destrói a
//  promessa do rótulo. A mesma semana devolve sempre os mesmos livros.
//

import Foundation

enum Featured {

    // MARK: Histórias da semana

    /// Quantas histórias a semana abre. Todas ficam grátis.
    static let porSemana = 3

    /// As histórias da semana, na ordem do carrossel: um livro ANIMADO, um
    /// clássico com amigo e um clássico só da Nuna.
    ///
    /// O animado abre o carrossel — é o cartão que aparece sozinho — e é a
    /// amostra grátis do que a assinatura entrega: a criança lê um livro
    /// inteiro com as páginas se mexendo. Os outros 14 continuam sendo o
    /// motivo de assinar. Antes os animados ficavam de fora da semana, e quem
    /// não assina nunca via o recurso.
    ///
    /// Os dois clássicos mantêm o que a regra já cuidava: capas diferentes
    /// lado a lado (a de amigo é bem diferente das só da Nuna).
    ///
    /// Cada grupo anda um livro por semana, então nenhum se repete de uma
    /// semana para a seguinte enquanto o grupo tiver mais de um.
    ///
    /// O livro grátis de sempre (`Store.livrosGratis`) fica fora: a semana
    /// existe para abrir três livros que estariam trancados, e sorteá-lo
    /// desperdiçava uma das três vagas.
    static func storiesOfTheWeek(from books: [Book], on date: Date = .now) -> [Book] {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let semana = cal.component(.weekOfYear, from: date)
        let ano = cal.component(.yearForWeekOfYear, from: date)
        let passo = abs(ano &* 53 &+ semana)

        // Memória da última conta. Cada capa pergunta "estou trancado?", e a
        // resposta passa por aqui: sem isto, a trinca inteira (filtros sobre
        // o catálogo, elenco de 12 spreads por livro) era refeita duas vezes
        // por capa, a cada capa que entrava na tela durante a rolagem.
        let ids = books.map(\.id)
        if let m = memoria, m.passo == passo, m.ids == ids, m.animados == Catalog.animados {
            return m.trio
        }
        let trio = sortear(books, passo: passo)
        memoria = (passo, ids, Catalog.animados, trio)
        return trio
    }

    private static var memoria: (passo: Int, ids: [String], animados: Set<String>, trio: [Book])?

    private static func sortear(_ books: [Book], passo: Int) -> [Book] {
        let elegiveis = books.filter { $0.isAvailable && !Store.livrosGratis.contains($0.id) }
        guard !elegiveis.isEmpty else { return [] }

        let animados = elegiveis.filter(\.animado)
        let classicos = elegiveis.filter { !$0.animado }
        func um(_ grupo: [Book]) -> Book? {
            grupo.isEmpty ? nil : grupo[passo % grupo.count]
        }

        var trio = [um(animados),
                    um(classicos.filter(\.temAmigos)),
                    um(classicos.filter { !$0.temAmigos })].compactMap { $0 }

        // Catálogo que não tem um dos grupos: completa com clássicos, depois
        // com animados, na ordem da semana e sem repetir.
        for grupo in [classicos, animados] where trio.count < porSemana {
            let inicio = passo % max(1, grupo.count)
            for i in grupo.indices where trio.count < porSemana {
                let livro = grupo[(inicio + i) % grupo.count]
                if !trio.contains(where: { $0.id == livro.id }) { trio.append(livro) }
            }
        }
        return trio
    }

    static func weekLabel(on date: Date = .now) -> String {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        return "Week \(cal.component(.weekOfYear, from: date))"
    }

    // MARK: Coleções por tema
    //
    // Filtragem por sub-string do slug em vez de metadados: os slugs já são
    // legíveis e refletem o tema. Passar de 25 para 100 livros muda uma linha.

    struct Collection: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        /// Pedaços de slug que entram na coleção.
        var matches: [String] = []
        /// Coleção de elenco, não de tema: todo livro com um amigo da Nuna.
        /// Não dá para pegar esses por slug — cada um tem o tema dele.
        var comAmigos = false
        /// Coleção do que se mexe: os livros que têm clipe em cada página.
        var soAnimadas = false

        func filter(_ books: [Book]) -> [Book] {
            books.filter { book in
                guard book.isAvailable else { return false }
                if soAnimadas { return book.animado }
                if comAmigos { return book.temAmigos }
                return matches.contains { book.id.contains($0) }
            }
        }
    }

    /// A prateleira das páginas que se mexem.
    ///
    /// Fora da lista `collections` de propósito: ela mora logo abaixo do
    /// carrossel da semana, e não no meio das coleções de tema. É a vitrine
    /// do que a assinatura entrega de mais caro — cada livro daqui custou
    /// doze clipes de vídeo para existir.
    ///
    /// Os livros continuam podendo cair na semana grátis: uma criança que
    /// vê a página se mexer é o melhor argumento que esse recurso tem.
    static let animadas = Collection(id: "animadas",
                                     title: "Stories that move",
                                     subtitle: "The pages come alive while you read",
                                     icon: "wand.and.sparkles",
                                     soAnimadas: true)

    /// Quais coleções de tema aparecem na Home, e em que ordem.
    ///
    /// A Home tinha nove prateleiras empilhadas, e a semana grátis e as
    /// histórias animadas se perdiam no meio delas. Ficam seis seções no total
    /// (continuar, semana, animadas, chegaram agora e estas duas); as outras
    /// coleções continuam definidas abaixo e valendo para a análise — só não
    /// ocupam a Home. Todo livro segue na Biblioteca, com os filtros de lá.
    static let naHome = ["fora-de-casa", "amigos"]

    static let collections: [Collection] = [
        Collection(id: "amigos", title: "Nuna and friends",
                   subtitle: "Theo, Lia, Benji and Maya",
                   icon: "person.3",
                   comAmigos: true),
        Collection(id: "fora-de-casa", title: "Adventures outside",
                   subtitle: "Beach, river, mountain, desert",
                   icon: "map",
                   matches: ["praia", "rio", "cidade", "feira", "viagem",
                             "mata", "fazenda", "cachoeira", "montanha",
                             "deserto", "acampamento", "neve", "piscina"]),
        Collection(id: "quintal", title: "In the backyard",
                   subtitle: "The world right outside the door",
                   icon: "leaf",
                   matches: ["quintal", "horta", "jardim", "sombra", "vento",
                             "chuva", "lama", "semente", "ninho", "outono",
                             "corrida", "bolhas", "pedrinhas", "esconde",
                             "asas", "sentidos"]),
        Collection(id: "antes-de-dormir", title: "Before bed",
                   subtitle: "Calm stories for the night",
                   icon: "moon.stars",
                   matches: ["noite", "lua", "silencio", "banho", "frio",
                             "medo", "adeus", "pijama"]),
        Collection(id: "juntos", title: "Things to do together",
                   subtitle: "Music, dancing, dressing up",
                   icon: "person.2",
                   matches: ["cozinha", "festa", "feira", "banho",
                             "parquinho", "piquenique", "banda", "danca",
                             "tesouro", "fantasia", "oficina", "escola",
                             "turma", "manha", "arrumacao"]),
    ]
}
