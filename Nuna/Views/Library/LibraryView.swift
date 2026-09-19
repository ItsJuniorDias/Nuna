//
//  LibraryView.swift
//  Nuna
//
//  Grade do acervo, com busca, filtro e ordenação. Barra fixa no topo em
//  `safeAreaInset` — busca não pode rolar embora quando a criança desce a
//  grade procurando um livro.
//
//  Placeholders (livros ainda sem arte) aparecem com "Coming soon" e não são
//  tocáveis — assim a Biblioteca já mostra os 25 hoje.
//
//  Livro bloqueado (sem assinatura) é outra coisa: tem arte, leva cadeado e
//  continua tocável. Quem desvia o toque pro paywall é o `RootView`.
//

import SwiftUI

struct LibraryView: View {
    let books: [Book]
    /// Livro e a capa tocada, que dá o id do zoom do leitor e a origem da
    /// leitura no analytics.
    var onOpen: (Book, OrigemDaLeitura) -> Void

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.postura) private var postura
    @State private var busca = ""
    @State private var filtro: Filtro = .todos
    @State private var ordem: Ordem = .catalogo
    /// Última busca que virou evento. Fica no aparelho: só o tamanho sai.
    @State private var ultimaBuscaRegistrada = ""

    private var progress: ReadingProgress { .shared }

    enum Filtro: String, CaseIterable, Identifiable {
        case todos, disponiveis, comecados
        var id: String { rawValue }
        var titulo: LocalizedStringResource {
            switch self {
            case .todos:       return "All"
            case .disponiveis: return "Available"
            case .comecados:   return "Started"
            }
        }
        var icone: String {
            switch self {
            case .todos:       return "square.grid.2x2"
            case .disponiveis: return "checkmark.circle"
            case .comecados:   return "bookmark.fill"
            }
        }
        /// Valor de `filter` no catálogo de eventos.
        var analitico: String {
            switch self {
            case .todos:       return "all"
            case .disponiveis: return "available"
            case .comecados:   return "started"
            }
        }
    }

    enum Ordem: String, CaseIterable, Identifiable {
        case catalogo, titulo
        var id: String { rawValue }
        var titulo: LocalizedStringResource {
            switch self {
            case .catalogo: return "Catalog order"
            case .titulo:   return "Title"
            }
        }
        /// Valor de `sort` no catálogo de eventos.
        var analitico: String {
            switch self {
            case .catalogo: return "catalog"
            case .titulo:   return "title"
            }
        }
    }

    private var resultado: [Book] {
        let filtrado = books.filter { book in
            let porFiltro: Bool = {
                switch filtro {
                case .todos:       return true
                case .disponiveis: return book.isAvailable
                case .comecados:   return progress.started(book.id)
                }
            }()
            guard porFiltro else { return false }
            guard !busca.isEmpty else { return true }
            return book.title.resolved()
                .localizedCaseInsensitiveContains(busca)
        }
        switch ordem {
        case .catalogo: return filtrado
        case .titulo:   return filtrado.sorted { $0.title.resolved() < $1.title.resolved() }
        }
    }

    private var columns: [GridItem] {
        let minimo: CGFloat = hSize == .regular ? 172 : 148
        guard postura.duasMetades else {
            return [GridItem(.adaptive(minimum: minimo), spacing: Space.md, alignment: .top)]
        }

        // Duo aberto na horizontal: número PAR de colunas, metade de cada
        // lado, e a calha da dobra no lugar do espaço do meio. Com grade
        // adaptativa uma capa podia cair bem em cima da dobra.
        let util = postura.tamanho.width - Space.lg * 2 - postura.calha
        let porMetade = max(1, Int((util / 2 + Space.md) / (minimo + Space.md)))
        var itens = Array(repeating: GridItem(.flexible(), spacing: Space.md, alignment: .top),
                          count: porMetade * 2)
        itens[porMetade - 1].spacing = postura.calha
        return itens
    }

    var body: some View {
        ScrollView {
            if resultado.isEmpty {
                semResultado
            } else {
                LazyVGrid(columns: columns, spacing: Space.lg) {
                    ForEach(Array(resultado.enumerated()), id: \.element.id) { posicao, book in
                        let origem = OrigemDaLeitura.biblioteca(posicao: posicao, filtro: filtro,
                                                                temBusca: !busca.isEmpty)
                        Button {
                            if book.isAvailable { onOpen(book, origem) }
                        } label: {
                            LibraryTile(book: book)
                                .origemDoZoom(origem.idDoZoom(book), raio: 16)
                                .opacity(book.isAvailable ? 1 : 0.55)
                                .overlay(alignment: .top) {
                                    if !book.isAvailable { emBreve.padding(Space.xs) }
                                }
                        }
                        .buttonStyle(.plain)
                        .disabled(!book.isAvailable)
                    }
                }
                .padding(.horizontal, Space.lg)
                .padding(.top, Space.sm)
                .padding(.bottom, Space.xxxl)
            }
        }
        .background(UITokens.surface)
        .safeAreaInset(edge: .top) { barra }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        // Um evento por busca assentada: cada tecla cancela a espera. Voltar
        // à aba com o mesmo texto não conta de novo.
        .task(id: busca) {
            guard !busca.isEmpty else {
                ultimaBuscaRegistrada = ""
                return
            }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, busca != ultimaBuscaRegistrada else { return }
            ultimaBuscaRegistrada = busca
            Analytics.shared.track(.librarySearchPerformed(
                tamanhoDaBusca: busca.count, resultados: resultado.count,
                filtro: filtro, ordem: ordem))
        }
        // Aqui e não no chip: tocar o chip ativo reatribui o mesmo valor, e o
        // `ViewThatFits` monta três fileiras de chips.
        .onChange(of: filtro) { antigo, novo in
            Analytics.shared.track(.libraryFilterChanged(
                filtro: novo, anterior: antigo, resultados: resultado.count,
                ordem: ordem, temBusca: !busca.isEmpty))
        }
        .onChange(of: ordem) { antiga, nova in
            Analytics.shared.track(.librarySortChanged(
                ordem: nova, anterior: antiga, filtro: filtro, temBusca: !busca.isEmpty))
        }
    }

    private var emBreve: some View {
        Text("Coming soon")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(UITokens.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .glassEffect(.regular, in: .capsule)
    }

    // MARK: Barra

    private var barra: some View {
        // Duas metades: busca de um lado da dobra, filtros do outro — campo
        // de texto atravessando a dobra é cursor que some na curva.
        DuasMetades(alinhamento: .center, espacoEmColuna: Space.sm) {
            campoBusca
        } segunda: {
            chips
        }
        .padding(.horizontal, Space.lg)
        .padding(.top, Space.xs)
        .padding(.bottom, Space.sm)
    }

    private var campoBusca: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(UITokens.inkSecondary)

            TextField("Search books", text: $busca)
                .font(TypeScale.ui)
                .foregroundStyle(UITokens.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !busca.isEmpty {
                Button { busca = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(UITokens.inkSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }

            Menu {
                Picker("Sort", selection: $ordem) {
                    ForEach(Ordem.allCases) { Text($0.titulo).tag($0) }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(UITokens.inkSecondary)
            }
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
        .glassEffect(.regular, in: .capsule)
    }

    /// Filtros + contador. Chip nunca quebra linha — "Dispo/níveis" deforma a
    /// cápsula. Com ícone a fileira pede ~407pt e num iPhone de 402pt sobram
    /// 354pt, então `ViewThatFits` tenta ícone + nome, depois só o nome, e em
    /// tela mais estreita que isso vira faixa rolável.
    private var chips: some View {
        HStack(spacing: Space.xs) {
            ViewThatFits(in: .horizontal) {
                fileiraDeChips(comIcone: true)
                fileiraDeChips(comIcone: false)
                ScrollView(.horizontal) {
                    fileiraDeChips(comIcone: false)
                        .padding(.vertical, Space.xxs)
                }
                .scrollIndicators(.hidden)
            }
            // Sem prioridade o HStack oferece metade do espaço livre ao
            // ViewThatFits e metade ao Spacer, e ele cai na faixa rolável
            // mesmo quando os chips cabem.
            .layoutPriority(1)

            Spacer(minLength: 0)

            Text("\(resultado.count)")
                .font(TypeScale.legenda.weight(.medium))
                .foregroundStyle(UITokens.inkSecondary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, Space.sm)
                .padding(.vertical, Space.xxs)
                .glassEffect(.regular, in: .capsule)
                .accessibilityLabel(Text("\(resultado.count) books"))
        }
    }

    private func fileiraDeChips(comIcone: Bool) -> some View {
        GlassEffectContainer(spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                ForEach(Filtro.allCases) { f in
                    chip(f, comIcone: comIcone)
                }
            }
        }
    }

    private func chip(_ f: Filtro, comIcone: Bool) -> some View {
        let ativo = f == filtro
        return Button {
            withAnimation(.easeInOut(duration: 0.22)) { filtro = f }
        } label: {
            Group {
                if comIcone {
                    Label { rotulo(f, ativo: ativo) } icon: { Image(systemName: f.icone) }
                } else {
                    rotulo(f, ativo: ativo)
                }
            }
            .font(TypeScale.legenda)
            .foregroundStyle(ativo ? UITokens.accent : UITokens.inkSecondary)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xxs)
        }
        .buttonStyle(.plain)
        .glassEffect(
            ativo ? .regular.interactive().tint(UITokens.accentSuave.opacity(0.35))
                  : .regular.interactive(),
            in: .capsule
        )
        .accessibilityAddTraits(ativo ? [.isSelected, .isButton] : .isButton)
    }

    /// Nome do filtro numa linha só, com a largura do semibold reservada: o
    /// chip não cresce ao ser escolhido, e o `ViewThatFits` não troca de
    /// variante só porque outro filtro ficou ativo.
    private func rotulo(_ f: Filtro, ativo: Bool) -> some View {
        Text(f.titulo)
            .font(TypeScale.legenda.weight(.semibold))
            .hidden()
            .overlay {
                Text(f.titulo)
                    .font(TypeScale.legenda.weight(ativo ? .semibold : .regular))
            }
            .lineLimit(1)
            .fixedSize()
    }

    private var semResultado: some View {
        VStack(spacing: Space.xs) {
            Text(busca.isEmpty ? "Nothing here" : "No books found")
                .font(TypeScale.titulo)
                .foregroundStyle(UITokens.ink)
            Text(busca.isEmpty
                 ? "Change the filter to see other books."
                 : "Try another title.")
                .font(TypeScale.legenda)
                .foregroundStyle(UITokens.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Space.xxxl)
        .frame(maxWidth: .infinity)
    }
}

/// Capa da grade, reusada pela Home e pela Biblioteca.
struct LibraryTile: View {
    let book: Book
    var showsProgress: Bool = true

    private var comecou: Bool {
        showsProgress && ReadingProgress.shared.started(book.id)
    }
    private var pagina: Int { ReadingProgress.shared.spread(for: book.id) + 1 }

    /// Vale também nas prateleiras da Home (`showsProgress: false`): é ali que
    /// a criança mais toca, e o cadeado avisa antes que um adulto é chamado.
    private var bloqueado: Bool { Store.shared.estaBloqueado(book) }

    var body: some View {
        BookCover(book: book, estilo: .grade)
            .overlay(alignment: .topTrailing) { selo }
            // O selo do movimento fica do lado oposto ao do cadeado e ao do
            // contador: um livro animado e bloqueado mostra os dois, e eles
            // não podem se empilhar.
            .overlay(alignment: .topLeading) {
                if book.animado { SeloDeMovimento() }
            }
            .auraDeMovimento(book.animado, raio: BookCover<EmptyView>.Estilo.grade.raio)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(rotuloAcessivel)
            .accessibilityAddTraits(book.isAvailable ? .isButton : [])
    }

    /// Segue o selo: bloqueado esconde a página, então o VoiceOver também.
    private var rotuloAcessivel: Text {
        var texto = Text(verbatim: book.title.resolved())
        if book.animado { texto = texto + Text(", moving pictures") }
        if bloqueado { return texto + Text(", locked") }
        if comecou { return texto + Text(", page \(pagina) of \(book.spreads.count)") }
        return texto
    }

    /// Cadeado no lugar do progresso, com a mesma altura de cápsula: página
    /// salva de assinatura vencida não serve de nada enquanto não abre.
    @ViewBuilder
    private var selo: some View {
        if bloqueado {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(UITokens.ink)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .glassEffect(.regular, in: .capsule)
                .padding(Space.xs)
        } else if comecou {
            Text("\(pagina)/\(book.spreads.count)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(UITokens.ink)
                .monospacedDigit()
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .glassEffect(.regular, in: .capsule)
                .padding(Space.xs)
        }
    }
}
