//
//  SafeZoneImage.swift
//  Nuna
//
//  Ilustração que já vem com os 20% inferiores como campo liso de #F7F3E9,
//  e o texto vai DENTRO dessa faixa — não abaixo dela.
//
//  Reservar outra faixa por fora somaria 40% de creme vazio e empurraria o
//  texto pra fora da tela. A arte já pagou por esse espaço; o app só ocupa.
//
//  A faixa é calculada sobre o retângulo REAL desenhado pela imagem, não sobre
//  o frame da view: com .fit os dois só coincidem quando as proporções batem.
//

import SwiftUI

/// De onde sai o movimento desta arte: o data asset e a tag do livro que o
/// traz. Quem resolve isso em arquivo é o `MotionStore`.
struct FonteDeMotion: Equatable {
    let asset: String
    let tag: String
    var recorte: MotionVideo.Recorte = .inteiro

    init(asset: String, tag: String, recorte: MotionVideo.Recorte = .inteiro) {
        self.asset = asset
        self.tag = tag
        self.recorte = recorte
    }

    init(_ spread: Spread, recorte: MotionVideo.Recorte = .inteiro) {
        self.init(asset: spread.motionAsset, tag: spread.motionTag,
                  recorte: recorte)
    }
}

struct SafeZoneImage<Overlay: View>: View {
    let name: String
    let colors: [String]
    let bands: Int
    var textPadding: CGFloat
    /// Ordem desta página entre as que estão entrando e saindo (leitor).
    var camada: Double
    /// Arte e texto têm transições próprias e trocam de identidade com o
    /// `name`: a arte pode deslizar e assentar enquanto o texto some e volta
    /// depois. Fora do leitor ficam em `.identity`.
    var transicaoArte: AnyTransition
    var transicaoTexto: AnyTransition
    /// Vídeo desta página, quando o livro tem motion. Desenhado no MESMO
    /// retângulo da imagem e ABAIXO da faixa de texto — o texto continua sendo
    /// do app, com a revelação palavra a palavra de sempre.
    var motion: FonteDeMotion?
    /// Só a página que está na frente toca.
    var motionAtivo: Bool
    /// Recebe o tamanho da faixa de texto: quem escreve nela escolhe o corpo
    /// pela altura real, não por um valor fixo que só serve numa tela.
    var overlay: (CGSize) -> Overlay

    init(name: String, colors: [String], bands: Int, textPadding: CGFloat = Space.lg,
         camada: Double = 0,
         transicaoArte: AnyTransition = .identity,
         transicaoTexto: AnyTransition = .identity,
         motion: FonteDeMotion? = nil,
         motionAtivo: Bool = false,
         @ViewBuilder overlay: @escaping (CGSize) -> Overlay) {
        self.name = name
        self.colors = colors
        self.bands = bands
        self.textPadding = textPadding
        self.camada = camada
        self.transicaoArte = transicaoArte
        self.transicaoTexto = transicaoTexto
        self.motion = motion
        self.motionAtivo = motionAtivo
        self.overlay = overlay
    }

    init(name: String, colors: [String], bands: Int, textPadding: CGFloat = Space.lg,
         @ViewBuilder overlay: @escaping () -> Overlay) {
        self.init(name: name, colors: colors, bands: bands, textPadding: textPadding) { _ in
            overlay()
        }
    }

    private var uiImage: UIImage? { UIImage(named: name) }

    var body: some View {
        GeometryReader { geo in
            let rect = drawnRect(in: geo.size)
            let band = SafeZone.alturaBanda(rect.height)

            ZStack(alignment: .topLeading) {
                illustration
                    .frame(width: geo.size.width, height: geo.size.height)
                    .id(name)
                    .transition(transicaoArte)
                    .zIndex(camada)

                // SEM `.id` e SEM a transição da virada: o vídeo chega
                // depois (o pacote é baixado), e entrar por uma transição de
                // página faria ele nascer deslocado uma tela inteira e ficar
                // lá, porque a animação da virada já acabou. Quem dá entrada
                // a ele é o próprio fade do `MotionVideo`.
                if let motion {
                    MotionArte(fonte: motion, tocando: motionAtivo)
                        .frame(width: rect.width, height: rect.height)
                        // Trava: o vídeo preenche a moldura e o que sobra é
                        // cortado AQUI. Sem isto ele vaza para o Papel e
                        // aparece por baixo do texto.
                        .clipped()
                        .offset(x: rect.minX, y: rect.minY)
                        .zIndex(camada + 0.25)
                }

                overlay(CGSize(width: rect.width, height: band))
                    .padding(.horizontal, textPadding)
                    .frame(width: rect.width, height: band, alignment: .leading)
                    .offset(x: rect.minX, y: rect.maxY - band)
                    .id(name)
                    .transition(transicaoTexto)
                    .zIndex(camada + 0.5)
            }
        }
    }

    /// Retângulo ocupado pela imagem depois do .fit.
    private func drawnRect(in size: CGSize) -> CGRect {
        guard let img = uiImage, img.size.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        let ratio = img.size.width / img.size.height
        let frameRatio = size.width / max(size.height, 1)

        if ratio > frameRatio {
            let h = size.width / ratio
            return CGRect(x: 0, y: (size.height - h) / 2, width: size.width, height: h)
        }
        let w = size.height * ratio
        return CGRect(x: (size.width - w) / 2, y: 0, width: w, height: size.height)
    }

    @ViewBuilder
    private var illustration: some View {
        if uiImage != nil {
            Image(name)
                .resizable()
                .aspectRatio(contentMode: .fit)
                // Sem isto o VoiceOver lê o nome do asset ("spread underscore…").
                // Quem conta a cena é o texto da página.
                .accessibilityHidden(true)
        } else {
            BandPlaceholder(colors: colors, bands: bands)
                .accessibilityHidden(true)
        }
    }
}

extension SafeZoneImage where Overlay == EmptyView {
    init(name: String, colors: [String], bands: Int) {
        self.init(name: name, colors: colors, bands: bands) { EmptyView() }
    }
}
