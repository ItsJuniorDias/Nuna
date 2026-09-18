//
//  RootView.swift
//  Nuna
//
//  Tab bar de Liquid Glass. Em iOS 26+ a tab bar padrão JÁ é Liquid Glass —
//  não se aplica `.glassEffect` nela. Vidro à mão é só para controle custom.
//
//  O leitor não vive numa aba: ele é full-bleed e esconde a tab bar. Vidro
//  translúcido sobre a faixa de texto da história deixaria ilegível pra quem
//  tem três anos, e essa faixa é justamente o rodapé da página.
//
//  Cada tela mede o próprio espaço (`medirPostura`) para se reorganizar em
//  volta da dobra do iPhone Duo; o leitor mede sozinho.
//
//  A arte de cada livro vem por On-Demand Resources, não no download do app
//  (ver `Pacotes`). Quem espera o pacote também é o `open`: enquanto ele não
//  chega, a capa fica na tela com uma barra, e nunca se abre um livro em
//  branco.
//
//  Livro bloqueado não abre o leitor: o desvio pro paywall mora aqui, em
//  `open`. Home, Biblioteca e cartão da semana só dizem "abre
//  este livro" — nenhuma delas precisa saber quem assina.
//

import SwiftUI

struct RootView: View {
    let books: [Book]

    @State private var tab: AppTab = .home
    @State private var reading: LeituraAberta?
    /// Livro cuja página está aberta (`BookDetailView`).
    @State private var detalhe: LeituraAberta?
    @State private var mostrandoPaywall = false
    @State private var origemDoPaywall: OrigemDoPaywall = .cabecalhoDaHome
    @State private var registrouPrimeiraTela = false
    /// Livro esperando o pacote de arte chegar.
    @State private var preparando: Book?
    /// Pacote que não veio: sem rede, o livro não abre e o adulto precisa
    /// entender por quê.
    @State private var semRede: Book?

    /// Zoom capa → leitor (ver `ZoomDaCapa.swift`).
    @Namespace private var capas
    @State private var origemDoZoom = ""
    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento

