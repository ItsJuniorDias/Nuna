//
//  SpreadView.swift
//  Nuna
//
//  O spread é a estrutura do livro E a estrutura do aparelho.
//  Esquerda: a criança. Direita: o bicho, na mesma pose.
//
//  Uma página  → Duo fechado em pé, Duo aberto na vertical, Split View
//  Lado a lado → Duo aberto na horizontal (as páginas se encontram NA dobra),
//                iPad e iPhone deitados
//
//  Quem decide é o `ReaderView`, pelo espaço que a tela recebeu. Nada aqui
//  checa orientação nem usa UIScreen: o display interno do Duo ignora
//  orientation lock.
//

import SwiftUI

struct SpreadView: View {
    let spread: Spread
    /// Em compact, qual das duas páginas está visível.
    @Binding var side: Side
    /// As duas páginas juntas, com o meio do spread sobre a dobra.
    var ladoALado: Bool
    /// Sentido da virada, camada e revelação do texto (ver `ReaderMotion`).
    var movimento = MovimentoDaPagina()
    /// Este spread está na frente e a virada já assentou: pode animar.
    var motionAtivo = false

    enum Side { case left, right }

    var body: some View {
        Group {
            if ladoALado {
                doublePage
            } else {
                singlePage
            }
        }
        .fundoDePapel()
    }

    // MARK: Aberto — o spread inteiro, com o meio sobre a dobra

    /// A arte do spread é UMA imagem: as páginas esquerda e direita são as
    /// duas metades dela, pixel a pixel. Desenhar a imagem inteira faz as
    /// faixas de chão atravessarem de uma página para a outra, como o DS
    /// pede. Com duas imagens, cada uma centrada na sua metade da tela,
    /// sobrava um vão de Papel bem em cima da dobra.
    ///
    /// Centrado na tela INTEIRA, não na área segura: no Duo a dobra é o meio
    /// do display, e uma safe area assimétrica (câmera, botões de um lado só)
    /// tiraria o meio do livro de cima dela. A margem lateral usa a MAIOR das
    /// duas inserções dos dois lados, então nada fica embaixo da câmera.
    private var doublePage: some View {
        GeometryReader { geo in
            let area = Self.areaDoSpread(tela: geo.size,
                                         margens: geo.safeAreaInsets,
                                         proporcao: proporcaoSpread)
            // o spread velho sai inteiro da tela e o novo entra do outro lado,
            // com o mesmo vão entre os dois que há entre spread e borda
            spreadAberto(largura: area.width, altura: area.height,
                         movimento: movimento.comDistancia(geo.size.width))
                .position(x: geo.size.width / 2, y: area.midY)
        }
        .ignoresSafeArea()
    }

    /// Maior retângulo com a proporção do spread que cabe na tela, centrado
    /// na horizontal no meio do display e na vertical dentro da área segura.
    static func areaDoSpread(tela: CGSize, margens: EdgeInsets, proporcao: CGFloat) -> CGRect {
        let lateral = max(margens.leading, margens.trailing) + Space.md
        let topo = margens.top + Space.xs
        let base = margens.bottom + Space.xs
        let larguraLivre = max(0, tela.width - lateral * 2)
        let alturaLivre = max(0, tela.height - topo - base)

        let largura = min(larguraLivre, alturaLivre * proporcao).rounded(.down)
        let altura = (largura / proporcao).rounded(.down)
        return CGRect(x: (tela.width - largura) / 2,
                      y: topo + (alturaLivre - altura) / 2,
                      width: largura, height: altura)
    }

    /// Largura ÷ altura da arte do spread (3:2 nos livros de hoje).
    private var proporcaoSpread: CGFloat {
        guard let imagem = UIImage(named: spread.imageName), imagem.size.height > 0 else {
            return 1.5
        }
        return imagem.size.width / imagem.size.height
    }

    private func spreadAberto(largura: CGFloat, altura: CGFloat,
                              movimento: MovimentoDaPagina) -> some View {
        let faixa = SafeZone.alturaBanda(altura)
        // Regra da dobra: os 6% centrais do spread não têm texto. Cada texto
        // recua metade disso a partir do meio, e nunca menos que a margem de
        // fora — com o aparelho meio fechado, letra na curva não se lê.
        let recuoDobra = max(Space.lg, SafeZone.meiaZonaVinco(largura))

        let esquerda = spread.left.resolved()
        // a frase da direita começa quando a da esquerda está quase no fim:
        // a leitura segue o livro, da criança para o bicho
        let atrasoDireita = Movimento.atrasoDoTexto
            + Movimento.duracaoRevelacao(palavras: Movimento.contarPalavras(esquerda)) * 0.85

        // Arte e textos trocam de identidade com o spread e têm transições
        // próprias; o ZStack continua o mesmo entre viradas.
        return ZStack(alignment: .bottom) {
            arteDoSpread
                .frame(width: largura, height: altura)
                .id(spread.imageName)
                .transition(movimento.transicaoArte)
                .zIndex(movimento.camada)

            HStack(spacing: 0) {
                TextoDaHistoria(texto: esquerda, alturaFaixa: faixa,
                                revelar: movimento.revelarTexto)
                    .padding(.leading, Space.lg)
                    .padding(.trailing, recuoDobra)
                    .frame(width: largura / 2, height: faixa)

                TextoDaHistoria(texto: spread.right.resolved(), alturaFaixa: faixa,
                                revelar: movimento.revelarTexto, atraso: atrasoDireita)
                    .padding(.leading, recuoDobra)
                    .padding(.trailing, Space.lg)
                    .frame(width: largura / 2, height: faixa)
            }
            .id(spread.imageName)
            .transition(movimento.transicaoTexto)
            .zIndex(movimento.camada + 0.5)
        }
        .frame(width: largura, height: altura)
    }

    @ViewBuilder
    private var arteDoSpread: some View {
        if UIImage(named: spread.imageName) != nil {
            // Sem `aspectRatio`: o frame já tem a proporção exata da imagem.
            // O vídeo, quando existe, entra por cima no MESMO frame: o clipe
            // é 16:9 com a arte 3:2 no meio, e o `resizeAspectFill` do
            // `MotionVideo` come as tarjas de Papel das laterais.
            Image(spread.imageName)
                .resizable()
                .accessibilityHidden(true)
                .overlay {
                    MotionArte(fonte: FonteDeMotion(spread), tocando: motionAtivo)
                        .clipped()
                }
        } else {
            HStack(spacing: 0) {
                BandPlaceholder(colors: spread.colors, bands: spread.bands)
                BandPlaceholder(colors: spread.colors, bands: spread.bands)
            }
            .accessibilityHidden(true)
        }
    }

    // MARK: Fechado — uma página, o espelho vira uma virada

    /// A virada de esquerda para direita troca `_l` por `_r`, que são as duas
    /// metades da mesma arte: deslizar no sentido da virada lê como a câmera
    /// andando pelo spread.
    private var singlePage: some View {
        PageView(
            imageName: side == .left ? spread.leftImageName : spread.rightImageName,
            text: side == .left ? spread.left.resolved() : spread.right.resolved(),
            colors: spread.colors,
            bands: spread.bands,
            movimento: movimento,
            // Uma página é metade do spread, e o vídeo é do spread inteiro:
            // o recorte segue o lado que está na tela.
            motion: FonteDeMotion(spread,
                                  recorte: side == .left ? .esquerda : .direita),
            motionAtivo: motionAtivo
        )
        .transition(.opacity)
    }
}
