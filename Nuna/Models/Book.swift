//
//  Book.swift
//  Nuna
//

import Foundation

/// Texto localizado por idioma. O app lê só a chave "en".
typealias LocalizedText = [String: String]

/// Idioma do app: inglês dos EUA, fixo.
///
/// O texto dos livros e o da interface precisam sair no MESMO idioma, e a
/// interface é escrita só em inglês. Por isso o idioma não segue o aparelho:
/// um iPhone em português continua vendo capa E menu em inglês. Os JSONs
/// ainda trazem "pt-BR" e "es-MX", mas nada no app lê essas chaves.
enum AppLanguage {
    static let atual = "en"

    /// Números, datas e ordenação no formato dos EUA, qualquer que seja a
    /// região do aparelho. Os preços NÃO passam por aqui: vêm formatados da
    /// App Store, na moeda da conta de quem compra.
    static let locale = Locale(identifier: "en_US")
}

extension LocalizedText {
    func resolved() -> String {
        self[AppLanguage.atual] ?? first?.value ?? ""
    }
}

struct Book: Codable, Identifiable, Sendable {
    let id: String
    let version: Int
    let title: LocalizedText
    let spreads: [Spread]

    private enum CodingKeys: String, CodingKey {
        case id, version, title, spreads
    }

    /// Init memberwise que injeta o `bookId` em cada spread.
    ///
    /// O slug do livro entra no nome do asset (`spread_<slug>_NN`) para que
    /// dois livros com o mesmo número de spread não colidam no
    /// Assets.xcassets. Como o `Spread` é decodificado sem saber qual livro é
    /// o pai, é aqui, na hora de montar o `Book`, que essa costura acontece —
    /// depois do decode e antes do valor chegar ao resto do app.
    init(id: String, version: Int, title: LocalizedText, spreads: [Spread]) {
        self.id = id
        self.version = version
        self.title = title
        self.spreads = spreads.map { s in
            var mut = s
            mut.bookId = id
            return mut
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        let version = try c.decode(Int.self, forKey: .version)
        let title = try c.decode(LocalizedText.self, forKey: .title)
        let spreads = try c.decode([Spread].self, forKey: .spreads)
        self.init(id: id, version: version, title: title, spreads: spreads)
    }
}

struct Spread: Codable, Identifiable, Sendable {
    /// Número do spread, começando em 1.
    let n: Int
    let left: LocalizedText
    let right: LocalizedText
    /// Descrição de cena em inglês, usada pelo pipeline de geração.
    let scene: String
    /// Chaves de cor da paleta. No máximo quatro, fora papel e tinta.
    let colors: [String]
    /// Quantas faixas horizontais a cena tem. Entre 3 e 5.
    let bands: Int
    /// Quem aparece no spread (`["nuna", "theo"]`). Livro só da Nuna não
    /// traz o campo.
    var characters: [String]? = nil

    /// Slug do livro pai. Fica fora do JSON — é injetado pelo `Book` depois
    /// do decode. Enquanto vazio, os nomes de asset caem no formato antigo
    /// `spread_NN`, o que só é útil pra `#Preview` e pra decode isolado.
    var bookId: String = ""

    /// O JSON não carrega `bookId`; ele é injetado depois do decode.
    private enum CodingKeys: String, CodingKey {
        case n, left, right, scene, colors, bands, characters
    }

    var id: Int { n }

    /// Nome do asset do spread completo. `spread_<slug>_NN`.
    ///
    /// Se `bookId` estiver vazio (uso fora do fluxo de `Book`), cai no
    /// formato antigo `spread_NN` — bom pra teste, ruim pra produção.
    var imageName: String {
        let numero = String(format: "%02d", n)
        return bookId.isEmpty ? "spread_\(numero)" : "spread_\(bookId)_\(numero)"
    }

    /// Página esquerda e direita como assets separados, para a pose fechada.
    var leftImageName: String  { imageName + "_l" }
    var rightImageName: String { imageName + "_r" }
}

extension Book {
    /// Asset da capa: `cover_o-quintal-da-nuna`.
    var coverImageName: String { "cover_\(id)" }

    /// Elenco do livro em nomes de gente, sem repetir: `["Nuna", "Theo"]`.
    /// A Nuna vem primeiro; os amigos, na ordem em que entram na história.
    var elenco: [String] {
        var vistos: [String] = []
        for spread in spreads {
            for nome in spread.characters ?? [] where !vistos.contains(nome) {
                vistos.append(nome)
            }
        }
        if let onde = vistos.firstIndex(of: "nuna"), onde != 0 {
            vistos.remove(at: onde)
            vistos.insert("nuna", at: 0)
        }
        return vistos.map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }

    /// Livro com pelo menos um amigo da Nuna. A capa desses é bem diferente
    /// das capas só da Nuna, e a ordem do catálogo usa isso para misturar.
    var temAmigos: Bool {
        spreads.contains { ($0.characters ?? []).contains { $0 != "nuna" } }
    }
}
