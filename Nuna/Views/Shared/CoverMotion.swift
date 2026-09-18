//
//  CoverMotion.swift
//  Nuna
//
//  A capa em movimento, dentro do `BookCover` do cartão da semana: entra na
//  camada da arte, abaixo do degradê e do título.
//
//  O primeiro quadro do vídeo É a capa — o pipeline gera o motion a partir
//  dela —, então a troca não tem corte: a arte começa e para de respirar.
//
//  Toda a mecânica (laço, fade no fim, mudo, pausa em segundo plano, Reduzir
//  Movimento) mora em `MotionVideo`. Aqui só se decide se há vídeo para este
//  livro e se este cartão é o da frente.
//

import SwiftUI

struct CoverMotion: View {
    let book: Book
    /// Só o cartão que está na frente do carrossel toca.
    var tocando: Bool

    var body: some View {
        MotionArte(fonte: FonteDeMotion(asset: book.coverMotionAsset,
                                        tag: book.motionTag),
                   tocando: tocando)
    }
}
