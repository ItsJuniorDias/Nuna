//
//  BookDetailView.swift
//  Nuna
//
//  A página do livro: a capa GRANDE e em movimento, a primeira frase da
//  história, o elenco e um botão.
//
//  Existe por um motivo concreto: os 50 livros têm capa animada e ela só
//  aparecia no carrossel da semana, ou seja, em três. Aqui a arte que a gente
//  pagou para gerar tem onde tocar — grande, no meio da tela, sem degradê de
//  cartão por cima.
//
//  Quem chega aqui: capa tocada numa prateleira da Home ou na grade da
//  Biblioteca. O carrossel da semana e a faixa de continuar NÃO passam por
//  aqui — são superfícies de "ler agora", e pôr uma tela no meio do caminho
//  de uma criança de três anos é tirar a história dela por um toque.
//
//  Livro bloqueado também abre esta tela em vez de ir direto ao paywall: o
//  adulto vê o que está comprando, com a capa respirando, antes de decidir.
//
//  Enquanto ela está aberta, o pacote de arte do livro é antecipado em
//  segundo plano. Se o dedo for para "Read", a história já está no aparelho.
//

import SwiftUI

struct BookDetailView: View {
    let book: Book
    let origem: OrigemDaLeitura
    /// Ler agora. Quem decide o que fazer é o `RootView`: livro bloqueado vai
    /// para o paywall, livro liberado espera o pacote e abre o leitor.
    var onRead: () -> Void
    var onClose: () -> Void

    @Environment(\.horizontalSizeClass) private var hSize
    @State private var tamanho: CGSize = .zero
    @State private var registrou = false

    private var store: Store { Store.shared }
    private var progresso: ReadingProgress { ReadingProgress.shared }

    private var bloqueado: Bool { store.estaBloqueado(book) }
    private var spreadSalvo: Int { progresso.spread(for: book.id) }
    private var concluido: Bool { progresso.concluido(book.id, total: book.spreads.count) }
    private var comecou: Bool { progresso.started(book.id) && !concluido }

    private var postura: Postura { Postura(tamanho: tamanho, horizontal: hSize) }

