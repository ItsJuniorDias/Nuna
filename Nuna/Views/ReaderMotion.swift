//
//  ReaderMotion.swift
//  Nuna
//
//  Movimento do leitor, num lugar só: tempos, transições da arte e do texto,
//  e a revelação do texto palavra a palavra.
//
//  Quem assiste tem três anos. Tudo aqui é calmo e previsível: a página nova
//  entra inteira pelo lado da virada e empurra a velha para fora, e só
//  depois as palavras aparecem, uma de cada vez, no ritmo de quem lê em voz
//  alta. Nada pisca, nada quica, nada gira em 3D.
//
//  Empurrar, e não fundir: duas ilustrações meio transparentes uma sobre a
//  outra — com a Nuna quase no mesmo lugar em páginas seguidas — viram um
//  fantasma duplo durante a troca. Empurrando, as duas ficam sempre opacas e
//  lado a lado; em página única, `_l` e `_r` são metades da mesma arte e a
//  virada vira uma panorâmica contínua pela cena.
//
//  Reduzir Movimento: sem deslocamento. A arte nova aparece por cima da
//  velha num fade, a revelação por palavra some e o texto entra inteiro.
//

import SwiftUI

// MARK: - Tempos

enum Movimento {
    /// Virada de página. Mola sem quique: a página assenta, não balança.
    static func virada(reduzir: Bool) -> Animation {
        reduzir ? .easeInOut(duration: 0.3) : .smooth(duration: 0.55)
    }

    /// Troca de uma página para duas (girar, abrir ou fechar o Duo).
    static func trocaDeLayout(reduzir: Bool) -> Animation {
        .easeInOut(duration: reduzir ? 0.2 : 0.35)
    }

    /// Toque além da primeira ou da última página: a página "tenta" virar e
    /// volta. Diz "acabou" sem som, sem alerta e sem texto.
    static let empurraoNaBorda: CGFloat = 12

    /// As palavras começam depois que a página terminou de entrar.
    static let atrasoDoTexto: Double = 0.5

    /// Ritmo de quem lê em voz alta para uma criança: uns 0,22s por palavra,
    /// sem arrastar frase curta nem correr com a longa.
    static func duracaoRevelacao(palavras: Int) -> Double {
        min(1.8, max(0.6, Double(palavras) * 0.22))
    }

    /// Depois disto a página já foi revelada: dobrar ou girar o aparelho não
    /// repete a revelação.
    static let tempoParaRevelar: Double = 4.5

    static func contarPalavras(_ frase: String) -> Int {
        frase.split(separator: " ").count
    }
}

// MARK: - Coreografia de uma página

/// O que a página precisa saber para entrar e sair. Vem do `ReaderState`,
/// que é quem sabe o sentido da virada e sobrevive à dobra.
struct MovimentoDaPagina {
    /// Quem sabe o sentido da virada. A transição lê daqui NA HORA em que a
    /// página sai — não do último desenho dela —, senão, ao inverter o
    /// sentido (avançar e depois voltar), a página velha sairia pelo lado
    /// errado.
    var leitor: ReaderState? = nil
    /// Quanto a página anda para entrar ou sair: a largura dela mesma, para
    /// a nova encostar na velha sem vão.
    var distancia: CGFloat = 0
    /// Ordem das camadas: a página da virada mais recente fica por cima.
    var camada: Double = 0
    /// Liga ao abrir o livro e a cada virada; desliga quando a página já foi
    /// lida uma vez.
    var revelarTexto = false
    var reduzirMovimento = false

    func comDistancia(_ nova: CGFloat) -> MovimentoDaPagina {
        var copia = self
        copia.distancia = nova
        return copia
    }

    private var empurrar: AnyTransition {
        AnyTransition(VirarPagina(distancia: distancia, leitor: leitor))
    }

    /// A página nova empurra a velha. Com Reduzir Movimento, a nova aparece
    /// por cima num fade e a velha fica inteira embaixo até ser coberta —
    /// fundindo as duas pela metade, o Papel do fundo apareceria no meio.
    var transicaoArte: AnyTransition {
        reduzirMovimento
            ? .asymmetric(insertion: .opacity, removal: AnyTransition(PermaneceAteCobrir()))
            : empurrar
    }

