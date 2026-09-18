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
//  num cartão por vez. Com margens iguais dos dois lados, parar num cartão é
//  parar com ele no centro.
//
//  "Sempre na primeira" vale para cada vez que a Home é montada. Ao voltar do
//  leitor, o carrossel continua no cartão que a criança abriu: voltar para o
//  começo com o livro aberto faria o zoom de volta mirar outra capa.
//

import SwiftUI

struct WeekCarousel: View {
    let books: [Book]
    /// Margem da seção. As vizinhas aparecem por dentro dela, na faixa
    /// `espiada` a mais de cada lado.
    var margem: CGFloat
    var onOpen: (Book, OrigemDaLeitura) -> Void

    @State private var foco: String?
    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento

    /// Quanto do cartão central fica para dentro da margem da Home, e é
    /// onde a vizinha aparece.
    private static let espiada: CGFloat = Space.lg
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
        .scrollPosition(id: $foco, anchor: .center)
        // Sem âncora inicial: o carrossel começa no zero, e com as margens de
        // conteúdo iguais dos dois lados isso deixa a primeira capa no centro
        // da tela, com a segunda espiando na borda.
        .contentMargins(.horizontal, margem + Self.espiada, for: .scrollContent)
        .sensoryFeedback(.selection, trigger: foco)
        // A semana virou com o app aberto: volta para a primeira das novas.
        .onChange(of: books.map(\.id)) { _, ids in
            foco = ids.first
        }
    }
}
