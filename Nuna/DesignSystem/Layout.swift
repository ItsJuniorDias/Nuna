//
//  Layout.swift
//  Nuna
//
//  Escala de espaçamento, safe zone da ilustração e constantes da dobra.
//  Nada de valor fixo de tela aqui: no Duo o raio e o tamanho mudam entre as
//  poses, então tudo é proporção ou token.
//

import SwiftUI

enum Space {
    static let xxs: CGFloat = 4
    static let xs:  CGFloat = 8
    static let sm:  CGFloat = 12
    static let md:  CGFloat = 16
    static let lg:  CGFloat = 24
    static let xl:  CGFloat = 32
    static let xxl: CGFloat = 48
    static let xxxl: CGFloat = 64
}

enum SafeZone {
    /// Faixa inferior reservada ao texto. Nunca há ilustração aqui.
    static let bandaTexto: CGFloat = 0.20

    /// Faixa central do spread livre de rosto, mão e texto — é onde dobra.
    static let vinco: CGFloat = 0.06

    /// Mínimo de Papel vazio por página.
    static let respiroMinimo: CGFloat = 0.25

    static func alturaIlustracao(_ total: CGFloat) -> CGFloat {
        total * (1 - bandaTexto)
    }

    static func alturaBanda(_ total: CGFloat) -> CGFloat {
        total * bandaTexto
    }

    /// Meia largura da zona livre da dobra, em pontos.
    static func meiaZonaVinco(_ larguraSpread: CGFloat) -> CGFloat {
        larguraSpread * vinco / 2
    }
}

// Canto que acompanha a curva da tela (o raio do Duo muda entre as poses):
// `ConcentricRectangle`, do sistema. Não calcular raio à mão.
