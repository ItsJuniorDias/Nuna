//
//  WeekCard.swift
//  Nuna
//
//  Uma das histórias da semana, um cartão do `WeekCarousel`. Mais baixo que a
//  capa: 4:3 em compact, 3:2 em regular (em 16:9 o rosto da Nuna sai do
//  quadro em várias capas). A arte, o degradê e o título dentro vêm de
//  `BookCover`, o mesmo das outras capas.
//
//  Os selos de vidro ficam nos cantos de cima: "Story of the week" no da
//  esquerda, "Moves" no da direita. Centrados, ou lado a lado, eles pousavam
//  na cabeça da Nuna, que fica no meio de quase toda capa; nos cantos pegam
//  céu ou margem.
//
//  O cartão inteiro é o botão — sem CTA separado.
//
//  Sem assinatura, o cadeado entra NO selo, no lugar das faíscas, e não numa
//  terceira pílula. Em cartão estreito (Duo fechado, iPhone pequeno) os dois
//  selos não cabem por extenso: o da semana encurta para "This week" e,
//  sem espaço nem para isso, fica só o ícone. Quebrar em duas linhas nunca.
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
    @Environment(\.homeRolando) private var homeRolando

    private var bloqueado: Bool { Store.shared.estaBloqueado(book) }

    var body: some View {
        Button(action: onOpen) {
            // O vídeo entra na camada da arte, abaixo do degradê e do
            // título, e começa no mesmo quadro da capa. Sem vídeo, ou com
            // Reduzir Movimento, fica só a capa parada.
            BookCover(book: book, estilo: .destaque,
                      proporcao: hSize == .regular ? 3.0 / 2.0 : 4.0 / 3.0) {
                CoverMotion(book: book, tocando: emFoco && !homeCoberta && !homeRolando)
            }
            // O animado da semana leva a mesma marca das prateleiras e da
            // Biblioteca: é a amostra grátis do recurso, e precisa se anunciar.
            .auraDeMovimento(book.animado, raio: BookCover<EmptyView>.Estilo.destaque.raio)
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
        if book.animado { base += ", moving pictures" }
        if let posicao, let total, total > 1 {
            base += ", \(posicao + 1) of \(total)"
        }
        return bloqueado ? "\(base), locked" : base
    }

    /// O primeiro arranjo que cabe na largura do cartão, do mais completo ao
    /// mais curto.
    private var selo: some View {
        ViewThatFits(in: .horizontal) {
            selos(rotulo: "Story of the week")
            selos(rotulo: "This week")
            selos(rotulo: nil)
        }
        .padding(Space.md)
    }

    /// `rotulo` nil: o selo da semana fica só com o ícone.
    private func selos(rotulo: LocalizedStringKey?) -> some View {
        HStack(spacing: 0) {
            pilula(rotulo, icone: bloqueado ? "lock.fill" : "sparkles",
                   cor: UITokens.ink)

            Spacer(minLength: Space.xs)

            // A semana já está no título da seção, logo acima; repetida
            // em cada cartão era só ruído. O lugar fica com o que só este
            // cartão tem: as páginas se mexem.
            if book.animado {
                pilula("Moves", icone: "wand.and.sparkles", cor: UITokens.accent)
            }
        }
    }

    private func pilula(_ titulo: LocalizedStringKey?, icone: String, cor: Color) -> some View {
        Group {
            if let titulo {
                Label(titulo, systemImage: icone)
            } else {
                Image(systemName: icone)
            }
        }
        .font(TypeScale.legenda.weight(.semibold))
        .foregroundStyle(cor)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xxs)
        .glassEffect(.regular, in: .capsule)
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
