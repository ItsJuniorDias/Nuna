//
//  WeekCard.swift
//  Nuna
//
//  Uma das histórias da semana, um cartão do `WeekCarousel`. Mais baixo que a
//  capa: 4:3 em compact, 3:2 em regular (em 16:9 o rosto da Nuna sai do
//  quadro em várias capas). A arte, o degradê e o título dentro vêm de
//  `BookCover`, o mesmo das outras capas.
//
//  O selo de vidro fica no canto superior esquerdo. Centrado, ele pousava na
//  cabeça da Nuna depois do recorte; no canto pega céu ou margem.
//
//  O cartão inteiro é o botão — sem CTA separado.
//
//  Sem assinatura, o cadeado entra NO selo, no lugar das faíscas, e não numa
//  terceira pílula: o selo já ocupa ~300 dos 322pt livres num iPhone de
//  402pt, e o título da seção logo acima já leva as faíscas.
//

import SwiftUI

struct WeekCard: View {
    let book: Book
    /// Posição no carrossel e quantos cartões ele tem, para o VoiceOver.
    var posicao: Int? = nil
    var total: Int? = nil
    /// Cartão na frente do carrossel: é o único que anima a capa.
    var emFoco: Bool = false
    var onOpen: () -> Void

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.homeCoberta) private var homeCoberta
    @Namespace private var vidro

    private var bloqueado: Bool { Store.shared.estaBloqueado(book) }

    var body: some View {
        Button(action: onOpen) {
            // O vídeo entra na camada da arte, abaixo do degradê e do
            // título, e começa no mesmo quadro da capa. Sem vídeo, ou com
            // Reduzir Movimento, fica só a capa parada.
            BookCover(book: book, estilo: .destaque,
                      proporcao: hSize == .regular ? 3.0 / 2.0 : 4.0 / 3.0) {
                CoverMotion(book: book, tocando: emFoco && !homeCoberta)
            }
            .overlay(alignment: .topLeading) { selo }
        }
        .buttonStyle(CartaoPressionado())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rotuloAcessivel)
        .accessibilityHint(bloqueado ? "Ask a grown-up to unlock"
                                     : "Opens the book")
        .accessibilityAddTraits(.isButton)
    }

    private var rotuloAcessivel: String {
        var base = "Story of the week: \(book.title.resolved())"
        if let posicao, let total, total > 1 {
            base += ", \(posicao + 1) of \(total)"
        }
        return bloqueado ? "\(base), locked" : base
    }

    private var selo: some View {
        GlassEffectContainer(spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                Label("Story of the week",
                      systemImage: bloqueado ? "lock.fill" : "sparkles")
                    .font(TypeScale.legenda.weight(.semibold))
                    .foregroundStyle(UITokens.ink)
                    .padding(.horizontal, Space.sm)
                    .padding(.vertical, Space.xxs)
                    .glassEffect(.regular, in: .capsule)
                    .glassEffectID("selo", in: vidro)

                Text(Featured.weekLabel())
                    .font(TypeScale.legenda)
                    .foregroundStyle(UITokens.inkSecondary)
                    .monospacedDigit()
                    .padding(.horizontal, Space.sm)
                    .padding(.vertical, Space.xxs)
                    .glassEffect(.regular, in: .capsule)
                    .glassEffectID("semana", in: vidro)
            }
        }
        .padding(Space.md)
    }
}

/// Sem o botão "Ler agora", o toque precisa de resposta no próprio cartão:
/// ele cede um pouco sob o dedo.
private struct CartaoPressionado: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: configuration.isPressed)
    }
}
