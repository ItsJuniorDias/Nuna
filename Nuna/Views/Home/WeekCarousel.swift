//
//  WeekCarousel.swift
//  Nuna
//
//  As três histórias da semana num carrossel. Abre sempre na primeira, com um
//  pedaço da próxima aparecendo na borda: a capa cortada já diz "tem mais
//  para lá", sem seta nem bolinhas.
//
//  Cada cartão ocupa a largura do carrossel menos as margens
//  (`containerRelativeFrame` desconta o `contentMargins`), e o arrasto para
//  num cartão por vez, encostado na margem da esquerda — a mesma do título
//  da seção e das prateleiras de baixo. A margem da direita é maior: é a
//  faixa onde a próxima aparece.
//
//  Antes as margens eram iguais e o cartão parava no centro, 24pt para
//  dentro do título. No Duo aberto na horizontal, preso numa metade, o
//  cartão ficava recuado dos dois lados e a vizinha nem aparecia.
//
//  "Sempre na primeira" vale para cada vez que a Home é montada. Ao voltar do
//  leitor, o carrossel continua no cartão que a criança abriu: voltar para o
//  começo com o livro aberto faria o zoom de volta mirar outra capa.
//

import SwiftUI

struct WeekCarousel: View {
    let books: [Book]
    /// Margem da seção, à esquerda do cartão. Dentro de uma metade do Duo é
    /// zero: quem dá a margem é a metade.
    var margem: CGFloat
    var onOpen: (Book, OrigemDaLeitura) -> Void

    @State private var foco: String?
    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento

    /// Faixa à direita do cartão onde a vizinha aparece. Igual com ou sem
    /// margem: numa metade do Duo o carrossel é cortado na borda dela, e
    /// menos que isto a vizinha encolhida some.
    private static let espiada: CGFloat = Space.xxl
    private static let espaco: CGFloat = Space.sm

    init(books: [Book], margem: CGFloat = Space.lg,
         onOpen: @escaping (Book, OrigemDaLeitura) -> Void) {
        self.books = books
        self.margem = margem
        self.onOpen = onOpen
        _foco = State(initialValue: books.first?.id)
    }

    var body: some View {
        // Fora do fechamento da transição, que não enxerga o ambiente.
        let reduzir = reduzirMovimento

        ScrollView(.horizontal) {
            HStack(spacing: Self.espaco) {
                ForEach(Array(books.enumerated()), id: \.element.id) { posicao, livro in
                    let origem = OrigemDaLeitura.semana(posicao: posicao)
                    WeekCard(book: livro, posicao: posicao, total: books.count,
                             emFoco: livro.id == foco) {
                        onOpen(livro, origem)
                    }
                    .origemDoZoom(origem.idDoZoom(livro), raio: 24)
                    .containerRelativeFrame(.horizontal)
                    // As vizinhas encolhem e apagam um pouco; a do centro
                    // fica inteira. Com Reduzir Movimento, só apagam.
                    .scrollTransition(.interactive, axis: .horizontal) { cartao, fase in
                        cartao
                            .scaleEffect(fase.isIdentity || reduzir ? 1 : 0.92)
                            .opacity(fase.isIdentity ? 1 : 0.6)
                    }
                    .id(livro.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        // O centro da tela cai sempre dentro do cartão encostado na margem
        // (a faixa da vizinha é mais estreita que meio cartão), então a
        // âncora no centro continua apontando para ele.
        .scrollPosition(id: $foco, anchor: .center)
        // Sem âncora inicial: o carrossel começa no zero, com a primeira capa
        // alinhada ao título e a segunda espiando na borda.
        .contentMargins(.horizontal,
                        EdgeInsets(top: 0, leading: margem, bottom: 0, trailing: Self.espiada),
                        for: .scrollContent)
        .sensoryFeedback(.selection, trigger: foco)
        // A semana virou com o app aberto: volta para a primeira das novas.
        .onChange(of: books.map(\.id)) { _, ids in
            foco = ids.first
        }
    }
}
