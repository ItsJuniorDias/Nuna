//
//  HomeView.swift
//  Nuna
//
//  Home com seis seções possíveis, em ordem de decisão:
//
//    1. Cabeçalho — saudação por hora do dia e convite à assinatura
//    2. Continuar de onde parou — se há progresso salvo
//    3. Histórias da semana — carrossel de três, abre na primeira
//    4. Chegaram agora — até 6 mais recentes ainda não lidos
//    5. Coleções — rails temáticos ("no quintal", "antes de dormir"...)
//    6. Em breve — os livros do catálogo que ainda não têm arte
//
//  Toda seção só aparece quando tem o que mostrar: a Home é decente com
//  poucos livros com arte E cheia depois — mesmo código.
//
//  O acervo inteiro NÃO fica aqui: é a Biblioteca, com busca, filtro e
//  ordenação. Repetir os 50 livros numa prateleira no fim da Home só dava
//  rolagem.
//

import SwiftUI

struct HomeView: View {
    let books: [Book]
    /// Livro e a capa tocada, que dá o id do zoom do leitor e a origem da
    /// leitura no analytics.
    var onOpen: (Book, OrigemDaLeitura) -> Void
    var onUnlock: () -> Void

    private var progress: ReadingProgress { .shared }
    private var store: Store { .shared }

    @Environment(\.postura) private var postura
    @Environment(\.displayScale) private var escalaDaTela
    /// A Home está rolando agora (ver `homeRolando`).
    @State private var rolando = false

    // MARK: Seleções

    private var disponiveis: [Book] { books.filter(\.isAvailable) }

    /// O livro que a criança está lendo AGORA: o mais recente entre os
    /// abertos e não terminados. Antes era "o primeiro da estante com
    /// progresso", que numa estante embaralhada era quase sempre outro.
    private var emAndamento: Book? {
        disponiveis
            .filter {
                progress.emLeitura($0.id)
                    && !progress.concluido($0.id, total: $0.spreads.count)
            }
            .max { progress.ultimaLeitura($0.id) < progress.ultimaLeitura($1.id) }
    }
    private var daSemana: [Book] { Featured.storiesOfTheWeek(from: books) }
    private var idsDaSemana: Set<String> { Set(daSemana.map(\.id)) }

    private var novos: [Book] {
        let semana = idsDaSemana
        return disponiveis
            .filter { !progress.emLeitura($0.id) && !semana.contains($0.id) }
            .prefix(6)
            .map { $0 }
    }

    /// Livros do catálogo que ainda não têm arte. Ficam numa prateleira só
    /// deles: no fim de "All books" ninguém rolava até lá, e quem acompanha
    /// o app quer ver o que vem.

    /// Livro para "Continuar de onde parou".
    ///
    /// Sem excluir os da semana: os únicos livros que quem não assina pode
    /// abrir SÃO os da semana, então a regra antiga escondia o cartão
    /// justamente de quem mais precisa dele.
    private var paraContinuar: Book? { emAndamento }

    /// Duo aberto na horizontal: o carrossel da semana ocupa uma metade e a outra
    /// recebe "Continuar" e "Chegaram agora". Esticada na largura toda, a
    /// capa — com o rosto da Nuna no meio — ficaria em cima da dobra. Sem
    /// nada para a outra metade, volta o carrossel na largura toda.
    private var destaqueDividido: Bool {
        postura.duasMetades && !daSemana.isEmpty && (paraContinuar != nil || !novos.isEmpty)
    }

    private var colecoes: [(Featured.Collection, [Book])] {
        Featured.naHome.compactMap { id in
            guard let c = Featured.collections.first(where: { $0.id == id }) else { return nil }
            let livros = c.filter(books)
            return livros.count >= 2 ? (c, livros) : nil
        }
    }

