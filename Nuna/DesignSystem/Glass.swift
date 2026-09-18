//
//  Glass.swift
//  Nuna
//
//  Liquid Glass centralizado num arquivo só, pra trocar em um lugar quando a
//  API mudar. Nada de vidro sobre texto de leitura: a faixa de 20% inferior da
//  página é campo liso de Papel e nunca recebe material translúcido.
//

import SwiftUI

enum Glass {
    /// Pílula de vidro para controles flutuantes (voltar, narração, fechar).
    static func pill<V: View>(_ content: V) -> some View {
        content
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.xs)
            .glassEffect(.regular.interactive(), in: .capsule)
    }

    /// Cartão de vidro sobre ilustração — só em Home e Biblioteca.
    static func card<V: View>(_ content: V, radius: CGFloat = 20) -> some View {
        content
            .glassEffect(.regular, in: .rect(cornerRadius: radius))
    }
}

extension View {
    /// Controle flutuante de vidro.
    func glassPill() -> some View {
        padding(.horizontal, Space.md)
            .padding(.vertical, Space.xs)
            .glassEffect(.regular.interactive(), in: .capsule)
    }

    /// Esconde a tab bar. Usado pelo leitor, que é full-bleed.
    func hidesTabBar() -> some View {
        toolbarVisibility(.hidden, for: .tabBar)
    }
}
