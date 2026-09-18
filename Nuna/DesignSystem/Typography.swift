//
//  Typography.swift
//  Nuna
//
//  Duas famílias, ambas do sistema — sem licença, sem download, sem peso no
//  bundle. New York para leitura, SF Rounded para a interface.
//
//  Regra dura: nada abaixo de 24pt em texto que a criança acompanha.
//

import SwiftUI

enum TypeScale {

    /// Menor corpo aceito em texto de leitura infantil.
    static let minimoLeitura: CGFloat = 24

    static let historiaSize: CGFloat = 32
    static let tituloSize:   CGFloat = 34
    static let uiSize:       CGFloat = 17
    static let legendaSize:  CGFloat = 15
    static let tituloCartaoSize: CGFloat = 17

    /// Entrelinha 1,5 — leitor iniciante perde a linha com menos que isso.
    static let entrelinha: CGFloat = 1.5

    static let titulo   = Font.system(size: tituloSize,   weight: .medium,  design: .serif)
    static let ui       = Font.system(size: uiSize,       weight: .regular, design: .rounded)
    static let legenda  = Font.system(size: legendaSize,  weight: .regular, design: .rounded)
    /// Título dentro da capa nas prateleiras e na grade — cabe em 132pt.
    static let tituloCartao = Font.system(size: tituloCartaoSize, weight: .semibold, design: .serif)

    /// Espaço EXTRA entre linhas, já que SwiftUI soma ao leading padrão.
    static func lineSpacing(for size: CGFloat) -> CGFloat {
        max(0, size * entrelinha - size * 1.2)
    }

    /// Altura de DUAS linhas de história neste corpo: duas linhas do leading
    /// padrão (~1,2) mais o espaço extra que leva a entrelinha a 1,5.
    static func alturaDuasLinhas(_ size: CGFloat) -> CGFloat {
        size * 1.2 * 2 + lineSpacing(for: size)
    }

    /// Corpo do texto da história para uma faixa de texto desta altura: o
    /// maior que deixa as duas linhas permitidas caberem na faixa, entre 24
    /// e 32. Página baixa (iPhone deitado) desce até 24; página alta (Duo
    /// aberto, iPad) fica em 32.
    ///
    /// Depende só da ALTURA da faixa — as duas páginas de um spread têm a
    /// mesma, então saem sempre no mesmo corpo, mesmo quando uma frase quebra
    /// linha e a outra não.
    static func corpoHistoria(paraFaixa altura: CGFloat) -> CGFloat {
        let cabe = (altura * 0.92 / alturaDuasLinhas(1)).rounded(.down)
        return min(historiaSize, max(minimoLeitura, cabe))
    }
}
