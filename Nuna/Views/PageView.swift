//
//  PageView.swift
//  Nuna
//
//  Uma página. O texto assenta dentro da faixa de Papel que a própria
//  ilustração reserva — sem caixa, sem sombra, sem gradiente. Como o fundo do
//  app é o mesmo Papel, a emenda desaparece.
//

import SwiftUI

struct PageView: View {
    let imageName: String
    let text: String
    let colors: [String]
    let bands: Int
    var movimento = MovimentoDaPagina()
    /// Vídeo da página, quando existe. Numa página só, é o spread inteiro
    /// recortado na metade certa.
    var motion: FonteDeMotion?
    var motionAtivo = false

    var body: some View {
        SafeZoneImage(name: imageName, colors: colors, bands: bands,
                      camada: movimento.camada,
                      transicaoArte: movimento.transicaoArte,
                      transicaoTexto: movimento.transicaoTexto,
                      motion: motion, motionAtivo: motionAtivo) { faixa in
            TextoDaHistoria(texto: text, alturaFaixa: faixa.height,
                            revelar: movimento.revelarTexto)
        }
        .fundoDePapel()
    }
}

/// O texto de uma página, dentro da faixa de 20% que a arte reserva.
///
/// O corpo sai da altura da faixa (`TypeScale.corpoHistoria(paraFaixa:)`), e o
/// texto ocupa sempre uma caixa de DUAS linhas, centrada na faixa e com o
/// texto preso no topo dela. Frase de uma linha começa onde começaria a de
/// duas: lado a lado, as duas páginas de um spread ficam na mesma linha de
/// base, e virar a página não faz o texto pular de altura.
///
/// Com `revelar`, as palavras aparecem uma a uma depois de `atraso`
/// (`RevelacaoPorPalavra`). O progresso é estado DESTA view: nasce em 0 só
/// quando a página chega por uma virada ou pela abertura do livro, e em 1 em
/// qualquer outro caso — dobrar o Duo depois de ler não repete a revelação.
/// O VoiceOver lê a frase inteira desde o primeiro quadro.
struct TextoDaHistoria: View {
    let texto: String
    let alturaFaixa: CGFloat
    let atraso: Double

    @State private var progresso: Double

    init(texto: String, alturaFaixa: CGFloat, revelar: Bool = false,
         atraso: Double = Movimento.atrasoDoTexto) {
        self.texto = texto
        self.alturaFaixa = alturaFaixa
        self.atraso = atraso
        _progresso = State(initialValue: revelar ? 0 : 1)
    }

    var body: some View {
        let corpo = TypeScale.corpoHistoria(paraFaixa: alturaFaixa)
        let frase = FrasePorPalavra(texto)
        frase.texto
            .font(.system(size: corpo, weight: .regular, design: .serif))
            .lineSpacing(TypeScale.lineSpacing(for: corpo))
            .foregroundStyle(UITokens.ink)
            .multilineTextAlignment(.leading)
            .lineLimit(2)
            .textRenderer(RevelacaoPorPalavra(progresso: progresso, totalPalavras: frase.total))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: TypeScale.alturaDuasLinhas(corpo), alignment: .topLeading)
            .frame(maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(texto)
            .accessibilityAddTraits(.isStaticText)
            .onAppear(perform: revelarSeFaltar)
    }

    private func revelarSeFaltar() {
        guard progresso < 1 else { return }
        // linear: o ritmo entre palavras fica constante; cada palavra já tem
        // a sua própria suavização dentro do renderizador
        let duracao = Movimento.duracaoRevelacao(palavras: Movimento.contarPalavras(texto))
        withAnimation(.linear(duration: duracao).delay(atraso)) {
            progresso = 1
        }
    }
}

/// Placeholder que já obedece a composição em faixas e reserva a faixa de texto.
struct BandPlaceholder: View {
    let colors: [String]
    let bands: Int

    private var resolved: [Color] {
        let fromKeys = colors.compactMap(Palette.named)
        return fromKeys.isEmpty ? [Palette.azulFumaca, Palette.terracota] : fromKeys
    }

    private var weights: [CGFloat] {
        switch max(3, min(5, bands)) {
        case 3:  return [0.42, 0.33, 0.25]
        case 4:  return [0.30, 0.26, 0.24, 0.20]
        default: return [0.26, 0.22, 0.20, 0.18, 0.14]
        }
    }

    var body: some View {
        GeometryReader { geo in
            let arte = SafeZone.alturaIlustracao(geo.size.height)
            VStack(spacing: 0) {
                ForEach(Array(weights.enumerated()), id: \.offset) { index, weight in
                    resolved[index % resolved.count]
                        .frame(height: arte * weight)
                }
                Palette.papel
                    .frame(maxHeight: .infinity)
            }
        }
    }
}

#Preview("Page") {
    PageView(
        imageName: "spread_o-quintal-da-nuna_02_l",
        text: "Nuna jumps in the puddle.",
        colors: ["azul_profundo", "oliva", "marrom_fundo"],
        bands: 4
    )
}
