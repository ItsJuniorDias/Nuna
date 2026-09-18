//
//  Miniaturas.swift
//  Nuna
//
//  Capas reduzidas ao tamanho em que aparecem, decodificadas fora da main.
//
//  Cada capa do catálogo é 832×1248 em HEIC, e HEIC é caro de decodificar.
//  Numa prateleira da Home ela aparece com 132 pt de largura — mas o
//  `UIImage(named:)` entregava a imagem inteira, e a decodificação acontecia
//  na main thread no primeiro quadro em que a capa surgia. A Home é uma
//  `LazyVStack`: ao rolar, cada prateleira nova trazia até 19 capas de uma vez,
//  e a rolagem engasgava ali.
//
//  Aqui a capa é desenhada UMA vez, numa thread de fundo, no tamanho em
//  pixels da tela, e guardada. O que chega à main já está pronto para
//  compor: 400×600 em vez de 832×1248 — um quarto da memória, e nenhuma
//  decodificação no meio da rolagem.
//
//  A Home prepara todas as capas no tamanho das prateleiras assim que
//  aparece; quando a criança rola até elas, já estão prontas.
//

import SwiftUI
import UIKit

nonisolated final class Miniaturas: @unchecked Sendable {
    static let shared = Miniaturas()

    /// O sistema esvazia sozinho quando a memória aperta.
    private let cache = NSCache<NSString, UIImage>()

    private init() {}

    /// A largura pedida sobe para a faixa de 100 px de cima: tamanhos
    /// parecidos (a grade da Biblioteca varia um pouco com a tela) dividem a
    /// mesma miniatura em vez de gerar uma para cada.
    static func faixa(_ pixels: CGFloat) -> Int {
        max(100, Int((pixels / 100).rounded(.up)) * 100)
    }

    private func chave(_ nome: String, _ largura: Int) -> NSString {
        "\(nome)@\(largura)" as NSString
    }

    /// Já pronta? Sem esperar nada — é o que o corpo da view pergunta.
    func pronta(_ nome: String, largura: Int) -> UIImage? {
        cache.object(forKey: chave(nome, largura))
    }

    /// Desenha a capa reduzida numa thread de fundo e guarda.
    func preparar(_ nome: String, largura: Int) async -> UIImage? {
        if let feita = pronta(nome, largura: largura) { return feita }
        let chave = chave(nome, largura)
        let cache = cache
        return await Task.detached(priority: .utility) { () -> UIImage? in
            guard let original = UIImage(named: nome), original.size.width > 0 else { return nil }
            let alvo = CGSize(width: CGFloat(largura),
                              height: (CGFloat(largura) * original.size.height
                                       / original.size.width).rounded())
            let formato = UIGraphicsImageRendererFormat()
            formato.scale = 1          // `alvo` já está em pixels
            formato.opaque = true      // capa não tem transparência: composição mais barata
            // Desenhar força a decodificação AQUI, fora da main.
            let reduzida = UIGraphicsImageRenderer(size: alvo, format: formato).image { _ in
                original.draw(in: CGRect(origin: .zero, size: alvo))
            }
            cache.setObject(reduzida, forKey: chave)
            return reduzida
        }.value
    }

    /// Prepara várias, uma de cada vez: cinquenta decodificações em paralelo
    /// disputariam a CPU com a própria rolagem que isto quer proteger.
    func prepararTodas(_ nomes: [String], largura: Int) async {
        for nome in nomes where pronta(nome, largura: largura) == nil {
            guard !Task.isCancelled else { return }
            _ = await preparar(nome, largura: largura)
        }
    }
}
