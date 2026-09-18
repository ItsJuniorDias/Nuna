//
//  Palette.swift
//  Nuna
//
//  Sistema de design — livro ilustrado 3–6, versão 1.
//  Treze cores travadas. Papel e Tinta em toda página, no máximo quatro das
//  outras por spread. As duas cores pop ficam abaixo de 8% da área.
//
//  A UI NÃO usa esta paleta. Ver UITokens no fim do arquivo.
//

import SwiftUI

enum Palette {

    // MARK: Base — presentes em toda página
    static let papel = Color(hex: 0xF7F3E9)
    static let tinta = Color(hex: 0x1C1815)

    // MARK: Quentes — chão, luz, estação
    static let terracota  = Color(hex: 0xD9873F)
    static let tijolo     = Color(hex: 0xC03A32)
    static let mostarda   = Color(hex: 0xE8C547)
    static let peleClara  = Color(hex: 0xF2C9A8)
    static let peleMedia  = Color(hex: 0xC68A5E)

    // MARK: Frios — distância, céu, vegetação
    static let azulFumaca    = Color(hex: 0x8794A8)
    static let azulProfundo  = Color(hex: 0x2B5EA8)
    static let oliva         = Color(hex: 0x6B7038)
    static let marromFundo   = Color(hex: 0x4A3320)

    // MARK: Pop — a surpresa, em área pequena
    static let magenta     = Color(hex: 0xC4407A)
    static let rosaPoeira  = Color(hex: 0xE8A0B8)

    /// Teto de cores por spread: papel + tinta + quatro.
    static let maxPorSpread = 6

    /// Resolve a chave usada no JSON das histórias.
    static func named(_ key: String) -> Color? {
        switch key {
        case "papel":         return papel
        case "tinta":         return tinta
        case "terracota":     return terracota
        case "tijolo":        return tijolo
        case "mostarda":      return mostarda
        case "pele_clara":    return peleClara
        case "pele_media":    return peleMedia
        case "azul_fumaca":   return azulFumaca
        case "azul_profundo": return azulProfundo
        case "oliva":         return oliva
        case "marrom_fundo":  return marromFundo
        case "magenta":       return magenta
        case "rosa_poeira":   return rosaPoeira
        default:              return nil
        }
    }

    static let popKeys: Set<String> = ["magenta", "rosa_poeira"]
}

// MARK: - Tokens de interface
//
// A inversão que a maioria erra: se a UI usar as treze cores, ela compete com
// a arte e o livro vira app. A UI é Papel e Tinta, mais um acento único.

enum UITokens {
    static let surface       = Palette.papel
    static let surfaceRaised = Color(hex: 0xFFFCF5)
    static let ink           = Palette.tinta
    static let inkSecondary  = Color(hex: 0x6B5F52)
    /// Texto sobre arte escurecida por degradê de Tinta. Papel, não branco puro.
    static let inkOnArt      = Palette.papel
    /// Acento do app inteiro: o magenta da paleta dos livros. Era o tijolo, e
    /// tijolo é a cor de erro em qualquer interface — num botão de comprar ou
    /// num chip de filtro isso lê como alerta.
    static let accent        = Palette.magenta
    /// Rosa claro, para ÁREA e não para traço: fundo de selo, fundo de chip
    /// ativo, preenchimento de cartão escolhido. Texto sobre ele só em Tinta;
    /// sobre o Papel ele não tem contraste nenhum (1,9:1).
    static let accentSuave   = Palette.rosaPoeira
    static let highlight     = Palette.mostarda
    /// Erro e ação destrutiva. Continua tijolo de propósito: com o acento
    /// rosa, o vermelho volta a significar só uma coisa.
    static let erro          = Palette.tijolo
}

// MARK: - Helper

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red:     Double((hex >> 16) & 0xFF) / 255,
            green:   Double((hex >>  8) & 0xFF) / 255,
            blue:    Double( hex        & 0xFF) / 255,
            opacity: opacity
        )
    }
}
