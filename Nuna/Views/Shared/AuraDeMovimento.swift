//
//  AuraDeMovimento.swift
//  Nuna
//
//  A marca dos livros cujas páginas se mexem.
//
//  Nem todo livro tem motion de página — cada um custa doze clipes de vídeo
//  para existir. Sem um sinal na capa, a criança abre um que se mexe e depois
//  um que não, e o segundo parece quebrado. Com o sinal, o que se mexe vira
//  promessa cumprida em vez de inconsistência.
//
//  São duas peças, e elas andam juntas:
//    - o ANEL, que respira devagar em volta do cartão. É o que se vê de
//      relance, rolando a Home;
//    - o SELO, um ícone pequeno, que diz o que o anel significa para quem
//      parar para olhar.
//
//  Reduzir Movimento desliga a respiração e mantém o anel parado: a
//  informação continua lá, o movimento é que sai. Nada aqui usa vídeo — numa
//  prateleira com oito capas, oito players seria a conta errada.
//

import SwiftUI

extension View {
    /// Anel de movimento em volta deste cartão, quando `ativo`.
    func auraDeMovimento(_ ativo: Bool, raio: CGFloat) -> some View {
        modifier(AuraDeMovimento(ativo: ativo, raio: raio))
    }
}

struct AuraDeMovimento: ViewModifier {
    let ativo: Bool
    let raio: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento
    @State private var respirando = false

    /// Do acento ao mostarda e de volta: as duas cores da paleta que sobrevivem
    /// em cima de qualquer capa, clara ou escura.
    private var tinta: LinearGradient {
        LinearGradient(colors: [UITokens.accent, UITokens.highlight, UITokens.accent],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if ativo {
                    RoundedRectangle(cornerRadius: raio, style: .continuous)
                        .strokeBorder(tinta, lineWidth: 2)
                        .opacity(respirando ? 1 : 0.5)
                        // O brilho é do acento e bem aberto: perto demais
                        // vira contorno duplo em cima da sombra do cartão.
                        .shadow(color: UITokens.accent.opacity(respirando ? 0.35 : 0.12),
                                radius: 8)
                        .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard ativo, !reduzirMovimento else {
                    respirando = true      // parado, mas no brilho cheio
                    return
                }
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    respirando = true
                }
            }
    }
}

/// O selo que acompanha o anel. Mesma cápsula de vidro dos outros selos do
/// cartão (cadeado, contador), do outro lado para não brigar com eles.
struct SeloDeMovimento: View {
    var body: some View {
        Image(systemName: "wand.and.sparkles")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(UITokens.accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .glassEffect(.regular, in: .capsule)
            .padding(Space.xs)
            .accessibilityHidden(true)   // o rótulo do cartão já diz
    }
}