    /// O texto é da página: sai e entra junto com ela. O novo chega vazio
    /// quando vai ser revelado palavra a palavra. Com Reduzir Movimento, o
    /// velho some rápido e o novo aparece inteiro num fade.
    var transicaoTexto: AnyTransition {
        reduzirMovimento
            ? .asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.3)),
                          removal: .opacity.animation(.easeOut(duration: 0.15)))
            : empurrar
    }
}

// MARK: - Transições

/// Virada de página: avançando, a nova entra pela direita e a velha sai pela
/// esquerda; voltando, o contrário. As duas sempre opacas.
///
/// O sentido é lido do `ReaderState` quando a fase muda, então a página que
/// sai usa o sentido DESTA virada. Com Reduzir Movimento o sistema troca por
/// fade (hasMotion padrão = true), mas o leitor nem usa esta transição aí.
struct VirarPagina: Transition {
    let distancia: CGFloat
    let leitor: ReaderState?

    func body(content: Content, phase: TransitionPhase) -> some View {
        content.offset(x: deslocamento(na: phase))
    }

    private func deslocamento(na fase: TransitionPhase) -> CGFloat {
        let lado: CGFloat = leitor?.sentido == .tras ? -1 : 1
        switch fase {
        case .willAppear:   return distancia * lado
        case .identity:     return 0
        case .didDisappear: return -distancia * lado
        }
    }
}

/// Fica visível até o fim da animação que a removeu. A opacidade vai a
/// 0,999 — imperceptível — só para a remoção durar a animação inteira.
/// Usada com Reduzir Movimento, embaixo da página nova que aparece em fade.
struct PermaneceAteCobrir: Transition {
    static let properties = TransitionProperties(hasMotion: false)

    func body(content: Content, phase: TransitionPhase) -> some View {
        content.opacity(phase.isIdentity ? 1 : 0.999)
    }
}

// MARK: - Palavra a palavra

/// Marca cada palavra com o seu índice, para o renderizador saber quando
/// ela aparece. Também é a base do read-along: a palavra ativa usa o mesmo
/// índice.
nonisolated struct PalavraDaHistoria: TextAttribute {
    let indice: Int
}

/// A frase montada palavra por palavra, cada uma com o seu índice.
struct FrasePorPalavra {
    let texto: Text
    let total: Int

    init(_ frase: String) {
        let palavras = frase.split(separator: " ").map(String.init)
        var montado = Text(verbatim: "")
        for (indice, palavra) in palavras.enumerated() {
            let comEspaco = indice == palavras.count - 1 ? palavra : palavra + " "
            let pedaco = Text(verbatim: comEspaco)
                .customAttribute(PalavraDaHistoria(indice: indice))
            // interpolação em vez de `+`, que está obsoleto desde o iOS 26
            montado = Text("\(montado)\(pedaco)")
        }
        texto = montado
        total = palavras.count
    }
}

/// Desenha as palavras aparecendo em sequência: cada uma sobe 8pt enquanto
/// ganha opacidade, com um pouco de sobreposição entre vizinhas para a frase
/// fluir em vez de "piscar" palavra por palavra.
///
/// `progresso` vai de 0 a 1 e é animável: o SwiftUI chama `draw` a cada
/// quadro. Em 1 desenha a frase normal, sem custo extra.
nonisolated struct RevelacaoPorPalavra: TextRenderer {
    var progresso: Double
    let totalPalavras: Int

    var animatableData: Double {
        get { progresso }
        set { progresso = newValue }
    }

    /// Folga embaixo para a palavra que ainda está subindo não ser cortada.
    var displayPadding: EdgeInsets {
        EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0)
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        guard progresso < 1, totalPalavras > 0 else {
            for linha in layout { ctx.draw(linha) }
            return
        }

        let total = Double(totalPalavras)
        // janela de cada palavra, maior que 1/total: vizinhas se sobrepõem
        let janela = min(1, 1.8 / total)

        for linha in layout {
            for run in linha {
                let indice = Double(run[PalavraDaHistoria.self]?.indice ?? 0)
                // o início da última palavra é 1 - janela: em progresso 1,
                // TODAS terminaram
                let inicio = totalPalavras > 1 ? indice / (total - 1) * (1 - janela) : 0
                let t = min(1, max(0, (progresso - inicio) / janela))
                let suave = t * t * (3 - 2 * t)
                guard suave > 0 else { continue }

                var palavra = ctx
                palavra.opacity = suave
                palavra.translateBy(x: 0, y: (1 - suave) * 8)
                palavra.draw(run)
            }
        }
    }
}