    /// O valor bruto é o `screen` do catálogo de eventos.
    enum AppTab: String, Hashable { case home, library, parents }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                HomeView(books: books, onOpen: abrir,
                         onUnlock: { abrirPaywall(.cabecalhoDaHome) })
                    .medirPostura()
            }

            Tab("Library", systemImage: "books.vertical.fill", value: AppTab.library) {
                LibraryView(books: books, onOpen: abrir)
                    .medirPostura()
            }

            Tab("Parents", systemImage: "person.2.fill", value: AppTab.parents) {
                ParentsView(books: books, onUnlock: { abrirPaywall(.pais) })
                    .medirPostura()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(UITokens.accent)
        .environment(\.zoomDasCapas, capas)
        // Com leitor ou página de livro por cima, a Home atrás para de animar.
        .environment(\.homeCoberta, reading != nil || detalhe != nil)
        // O onAppear roda de novo toda vez que o leitor ou o paywall fecham
        // por cima da TabView; a tela inicial é uma só.
        .onAppear {
            guard !registrouPrimeiraTela else { return }
            registrouPrimeiraTela = true
            Analytics.shared.track(.screenViewed(tela: tab, anterior: nil, gatilho: .initial))
        }
        .onChange(of: tab) { antiga, nova in
            Analytics.shared.track(.screenViewed(tela: nova, anterior: antiga, gatilho: .tabTap))
        }
        .overlay {
            if let preparando {
                PreparandoLivro(book: preparando,
                                estado: estadoDoPreparo(preparando))
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: preparando?.id)
        .alert("Couldn't get this book",
               isPresented: Binding(get: { semRede != nil },
                                    set: { if !$0 { semRede = nil } })) {
            Button("OK", role: .cancel) { semRede = nil }
        } message: {
            Text(mensagemDoPacote)
        }
        .fullScreenCover(item: $detalhe) { livro in
            BookDetailView(book: livro.book, origem: livro.origem,
                           onRead: { lerDoDetalhe(livro) },
                           onClose: { detalhe = nil })
                .hidesTabBar()
                .navigationTransition(transicaoDoZoom)
        }
        .fullScreenCover(item: $reading) { leitura in
            // o botão de fechar mora na barra do próprio leitor, junto dos
            // outros controles — assim nada flutua sozinho sobre a arte
            ReaderView(book: leitura.book, origem: leitura.origem) { reading = nil }
                .hidesTabBar()
                // Criança puxa a tela para baixo sem querer; fechar é só no X.
                .interactiveDismissDisabled()
                .navigationTransition(transicaoDoZoom)
        }
        // Os planos abrem direto; o portão parental que a categoria Kids
        // exige fica no botão Assinar do próprio `PaywallView`.
        .fullScreenCover(isPresented: $mostrandoPaywall) {
            PaywallView(origem: origemDoPaywall) { mostrandoPaywall = false }
                .medirPostura()
        }
    }

    /// O alerta é da criança e do adulto: uma frase, sem jargão. Em build de
    /// desenvolvimento vai junto o motivo real — "sem internet" é a mensagem
    /// errada quando a internet está boa e o que falhou foi o pacote.
    private var mensagemDoPacote: String {
        let base = "Nuna needs the internet the first time you open a book. "
            + "Once it is on this device, it works offline."
        #if DEBUG
        if let falha = Pacotes.shared.ultimaFalha {
            return base + "\n\n[debug] \(falha)"
        }
        #endif
        return base
    }

    /// Zoom da capa tocada para a tela que sobe — a página do livro ou o
    /// leitor. Com Reduzir Movimento é um fade, sem crescer da capa.
    private var transicaoDoZoom: AnyNavigationTransition {
        reduzirMovimento
            ? AnyNavigationTransition(.crossFade)
            : AnyNavigationTransition(.zoom(sourceID: origemDoZoom, in: capas))
    }

    /// Por onde a capa tocada entra: página do livro ou história direto.
    ///
    /// O carrossel da semana e a faixa de continuar abrem a história NA HORA
    /// — são superfícies de "ler agora", e uma tela no meio do caminho tira a
    /// história de quem tem três anos por um toque. As capas de navegação
    /// (prateleiras da Home e grade da Biblioteca) passam pela página do
    /// livro, que é onde a capa em movimento tem lugar para tocar.
    private func abrir(_ book: Book, de origem: OrigemDaLeitura) {
        switch origem {
        case .semana, .continuar:
            open(book, de: origem)
        case .chegaramAgora, .colecao, .todos, .biblioteca:
            origemDoZoom = origem.idDoZoom(book)
            detalhe = LeituraAberta(book: book, origem: origem)
        }
    }

    /// "Read" na página do livro. A página sai ANTES de o leitor subir: duas
    /// folhas em tela cheia não se empilham, e assim fechar o leitor devolve
    /// a Home, não a página. A pausa é o tempo de a primeira terminar de sair.
    private func lerDoDetalhe(_ livro: LeituraAberta) {
        detalhe = nil
        Task {
            try? await Task.sleep(for: .milliseconds(320))
            open(livro.book, de: livro.origem)
        }
    }

    /// `origem` diz qual capa foi tocada; o id do zoom sai dela, o mesmo que
    /// a capa passou para `origemDoZoom`. Livro bloqueado vai para o paywall
    /// e não usa o zoom.
    ///
    /// Sem analytics aqui: toque duplo chama isto duas vezes antes do leitor
    /// subir. Quem registra é o leitor (`book_opened`) ou o paywall.
    private func open(_ book: Book, de origem: OrigemDaLeitura) {
        guard Store.shared.podeLer(book) else {
            abrirPaywall(.livroBloqueado(bookId: book.id, origem: origem,
                                         temProgresso: ReadingProgress.shared.started(book.id)))
            return
        }
        origemDoZoom = origem.idDoZoom(book)

        // Tudo já no aparelho: abre no mesmo quadro, sem espera nenhuma.
        let movimentoPronto = !book.animado
            || Pacotes.shared.estado(book.spreadMotionTag) == .pronto
        if Pacotes.shared.estado(book.artTag) == .pronto, movimentoPronto {
            reading = LeituraAberta(book: book, origem: origem)
            return
        }

        Task {
            // A tela de preparo só aparece se a espera for de verdade. Livro
            // animado reaberto tem o pacote no aparelho, mas passa pela
            // verificação — sem este atraso ela piscava a cada reabertura.
            let mostrarEspera = Task {
                try? await Task.sleep(for: .milliseconds(150))
                if !Task.isCancelled { preparando = book }
            }
            // Livro animado espera as páginas em movimento TAMBÉM, na mesma
            // tela de preparo: abrir com a arte parada e ver a página começar
            // a se mexer segundos depois parecia defeito. Agora o leitor sobe
            // com a primeira página já se mexendo.
            async let arte = Pacotes.shared.garantir(book.artTag)
            async let movimento = esperarMovimento(de: book)
            let chegou = await arte
            _ = await movimento
            mostrarEspera.cancel()
            preparando = nil
            if chegou {
                // Livro que a criança abriu é o último que o iOS deve apagar.
                Pacotes.shared.preservar(book.artTag)
                reading = LeituraAberta(book: book, origem: origem)
            } else {
                semRede = book
            }
        }
    }

    /// Quanto o preparo espera pelo motion antes de abrir sem ele. Com rede
    /// ruim, uma criança olhando uma barra por um minuto desiste do livro; o
    /// motion é enfeite e nunca pode impedir a leitura. Passado isto, o livro
    /// abre e as páginas começam a se mexer quando o pacote chegar.
    private static let esperaMaximaDoMovimento: Duration = .seconds(25)

    /// Baixa as páginas em movimento e já deixa pronto o clipe da página em
    /// que o livro vai abrir — senão o primeiro vídeo ainda levaria o tempo
    /// de sair do pacote para um arquivo. Não falha: sem motion, o livro abre
    /// com a arte parada, como sempre abriu.
    private func esperarMovimento(de book: Book) async -> Bool {
        guard book.animado else { return true }
        let tag = book.spreadMotionTag
        let busca = Task { () -> Bool in
            guard await Pacotes.shared.garantir(tag) else { return false }
            let salvo = ReadingProgress.shared.spread(for: book.id)
            let indice = min(max(0, salvo), book.spreads.count - 1)
            if book.spreads.indices.contains(indice) {
                _ = await MotionStore.shared.url(asset: book.spreads[indice].motionAsset,
                                                 tag: tag)
            }
            return true
        }
        // O que acabar primeiro: o pacote ou o limite. Não dá para usar um
        // grupo de tarefas aqui: ele espera TODOS os filhos antes de devolver,
        // e esperar um download não obedece cancelamento — o limite nunca
        // venceria. O download segue mesmo se o limite ganhar; só o livro
        // para de esperar por ele.
        final class Largada { var decidida = false }
        let largada = Largada()
        return await withCheckedContinuation { (fim: CheckedContinuation<Bool, Never>) in
            let relogio = Task {
                try? await Task.sleep(for: Self.esperaMaximaDoMovimento)
                guard !largada.decidida else { return }
                largada.decidida = true
                Diagnostico.rastro("preparo: motion de \(book.id) passou do limite, abrindo sem ele")
                fim.resume(returning: false)
            }
            Task {
                let chegou = await busca.value
                guard !largada.decidida else { return }
                largada.decidida = true
                relogio.cancel()
                fim.resume(returning: chegou)
            }
        }
    }

    /// Uma barra só para a espera inteira. O peso segue o tamanho: a arte são
    /// ~5 MB e as páginas em movimento ~19 MB, então a barra anda no ritmo do
    /// que falta de verdade.
    private func estadoDoPreparo(_ book: Book) -> Pacotes.Estado {
        let arte = Pacotes.shared.estado(book.artTag)
        guard book.animado else { return arte }
        func fracao(_ estado: Pacotes.Estado) -> Double {
            switch estado {
            case .pronto:             return 1
            case .baixando(let f):    return f
            case .ausente, .semRede:  return 0
            }
        }
        let total = fracao(arte) * 0.2
            + fracao(Pacotes.shared.estado(book.spreadMotionTag)) * 0.8
        return total >= 1 ? .pronto : .baixando(total)
    }

    /// Com o paywall já subindo, um segundo toque não troca a origem dele.
    private func abrirPaywall(_ origem: OrigemDoPaywall) {
        guard !mostrandoPaywall else { return }
        origemDoPaywall = origem
        mostrandoPaywall = true
    }
}
