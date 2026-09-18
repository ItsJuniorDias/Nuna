//
//  FundoDePapel.swift
//  Nuna
//
//  O fundo do app é o MESMO papel da ilustração, não uma cor parecida.
//
//  Antes o fundo era `#F7F3E9` chapado e a arte trazia um creme um tom
//  diferente, com grão de guache. Com a arte menor que a tela — e em retrato
//  ela é bem menor — dava para ver o retângulo da página: virava imagem colada
//  num fundo, em vez de página de livro.
//
//  O ladrilho sai da própria arte: o pipeline recorta um pedaço da faixa de
//  texto de um spread (Papel puro com grão) e espelha nos dois eixos, então
//  ele repete sem costura (`run.py papel`).
//
//  O ladrilho é desenhado na escala em que a arte aparece na tela (~3 px por
//  ponto). Sem isso o grão do fundo ficaria três vezes maior que o da página e
//  a emenda apareceria de novo, ao contrário.
//

import SwiftUI
import UIKit

struct FundoDePapel: View {
    var body: some View {
        UITokens.surface
            .overlay { Papel.ladrilho }
            .ignoresSafeArea()
    }
}

enum Papel {
    /// Quantos pontos tem cada repetição. 105 pt de um ladrilho de 316 px dá
    /// exatamente os 3 px por ponto em que a arte é desenhada no iPhone.
    private static let ladoEmPontos: CGFloat = 105

    /// O ladrilho já na escala certa. Estático: uma imagem para o app todo.
    static let ladrilho: AnyView = {
        guard let ui = UIImage(named: "papel_fundo"), let cg = ui.cgImage else {
            return AnyView(Color.clear)
        }
        let escala = CGFloat(cg.width) / ladoEmPontos
        let naEscala = UIImage(cgImage: cg, scale: escala, orientation: .up)
        return AnyView(
            Image(uiImage: naEscala)
                .resizable(resizingMode: .tile)
                .ignoresSafeArea()
                .accessibilityHidden(true)
        )
    }()
}

extension View {
    /// Papel com grão atrás desta tela, no lugar da cor chapada.
    func fundoDePapel() -> some View {
        background { FundoDePapel() }
    }
}