    // MARK: View

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.xxl, pinnedViews: []) {
                cabecalho

                if destaqueDividido {
                    DuasMetades {
                        secaoDaSemana(margem: 0)
                    } segunda: {
                        VStack(alignment: .leading, spacing: Space.xxl) {
                            if let atual = paraContinuar {
                                secao("Pick up where you left off", icon: "bookmark.fill",
                                      analitico: .continueStrip, margem: 0) {
                                    faixaContinuar(atual)
                                }
                            }
                            if !novos.isEmpty {
                                rail("Just arrived", icon: "sparkle", books: novos,
                                     trilho: .chegaramAgora, margem: 0)
                            }
                        }
                    }
                    .padding(.horizontal, Space.lg)

                    prateleiraAnimadas
                } else {
                    if let atual = paraContinuar {
                        secao("Pick up where you left off", icon: "bookmark.fill",
                              analitico: .continueStrip) {
                            faixaContinuar(atual)
                        }
                    }

                    if !daSemana.isEmpty {
                        secaoDaSemana()
                    }

                    prateleiraAnimadas

                    if !novos.isEmpty {
                        rail("Just arrived", icon: "sparkle", books: novos,
                             trilho: .chegaramAgora)
                    }
                }

                ForEach(colecoes, id: \.0.id) { colecao, livros in
                    rail(colecao.title, subtitle: colecao.subtitle,
                         icon: colecao.icon, books: livros, trilho: .colecao(colecao.id))
                }
            }
            // Sem padding horizontal aqui: as prateleiras rolam de borda a
            // borda da tela. Cada seção aplica a própria margem.
            .padding(.top, Space.xs)
            .padding(.bottom, Space.xxxl)
        }
        .background(UITokens.surface)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        // O vídeo da capa do carrossel pausa enquanto a Home rola, e volta
        // quando ela para. Muda duas vezes por gesto, não a cada quadro.
        .onScrollPhaseChange { _, fase in
            if rolando != fase.isScrolling { rolando = fase.isScrolling }
        }
        .environment(\.homeRolando, rolando)
        // As capas das prateleiras, reduzidas ao tamanho em que aparecem e
        // decodificadas fora da main, antes de a criança rolar até elas.
        .task {
            await Miniaturas.shared.prepararTodas(
                books.map(\.coverImageName),
                largura: Miniaturas.faixa(Self.larguraDaCapa * escalaDaTela))
        }
        // As três da semana são as mais tocadas da Home: o pacote de arte
        // delas vem em segundo plano, sem pressa, para o toque abrir na hora.
        .task(id: idsDaSemana) {
            // O animado da semana leva junto as páginas em movimento: é a
            // amostra grátis do recurso e o primeiro cartão do carrossel, e a
            // primeira impressão dele não pode ser uma barra de download.
            Pacotes.shared.antecipar(daSemana.map(\.artTag)
                                     + daSemana.filter(\.animado).map(\.spreadMotionTag))
        }
    }

    /// As histórias com as páginas em movimento, logo abaixo da semana.
    ///
    /// Vitrine da assinatura: é o que o app tem de mais caro para produzir.
    /// Some sozinha enquanto não houver pelo menos duas — prateleira de um
    /// item só parece erro, e no começo ela vai crescer livro a livro.
    @ViewBuilder
    private var prateleiraAnimadas: some View {
        let animadas = Featured.animadas.filter(books)
        if animadas.count >= 2 {
            rail(Featured.animadas.title, subtitle: Featured.animadas.subtitle,
                 icon: Featured.animadas.icon, books: animadas,
                 trilho: .colecao(Featured.animadas.id),
                 trailing: store.isPremium ? nil : "Premium")
        }
    }

    /// Largura das capas nas prateleiras. É também o tamanho em que as
    /// miniaturas são preparadas — um número só para os dois.
    static let larguraDaCapa: CGFloat = 132

    // MARK: Cabeçalho

    private var cabecalho: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(saudacao)
                .font(TypeScale.legenda.weight(.medium))
                .foregroundStyle(UITokens.inkSecondary)
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text("Nuna")
                    .font(.system(size: 40, weight: .semibold, design: .serif))
                    .foregroundStyle(UITokens.ink)

                Spacer()

                if !store.isPremium {
                    assinar
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Space.xs)
        .padding(.horizontal, Space.lg)
    }

    private var saudacao: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12:  return "Good morning"
        case 12..<18: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    /// Entra no lugar do contador "N de 50 livros": com um livro só aberto, o
    /// número virava lembrete do que falta. Compacto e numa linha — ao lado
    /// do "Nuna" de 40pt sobram ~250pt em 354, e "Teste grátis" pede ~140.
    /// Some quando já há assinatura. O toque não vende nada direto: abre os
    /// planos, e a compra passa pelo portão parental no botão Assinar.
    private var assinar: some View {
        Button(action: onUnlock) {
            Label(store.trialEligible ? "Free trial" : "Subscribe",
                  systemImage: "sparkles")
                .labelStyle(.titleAndIcon)
                .font(TypeScale.legenda.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(.glassProminent)
        .tint(UITokens.accent)
        .controlSize(.small)
        .accessibilityHint("Shows the subscription plans")
    }

    // MARK: Blocos reutilizáveis

    private func secao<Content: View>(
        _ titulo: String, icon: String, analitico: SecaoDaHome,
        trailing: String? = nil,
        margem: CGFloat = Space.lg,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(titulo, icon: icon, trailing: trailing)
            content()
        }
        .padding(.horizontal, margem)
        .onScrollVisibilityChange(threshold: 0.5) { visivel in
            if visivel { registrarVisita(analitico) }
        }
    }

    /// Como as prateleiras: o título respeita a margem e o carrossel vai de
    /// borda a borda, para as capas vizinhas aparecerem até a beira da tela.
    private func secaoDaSemana(margem: CGFloat = Space.lg) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Stories of the week", icon: "sparkles",
                          trailing: Featured.weekLabel())
                .padding(.horizontal, margem)
            WeekCarousel(books: daSemana, margem: margem, onOpen: onOpen)
        }
        .onScrollVisibilityChange(threshold: 0.5) { visivel in
            if visivel { registrarVisita(.weekCard) }
        }
    }

    private func rail(_ titulo: String, subtitle: String? = nil,
                      icon: String, books: [Book], trilho: TrilhoDaHome,
                      trailing: String? = nil,
                      margem: CGFloat = Space.lg) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(titulo, icon: icon, subtitle: subtitle, trailing: trailing)
                .padding(.horizontal, margem)

            // A rolagem ocupa a largura da tela e a margem vai no conteúdo:
            // a primeira capa alinha com o título, e as capas deslizam até a
            // borda em vez de serem cortadas 24pt antes dela.
            ScrollView(.horizontal, showsIndicators: false) {
                // Preguiçosa: só as capas que aparecem existem. Com `HStack`,
                // uma prateleira entrando na tela criava as até 19 de uma vez.
                LazyHStack(alignment: .top, spacing: Space.md) {
                    ForEach(Array(books.enumerated()), id: \.element.id) { posicao, book in
                        // bloqueado continua tocável — o `RootView` desvia
                        // pro paywall em vez de abrir o leitor
                        let origem = trilho.origem(posicao: posicao)
                        Button {
                            if book.isAvailable { onOpen(book, origem) }
                        } label: {
                            LibraryTile(book: book, showsProgress: false)
                                .frame(width: Self.larguraDaCapa)
                                .origemDoZoom(origem.idDoZoom(book), raio: 16)
                                .opacity(book.isAvailable ? 1 : 0.55)
                        }
                        .buttonStyle(.plain)
                        .disabled(!book.isAvailable)
                    }
                }
                .padding(.vertical, Space.xxs)
            }
            .contentMargins(.horizontal, margem, for: .scrollContent)
            .scrollEdgeEffectStyle(.soft, for: .horizontal)
        }
        .onScrollVisibilityChange(threshold: 0.5) { visivel in
            if visivel { registrarVisita(trilho.secao, colecao: trilho.idDaColecao) }
        }
    }

    /// Uma vez por seção por sessão, e a trava mora no `Analytics`, não em
    /// `@State`: a lista preguiçosa cria e descarta as seções enquanto rola,
    /// e a Home reaparece a cada livro fechado.
    private func registrarVisita(_ secao: SecaoDaHome, colecao: String? = nil) {
        Analytics.shared.track(
            .homeSectionViewed(secao: secao, colecao: colecao, duasMetades: postura.duasMetades),
            umaVezPorSessao: "home_section|\(secao.rawValue)|\(colecao ?? "")")
    }

    // MARK: Origens do zoom

    private func faixaContinuar(_ livro: Book) -> some View {
        let origem = OrigemDaLeitura.continuar
        return ContinueStrip(book: livro) { onOpen(livro, origem) }
            .origemDoZoom(origem.idDoZoom(livro), raio: 22)
    }

}

/// Cabeçalho de seção. Aceita subtítulo (para coleções) OU rótulo trailing.
struct SectionHeader: View {
    let titulo: String
    let icon: String
    var subtitle: String? = nil
    var trailing: String? = nil

    init(_ titulo: String, icon: String, subtitle: String? = nil,
         trailing: String? = nil) {
        self.titulo = titulo
        self.icon = icon
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: Space.xs) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(UITokens.accent)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(titulo)
                    .font(TypeScale.ui.weight(.semibold))
                    .foregroundStyle(UITokens.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(TypeScale.legenda)
                        .foregroundStyle(UITokens.inkSecondary)
                }
            }

            Spacer(minLength: 0)

            if let trailing {
                Text(trailing)
                    .font(TypeScale.legenda)
                    .foregroundStyle(UITokens.inkSecondary)
                    .monospacedDigit()
                    .padding(.horizontal, Space.sm)
                    .padding(.vertical, 3)
                    .glassEffect(.regular, in: .capsule)
            }
        }
    }
}