    /// Cabe capa e texto lado a lado. Em pé, um embaixo do outro e rolando.
    private var ladoALado: Bool {
        tamanho.width > tamanho.height * 1.15 && tamanho.width >= 640
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if tamanho == .zero {
                UITokens.surface
            } else if ladoALado {
                deitado
            } else {
                emPe
            }
            fechar
        }
        .fundoDePapel()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { tamanho = $0 }
        .task {
            // O pacote de arte enquanto o adulto lê a sinopse: o toque em
            // "Read" encontra o livro pronto em vez da tela de espera. Livro
            // animado leva junto as páginas em movimento — 19 MB em HEVC, e
            // quem abriu a página de um livro animado quase sempre lê.
            Pacotes.shared.antecipar(book.animado
                                     ? [book.artTag, book.spreadMotionTag]
                                     : [book.artTag])
            guard !registrou else { return }
            registrou = true
            Analytics.shared.track(.bookDetailViewed(
                book: book, origem: origem, bloqueado: bloqueado,
                temProgresso: progresso.started(book.id)))
        }
    }

    // MARK: Os dois arranjos

    private var emPe: some View {
        ScrollView {
            VStack(spacing: Space.lg) {
                capa
                    .frame(maxWidth: min(340, tamanho.width - Space.xl * 2))
                ficha
            }
            .padding(.horizontal, Space.lg)
            // Folga no topo para o X não encostar na capa.
            .padding(.top, Space.xxl + Space.sm)
            .padding(.bottom, Space.xxl)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
    }

    /// Deitado, as duas colunas dividem a tela. No Duo aberto a divisa é a
    /// calha da dobra: capa de um lado, texto do outro, e nada em cima do
    /// vinco.
    private var deitado: some View {
        let espaco = postura.duasMetades ? postura.calha : Space.xl
        let coluna = (tamanho.width - espaco) / 2 - Space.lg

        return HStack(alignment: .center, spacing: espaco) {
            capa
                .frame(maxWidth: coluna,
                       maxHeight: tamanho.height - Space.xl * 2)

            ScrollView {
                ficha
                    .padding(.vertical, Space.xl)
            }
            .frame(width: coluna)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
        }
        .padding(.horizontal, Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Capa

    /// A capa em movimento, do tamanho que ela merece. `tocando` é sempre
    /// verdadeiro: esta tela existe para isso, e o `MotionArte` já respeita
    /// Reduzir Movimento e Modo de Baixo Consumo por dentro.
    ///
    /// Escondida do VoiceOver: o título dela é o mesmo que a ficha lê logo
    /// abaixo, e ninguém quer ouvir duas vezes.
    private var capa: some View {
        BookCover(book: book, estilo: .destaque) {
            CoverMotion(book: book, tocando: true)
        }
        .auraDeMovimento(book.animado, raio: BookCover<EmptyView>.Estilo.destaque.raio)
        .accessibilityHidden(true)
    }

    // MARK: Ficha

    private var ficha: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            // Os dois selos convivem: um livro animado pode estar bloqueado.
            HStack(spacing: Space.xs) {
                selo
                if book.animado {
                    etiqueta("This one moves", icone: "wand.and.sparkles")
                }
            }

            Text(book.title.resolved())
                .font(TypeScale.titulo)
                .foregroundStyle(UITokens.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let primeira = book.spreads.first?.left.resolved(), !primeira.isEmpty {
                // A primeira frase do livro é a melhor sinopse que existe: é
                // a voz da história, não um resumo escrito por fora.
                Text(primeira)
                    .font(.system(size: TypeScale.uiSize + 2, weight: .regular, design: .serif))
                    .foregroundStyle(UITokens.inkSecondary)
                    .lineSpacing(TypeScale.lineSpacing(for: TypeScale.uiSize + 2))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(fatos)
                .font(TypeScale.legenda)
                .foregroundStyle(UITokens.inkSecondary)

            if comecou { barraDeProgresso }

            botao
                .padding(.top, Space.xs)

            if comecou {
                Button("Start from the beginning") {
                    progresso.reset(book.id)
                    onRead()
                }
                .font(TypeScale.legenda)
                .foregroundStyle(UITokens.accent)
                .buttonStyle(.plain)
                // Centrado embaixo do botão principal, que ocupa a largura
                // toda: alinhado à esquerda ele parecia solto da ação.
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "12 pages · Nuna and Theo".
    private var fatos: String {
        var partes = ["\(book.spreads.count) pages"]
        let elenco = Self.lista(book.elenco)
        if !elenco.isEmpty { partes.append(elenco) }
        return partes.joined(separator: "  ·  ")
    }

    @ViewBuilder
    private var selo: some View {
        if bloqueado {
            etiqueta("Locked", icone: "lock.fill")
        } else if store.ehHistoriaDaSemana(book) {
            etiqueta("Free this week", icone: "sparkles")
        } else if concluido {
            etiqueta("You finished this one", icone: "checkmark.circle.fill")
        }
    }

    private func etiqueta(_ texto: String, icone: String) -> some View {
        Label(texto, systemImage: icone)
            .font(TypeScale.legenda.weight(.medium))
            .foregroundStyle(UITokens.ink)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xxs)
            .background(UITokens.accentSuave.opacity(0.35), in: .capsule)
    }

    private var barraDeProgresso: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text("You stopped on page \(spreadSalvo + 1) of \(book.spreads.count)")
                .font(TypeScale.legenda)
                .foregroundStyle(UITokens.inkSecondary)

            ProgressView(value: Double(spreadSalvo + 1),
                         total: Double(max(1, book.spreads.count)))
                .tint(UITokens.accent)
                .frame(maxWidth: 240)
        }
        .accessibilityElement(children: .combine)
    }

    private var botao: some View {
        Button(action: onRead) {
            Text(rotulo)
                .font(TypeScale.ui.weight(.semibold))
                // A largura mora DENTRO do rótulo, senão a cápsula de vidro
                // não estica (mesma regra do paywall).
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(UITokens.accent)
        .controlSize(.large)
        .accessibilityHint(bloqueado ? "Opens the subscription screen"
                                     : "Opens the story")
    }

    private var rotulo: String {
        if bloqueado { return "Unlock this story" }
        if comecou { return "Continue on page \(spreadSalvo + 1)" }
        if concluido { return "Read it again" }
        return "Read the story"
    }

    // MARK: Fechar

    private var fechar: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(UITokens.ink)
                .frame(width: 30, height: 30)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Close")
        .padding(.horizontal, Space.md)
        .padding(.top, Space.xs)
    }

    /// "Nuna", "Nuna and Theo", "Nuna, Theo and Lia". Escrito à mão porque o
    /// app é en-US fixo, e `ListFormatter` seguiria a região do aparelho.
    private static func lista(_ nomes: [String]) -> String {
        switch nomes.count {
        case 0:  return ""
        case 1:  return nomes[0]
        default: return nomes.dropLast().joined(separator: ", ") + " and " + nomes[nomes.count - 1]
        }
    }
}

#Preview("Detalhe") {
    if let livro = Catalog.loadAll().first {
        BookDetailView(book: livro,
                       origem: .biblioteca(posicao: 0, filtro: .todos, temBusca: false),
                       onRead: {}, onClose: {})
    }
}
