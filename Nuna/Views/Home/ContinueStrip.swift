//
//  ContinueStrip.swift
//  Nuna
//
//  Faixa de retomada. Só aparece quando há progresso salvo — sem isso seria
//  um botão "Continuar" que sempre volta pra página 1.
//
//  O cartão é superfície levantada, não vidro: sobre o Papel liso da Home o
//  vidro escurecia a faixa e ela pesava mais que a capa ao lado. Mesma receita
//  dos cartões do paywall e da área dos pais — Papel um tom acima com um fio
//  de Tinta na borda. O vidro fica só no botão redondo de play, que é o que a
//  criança aperta.
//

import SwiftUI

struct ContinueStrip: View {
    let book: Book
    var onOpen: () -> Void

    private let forma = RoundedRectangle(cornerRadius: 22, style: .continuous)

    private var pagina: Int { ReadingProgress.shared.spread(for: book.id) + 1 }
    private var fracao: Double {
        guard book.spreads.count > 1 else { return 0 }
        return Double(pagina - 1) / Double(book.spreads.count - 1)
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Space.sm) {
                miniatura

                VStack(alignment: .leading, spacing: 3) {
                    Text(book.title.resolved())
                        .font(TypeScale.ui.weight(.medium))
                        .foregroundStyle(UITokens.ink)
                        .lineLimit(1)

                    Text("Page \(pagina) of \(book.spreads.count)")
                        .font(TypeScale.legenda)
                        .foregroundStyle(UITokens.inkSecondary)
                        .monospacedDigit()

                    ProgressView(value: fracao)
                        .tint(UITokens.accent)
                        .frame(maxWidth: 160)
                }

                Spacer(minLength: 0)

                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(UITokens.accent)
                    .frame(width: 34, height: 34)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .padding(Space.sm)
            .background(UITokens.surfaceRaised, in: forma)
            .overlay { forma.strokeBorder(UITokens.ink.opacity(0.08)) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Continue \(book.title.resolved()), page \(pagina)")
    }

    private var miniatura: some View {
        Group {
            if UIImage(named: book.coverImageName) != nil {
                Image(book.coverImageName).resizable().aspectRatio(contentMode: .fill)
            } else {
                Palette.azulFumaca
            }
        }
        .frame(width: 44, height: 62)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
