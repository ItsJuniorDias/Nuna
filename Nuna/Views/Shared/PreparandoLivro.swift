//
//  PreparandoLivro.swift
//  Nuna
//
//  A espera de quando a arte do livro ainda não está no aparelho.
//
//  A arte vem por On-Demand Resources, então a primeira abertura de cada livro
//  baixa ~5 MB. São uns dois segundos em Wi-Fi, mas dois segundos em branco,
//  para uma criança de três anos, são um app quebrado.
//
//  Por isso a espera é a CAPA: a mesma que ela acabou de tocar, no meio da
//  tela, com uma barra fina embaixo. Nada de roda cinza de sistema.
//

import SwiftUI

struct PreparandoLivro: View {
    let book: Book
    let estado: Pacotes.Estado

    private var fracao: Double {
        if case .baixando(let f) = estado { return f }
        return 0
    }

    var body: some View {
        ZStack {
            UITokens.surface.ignoresSafeArea()

            VStack(spacing: Space.lg) {
                BookCover(book: book, estilo: .destaque, proporcao: 2.0 / 3.0)
                    .frame(maxWidth: 260)

                VStack(spacing: Space.sm) {
                    Text("Getting the book ready…")
                        .font(TypeScale.ui)
                        .foregroundStyle(UITokens.inkSecondary)

                    // Determinada quando o iOS informa progresso; nos
                    // primeiros instantes ele ainda não sabe, e aí a barra
                    // corre sozinha em vez de fingir um número.
                    Group {
                        if fracao > 0 {
                            ProgressView(value: fracao)
                        } else {
                            ProgressView()
                        }
                    }
                    .tint(UITokens.accent)
                    .frame(maxWidth: 200)
                }
            }
            .padding(Space.xl)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Getting \(book.title.resolved()) ready")
    }
}
