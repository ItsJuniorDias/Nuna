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

    /// As histórias da semana, na ordem do carrossel.
    ///
    /// A PRIMEIRA é a que o carrossel mostra sozinha ao abrir, então fica com
    /// um livro com amigo, de capa diferente das duas de trás, que são só da
    /// Nuna. Sem livro com amigo, ou sem dois só da Nuna, valem três seguidos
    /// na ordem do catálogo.
    ///
    /// De uma semana para a outra cada grupo anda o número de livros que usa
    /// (um com amigo, dois só da Nuna), então a semana nova não repete a
    /// anterior enquanto o grupo tiver livro para isso.
    static func storiesOfTheWeek(from books: [Book], on date: Date = .now) -> [Book] {
        // Os animados ficam de fora: a semana é o que o app dá de graça, e as
        // páginas em movimento são justamente o que a assinatura entrega de
        // mais caro. Um livro animado na trinca grátis daria o prêmio sem
        // ninguém pagar por ele.
        //
        // A reserva existe para o dia em que TODOS forem animados: melhor uma
        // semana com livro animado do que um carrossel vazio.
        let prontos = books.filter(\.isAvailable)
        let semMovimento = prontos.filter { !$0.animado }
        let elegiveis = semMovimento.count >= porSemana ? semMovimento : prontos
        guard !elegiveis.isEmpty else { return [] }
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let semana = cal.component(.weekOfYear, from: date)
        let ano = cal.component(.yearForWeekOfYear, from: date)
        let passo = abs(ano &* 53 &+ semana)

        let comAmigos = elegiveis.filter(\.temAmigos)
        let soNuna = elegiveis.filter { !$0.temAmigos }
        if !comAmigos.isEmpty, soNuna.count >= 2 {
            let primeira = comAmigos[passo % comAmigos.count]
            let resto = (passo &* 2) % soNuna.count
            return [primeira, soNuna[resto], soNuna[(resto + 1) % soNuna.count]]
        }

        let quantos = min(porSemana, elegiveis.count)
        let inicio = (passo &* porSemana) % elegiveis.count
        return (0..<quantos).map { elegiveis[(inicio + $0) % elegiveis.count] }
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
