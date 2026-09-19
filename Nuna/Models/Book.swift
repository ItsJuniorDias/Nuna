//
//  Book.swift
//  Nuna
//

import Foundation
import SwiftUI

/// Texto localizado por idioma.
///
/// A chave é o código do idioma como aparece no JSON de conteúdo:
/// "pt-BR", "en", "es-MX" hoje; "fr", "de", "it", "ar" quando os livros
/// forem traduzidos. Aparelho num idioma que o JSON não tem cai no inglês.
typealias LocalizedText = [String: String]

/// Idioma escolhido para o conteúdo dos livros e para a interface.
///
/// "auto" segue a preferência do iOS; qualquer outro código sobrepõe. A
/// escolha mora no AppStorage e é aplicada na árvore de SwiftUI via
/// `.environment(\.locale, AppLanguage.locale)` no `NunaApp`. Aqui a mesma
/// escolha decide qual chave do `LocalizedText` os JSONs de livro entregam.
enum AppLanguage {
    /// Chave do UserDefaults/AppStorage que guarda a escolha.
    static let chaveEscolha = "idiomaEscolhido"

    /// "auto" ou um código de idioma. Lido direto do UserDefaults para
    /// funcionar fora de uma View (loaders, resolved()).
    static var escolhido: String {
        UserDefaults.standard.string(forKey: chaveEscolha) ?? "auto"
    }

    /// Idioma de fato usado para escolher a chave do JSON de conteúdo.
    static var atual: String {
        let base = escolhido == "auto"
            ? (Locale.preferredLanguages.first ?? "en")
            : escolhido
        switch base.prefix(2) {
        case "pt": return "pt-BR"
        case "es": return "es-MX"
        case "fr": return "fr"
        case "de": return "de"
        case "it": return "it"
        case "ar": return "ar"
        default:   return "en"
        }
    }

    /// Locale que a árvore do SwiftUI usa. Com "auto" segue o sistema; com
    /// idioma escolhido, força esse. O SwiftUI observa isso para achar as
    /// traduções no String Catalog em runtime.
    static var locale: Locale {
        escolhido == "auto" ? .current : Locale(identifier: escolhido)
    }

    /// Sentido de leitura para o `.environment(\.layoutDirection)`. Só o
    /// árabe entra como RTL no app; "auto" segue o idioma preferido do iOS.
    static var direcao: LayoutDirection {
        let base = escolhido == "auto"
            ? (Locale.preferredLanguages.first ?? "en")
            : escolhido
        return base.hasPrefix("ar") ? .rightToLeft : .leftToRight
    }

    /// Os idiomas disponíveis para o menu, na ordem em que aparecem.
    /// "auto" no topo, depois os sete idiomas do catálogo.
    static let opcoes: [String] = [
        "auto", "pt-BR", "en", "es", "fr", "de", "it", "ar",
    ]

    /// Nome do idioma escrito no idioma dele mesmo. "auto" fica em branco
    /// — quem chama monta "Automatic" pelo próprio catálogo.
    static func nomeNativo(_ codigo: String) -> String {
        switch codigo {
        case "pt-BR": return "Português (Brasil)"
        case "en":    return "English"
        case "es":    return "Español"
        case "fr":    return "Français"
        case "de":    return "Deutsch"
        case "it":    return "Italiano"
        case "ar":    return "العربية"
        default:      return ""
        }
    }
}


extension LocalizedText {
    func resolved() -> String {
        self[AppLanguage.atual] ?? self["en"] ?? first?.value ?? ""
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
