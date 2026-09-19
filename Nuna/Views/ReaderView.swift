//
//  ReaderView.swift
//  Nuna
//
//  Os controles moram no TOPO, não embaixo. A faixa inferior é da história, e
//  vidro translúcido por cima dela deixaria ilegível pra quem tem três anos —
//  além de cortar a segunda linha nas telas mais baixas.
//
//  Guarda o estado que precisa sobreviver à dobra: índice do spread, lado
//  visível, posição do áudio e palavra ativa no read-along. Abrir ou fechar
//  o Duo no meio da leitura só troca o layout — o `ReaderState` é o mesmo, e
//  a criança continua na mesma página.
//
//  Movimento (tempos e transições em `ReaderMotion.swift`):
//    - virada: a página nova entra pelo lado da virada e empurra a velha
//      para fora; depois o texto novo aparece palavra a palavra;
//    - contador rola os números no sentido da virada; a seta tocada pula;
//    - na primeira e na última página, a página "tenta" virar e volta;
//    - vibração leve a cada virada; VoiceOver anuncia página e frase.
//

import SwiftUI

@Observable
final class ReaderState {
    enum Sentido { case frente, tras }

    var spreadIndex: Int
    var side: SpreadView.Side = .left

    /// Sentido da última virada que aconteceu de fato.
    private(set) var sentido: Sentido = .frente
    private(set) var avancos = 0
    private(set) var recuos = 0
    /// Sobe a cada virada: ordena as camadas (a arte nova por cima), dispara
    /// a vibração e reinicia o relógio da revelação do texto.
    var viradas: Int { avancos + recuos }

    /// A página atual ainda não foi revelada palavra a palavra. Liga ao abrir
    /// o livro e a cada virada; o `ReaderView` desliga depois que a revelação
    /// termina, para dobrar ou girar o aparelho não repeti-la.
    var revelarTexto = true

    // MARK: Analytics
    //
    // Nada daqui aparece na tela: tudo fora da observação, para contar
    // página e tempo não redesenhar o livro.

    /// Como o livro abriu em relação ao progresso salvo.
    let retomada: EstadoDaRetomada
    /// Capturado na abertura: assinatura que muda no meio do livro não muda
    /// o que o fechamento conta.
    @ObservationIgnored var motivoDoAcesso: MotivoDoAcesso = .premium
    @ObservationIgnored var aberturaRegistrada = false
    @ObservationIgnored var fechamentoRegistrado = false
    @ObservationIgnored var fimRegistrado = false
    @ObservationIgnored var leuDoComeco = false
    @ObservationIgnored var spreadInicial = 0
    @ObservationIgnored var spreadMaisLonge = 0
    /// `spreadIndex * 2` para a página esquerda, `+ 1` para a direita.
    @ObservationIgnored var paginasVistas: Set<Int> = []
    @ObservationIgnored var empurroes = 0
    @ObservationIgnored var arrastosIgnorados = 0
    @ObservationIgnored var trocasDeLayout = 0
    /// Último layout registrado (`true` = lado a lado). Base da troca.
    @ObservationIgnored var layoutRegistrado: Bool?
    @ObservationIgnored var tempoAberto = RelogioAtivo()
    @ObservationIgnored var tempoNaPagina = RelogioAtivo()
    /// Artes que faltaram nesta abertura: cada uma registra uma vez só.
    @ObservationIgnored var artesAusentes: Set<String> = []

    init(startAt index: Int = 0, retomada: EstadoDaRetomada = .start) {
        spreadIndex = index
        self.retomada = retomada
    }

    var audioPosition: TimeInterval = 0
    var highlightedWord: Int = 0

    /// `true` se a página virou. Na última página não vira, e quem chamou
    /// decide o que mostrar.
    @discardableResult
    func advance(total: Int, compact: Bool) -> Bool {
        if compact && side == .left {
            side = .right
            virou(.frente)
            return true
        }
        guard spreadIndex < total - 1 else { return false }
        spreadIndex += 1
        side = .left
        virou(.frente)
        return true
    }

    @discardableResult
    func back(compact: Bool) -> Bool {
        if compact && side == .right {
            side = .left
            virou(.tras)
            return true
        }
        guard spreadIndex > 0 else { return false }
        spreadIndex -= 1
        side = compact ? .right : .left
        virou(.tras)
        return true
    }

    private func virou(_ novo: Sentido) {
        sentido = novo
        if novo == .frente { avancos += 1 } else { recuos += 1 }
        revelarTexto = true
    }

    /// Lado a lado não existe "página da direita" isolada: o spread 1 já é
    /// o começo, qualquer que seja o lado guardado da pose anterior.
    func isAtStart(compact: Bool) -> Bool {
        spreadIndex == 0 && (!compact || side == .left)
    }

    func isAtEnd(total: Int, compact: Bool) -> Bool {
        spreadIndex == total - 1 && (!compact || side == .right)
    }
}

struct ReaderView: View {
    let book: Book
    let origem: OrigemDaLeitura
    var onClose: (() -> Void)?

    @State private var state: ReaderState
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.scenePhase) private var fase
    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento
    /// Espaço real do leitor. Muda ao abrir, fechar, girar ou dobrar o Duo.
    @State private var tamanho: CGSize = .zero
    /// Altura medida da barra; as zonas de toque começam abaixo dela.
    @State private var alturaBarra: CGFloat = 56
    /// Deslocamento do empurrão na borda do livro.
    @State private var empurrao: CGFloat = 0
    @State private var toquesNaBorda = 0
    /// O vídeo desta página pode tocar. Nasce desligado a cada virada: durante
    /// a troca de spreads a tela já tem duas artes deslizando, e um vídeo
    /// entrando no meio disso vira ruído.
    @State private var motionLiberado = false

    init(book: Book, origem: OrigemDaLeitura, onClose: (() -> Void)? = nil) {
        self.book = book
        self.origem = origem
        self.onClose = onClose
        // retoma de onde parou; se o índice salvo não existir mais (livro
        // atualizado com menos spreads), volta pro começo
        let salvo = ReadingProgress.shared.spread(for: book.id)
        let invalido = salvo >= book.spreads.count
        let retomada: EstadoDaRetomada
        if invalido {
            retomada = .resetInvalid
        } else if salvo == 0 {
            retomada = .start
        } else if salvo == book.spreads.count - 1 {
            retomada = .resumedAtEnd
        } else {
            retomada = .resumed
        }
        // Sem analytics aqui: a folha do leitor roda este init a cada
        // atualização do `RootView`, e os estados extras são descartados.
        _state = State(wrappedValue: ReaderState(
            startAt: invalido ? 0 : salvo,
            retomada: retomada
        ))
    }

    /// Duas páginas quando o spread inteiro cabe tão grande quanto uma página
    /// sozinha caberia, ou quando a dobra corta a tela em pé no meio.
    ///
    /// - Duo aberto na horizontal: `duasMetades`. Mesmo quase quadrado, UMA
    ///   página centrada pousaria em cima da dobra; duas se encontram nela.
    /// - Tela deitada com 1,3:1 ou mais (iPhone, Duo fechado deitado): o
    ///   spread 3:2 fica da altura da tela, e cada página sai do mesmo
    ///   tamanho que sairia sozinha — mostrar as duas não custa nada.
    /// - Em pé, inclusive o Duo aberto na vertical: uma página, o maior
    ///   possível.
    private var ladoALado: Bool { Self.ladoALado(tamanho: tamanho, horizontal: hSize) }

    /// A mesma regra, para quem precisa decidir com um tamanho que ainda não
    /// chegou ao `@State` (a primeira medida).
    private static func ladoALado(tamanho: CGSize, horizontal: UserInterfaceSizeClass?) -> Bool {
        guard tamanho.height > 0 else { return false }
        return Postura(tamanho: tamanho, horizontal: horizontal).duasMetades
            || tamanho.width >= tamanho.height * 1.3
    }

    private var compact: Bool { !ladoALado }

    /// A página atual, SEM subscrito cru. Índice fora da faixa aqui é
    /// "Index out of range": trap do Swift, app fechado na hora e sem diálogo.
    /// Se um dia acontecer, o rastro conta em vez de o app sumir.
    private var spread: Spread {
        let limite = book.spreads.count - 1
        guard state.spreadIndex >= 0, state.spreadIndex <= limite else {
            Diagnostico.rastro(
                "ÍNDICE FORA DA FAIXA: \(state.spreadIndex) em \(book.spreads.count) "
                + "spreads de \(book.id) — usando o mais próximo")
            return book.spreads[min(max(0, state.spreadIndex), max(0, limite))]
        }
        return book.spreads[state.spreadIndex]
    }

    /// Em página única a página ocupa a largura do leitor; lado a lado o
    /// `SpreadView` troca pela largura da tela inteira (ver `comDistancia`).
    private var movimento: MovimentoDaPagina {
        MovimentoDaPagina(
            leitor: state,
            distancia: tamanho.width,
            camada: Double(state.viradas),
            revelarTexto: state.revelarTexto && !reduzirMovimento,
            reduzirMovimento: reduzirMovimento
        )
    }

    var body: some View {
        Group {
            // Nada antes de medir: sem isto o primeiro quadro sai em página
            // única e troca para duas no meio da abertura do livro.
            if tamanho == .zero {
                UITokens.surface
            } else {
                // Sem `.id(spread.n)`: o SpreadView fica, e só a arte e o
                // texto de dentro trocam — cada um com a sua transição.
                SpreadView(spread: spread, side: $state.side,
                           ladoALado: ladoALado, movimento: movimento,
                           motionAtivo: motionLiberado && fase == .active)
            }
        }
        .offset(x: empurrao)
        .fundoDePapel()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { medir($0) }
        .animation(Movimento.trocaDeLayout(reduzir: reduzirMovimento), value: ladoALado)
        // Troca de layout espera 1 s parada: absorve a virada de página única
        // para duas na abertura (antes da medida, `ladoALado` é false) e o
        // redimensionar ao vivo do Stage Manager perto da proporção 1,3.
        // A tarefa mora no Group e reinicia a cada troca de ramo; a base em
        // `layoutRegistrado` faz a repetição não contar duas vezes.
        .task(id: ladoALado) {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, tamanho != .zero, state.aberturaRegistrada,
                  !state.fechamentoRegistrado,
                  let anterior = state.layoutRegistrado, anterior != ladoALado
            else { return }
            registrarTrocaDeLayout(de: anterior)
        }
        .onChange(of: state.spreadIndex) { _, novo in
            ReadingProgress.shared.save(novo, for: book.id)
        }
        // Abrir já conta como "lendo": é o que põe o livro no cartão de
        // continuar da Home, mesmo que a criança pare na página 1.
        .onAppear {
            Diagnostico.rastro("leitor abriu \(book.id) em spread=\(state.spreadIndex) "
                               + "de \(book.spreads.count)")
            ReadingProgress.shared.marcarAberto(book.id)
        }
        // Retrato da leitura ao ir para segundo plano: se o sistema matar o
        // app lá, o `reader_closed` nunca chega. Os relógios param junto.
        // `.inactive` (Central de Controle, notificação) não é sair do livro.
        .onChange(of: fase) { _, nova in
            // Tela apagada ou app em segundo plano: a voz para, e não volta
            // sozinha no meio da frase.
            if nova != .active { Narracao.shared.parar() }
            guard state.aberturaRegistrada, !state.fechamentoRegistrado else { return }
            switch nova {
            case .background:
                state.tempoAberto.pausar()
                state.tempoNaPagina.pausar()
                Analytics.shared.track(.readerBackgrounded(
                    bookId: book.id, origem: origem, indiceDoSpread: state.spreadIndex,
                    indiceMaisLonge: state.spreadMaisLonge, spreads: book.spreads.count,
                    paginasVistas: state.paginasVistas.count, concluido: state.fimRegistrado,
                    duracao: state.tempoAberto.total))
            case .active:
                state.tempoAberto.retomar()
                state.tempoNaPagina.retomar()
            default:
                break
            }
        }
        // Depois de revelada, a página fica revelada. A tarefa reinicia a
        // cada virada, então só a página atual conta.
        .task(id: state.viradas) {
            guard state.revelarTexto else { return }
            try? await Task.sleep(for: .seconds(Movimento.tempoParaRevelar))
            guard !Task.isCancelled else { return }
            state.revelarTexto = false
        }
        // O movimento entra depois que a virada assenta, e some assim que a
        // criança vira de novo. `spread.n` e `state.side` no id: numa página
        // só, mudar de lado é mudar de arte.
        .task(id: "\(state.viradas)|\(spread.n)|\(state.side)") {
            motionLiberado = false
            // A voz da página anterior não atravessa a virada.
            Narracao.shared.parar()
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled else { return }
            motionLiberado = true
            // A voz entra junto com o motion e com as primeiras palavras do
            // texto (que começam a aparecer em 0,5 s).
            lerPagina()
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: state.viradas)
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.3), trigger: toquesNaBorda)
        // Ordem importa: tap zones primeiro (embaixo), top bar por cima.
        // As tap zones tambem recuam da area da barra — Color.clear com
        // allowsHitTesting(false) NAO protege o HStack abaixo, ele so se
        // torna transparente a toque; a barreira precisa ser geometrica.
        .overlay { tapZones }
        .overlay(alignment: .top) { topBar }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { arrasto in
                    let dx = arrasto.translation.width
                    let dy = arrasto.translation.height
                    // só arrasto de lado vira página; puxar para cima ou para
                    // baixo não pode voltar uma página sem querer
                    guard abs(dx) > abs(dy) * 1.5 else {
                        state.arrastosIgnorados += 1
                        return
                    }
                    dx < 0 ? advance(via: .swipe) : goBack(via: .swipe)
                }
        )
    }

    /// A primeira medida chega sem animação: é o leitor aparecendo, não o
    /// aparelho girando.
    private func medir(_ novo: CGSize) {
        guard tamanho != .zero else {
            var semAnimacao = Transaction()
            semAnimacao.disablesAnimations = true
            withTransaction(semAnimacao) { tamanho = novo }
            registrarAbertura(tamanho: novo)
            return
        }
        if Self.ladoALado(tamanho: tamanho, horizontal: hSize)
            != Self.ladoALado(tamanho: novo, horizontal: hSize) {
            Diagnostico.rastro("layout mudou com \(Int(novo.width))x\(Int(novo.height))")
        }
        tamanho = novo
    }

    // MARK: Barra superior — tudo que não é a história vive aqui

    private var topBar: some View {
        HStack(spacing: Space.xs) {
            if onClose != nil {
                iconButton("xmark", label: "Close book", pulso: 0, action: fechar)
            }

            Spacer()

            // Ler em voz alta. Desligar vale para os próximos livros também:
            // é o adulto dizendo "eu leio". Só aparece em inglês — as falas
            // não têm versão nos outros seis idiomas (ver `Narracao`), e um
            // botão sem áudio confunde mais que ajuda.
            if narracao.disponivel {
                iconButton(narracao.ligada ? "speaker.wave.2.fill" : "speaker.slash.fill",
                           label: narracao.ligada ? "Stop reading aloud" : "Read aloud",
                           pulso: 0) {
                    narracao.alternar()
                    if narracao.ligada { lerPagina() }
                }
            }

            Text("\(state.spreadIndex + 1) / \(book.spreads.count)")
                .font(TypeScale.legenda.weight(.medium))
                .foregroundStyle(UITokens.inkSecondary)
                .monospacedDigit()
                // o número rola para cima avançando e para baixo voltando
                .contentTransition(.numericText(countsDown: state.sentido == .tras))
                .padding(.horizontal, Space.sm)
                .padding(.vertical, Space.xxs)
                .glassEffect(.regular, in: .capsule)
                .accessibilityLabel(Text("Page \(state.spreadIndex + 1) of \(book.spreads.count)"))

            iconButton("chevron.backward", label: "Previous page", pulso: state.recuos,
                       action: { goBack(via: .button) })
                .disabled(state.isAtStart(compact: compact))
                .opacity(state.isAtStart(compact: compact) ? 0.35 : 1)

            iconButton("chevron.forward", label: "Next page", pulso: state.avancos,
                       action: { advance(via: .button) })
                .disabled(state.isAtEnd(total: book.spreads.count, compact: compact))
                .opacity(state.isAtEnd(total: book.spreads.count, compact: compact) ? 0.35 : 1)
        }
        .padding(.horizontal, Space.md)
        .padding(.top, Space.xs)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { alturaBarra = $0 }
    }

    /// `pulso` sobe a cada virada no sentido do botão, e o símbolo dá um
    /// pulinho: o toque na zona da página também "aperta" a seta certa.
    private func iconButton(_ symbol: String, label: LocalizedStringKey, pulso: Int,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(UITokens.ink)
                .symbolEffect(.bounce, value: pulso)
                .frame(width: 30, height: 30)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }

    // MARK: Voz

    private var narracao: Narracao { .shared }

    /// Em pé, a página da tela. Deitado, as duas, esquerda antes da direita.
    private func lerPagina() {
        let falas = ladoALado
            ? [spread.falaAsset(.left), spread.falaAsset(.right)]
            : [spread.falaAsset(state.side)]
        narracao.ler(falas)
    }

    // MARK: Zonas de toque
    //
    // Metade esquerda volta, a direita avança. Criança de três anos toca a tela
    // inteira; toque único que só avança faz ela perder a página e não saber
    // voltar. As duas metades têm o mesmo tamanho.
    //
    // As zonas RECUAM da barra superior (padding no topo), senão o toque no X
    // cai na zona esquerda e chama goBack — o botão fica sem efeito no spread 1.
    // A altura é MEDIDA, não fixa: no Duo a barra e a safe area mudam de pose
    // para pose.
    //
    // Lado a lado, cada zona é uma página inteira e a divisa cai na dobra:
    // tocar na página da esquerda volta, na da direita avança.

    private var tapZones: some View {
        HStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { goBack(via: .tapZone) }
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { advance(via: .tapZone) }
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        }
        .padding(.top, alturaBarra + Space.xs)   // folga: menos que isto pega a borda dos botões
    }

    // MARK: Virada

    private func advance(via entrada: EntradaDaVirada) {
        Diagnostico.rastro("virar frente (\(entrada)) de spread=\(state.spreadIndex) "
                           + "lado=\(state.side) ladoALado=\(ladoALado)")
        let virou = withAnimation(Movimento.virada(reduzir: reduzirMovimento)) {
            state.advance(total: book.spreads.count, compact: compact)
        }
        Diagnostico.rastro("→ agora spread=\(state.spreadIndex) lado=\(state.side) virou=\(virou)")
        if virou {
            anunciarPagina()
            registrarVirada(.frente, via: entrada)
        } else {
            empurrarNaBorda(.frente)
        }
    }

    private func goBack(via entrada: EntradaDaVirada) {
        Diagnostico.rastro("virar trás (\(entrada)) de spread=\(state.spreadIndex) "
                           + "lado=\(state.side) ladoALado=\(ladoALado)")
        let virou = withAnimation(Movimento.virada(reduzir: reduzirMovimento)) {
            state.back(compact: compact)
        }
        Diagnostico.rastro("→ agora spread=\(state.spreadIndex) lado=\(state.side) virou=\(virou)")
        if virou {
            anunciarPagina()
            registrarVirada(.tras, via: entrada)
        } else {
            empurrarNaBorda(.tras)
        }
    }

    /// A página anda um pouco na direção pedida e volta. Com Reduzir
    /// Movimento fica só a vibração.
    private func empurrarNaBorda(_ sentido: ReaderState.Sentido) {
        toquesNaBorda += 1
        // Antes do guard: quem usa Reduzir Movimento também empurra a borda.
        state.empurroes += 1
        guard !reduzirMovimento else { return }
        let distancia = sentido == .frente ? -Movimento.empurraoNaBorda : Movimento.empurraoNaBorda
        withAnimation(.snappy(duration: 0.12)) {
            empurrao = distancia
        } completion: {
            withAnimation(.smooth(duration: 0.4)) { empurrao = 0 }
        }
    }

    /// As zonas de toque são invisíveis ao VoiceOver; quem vira pelas setas
    /// ouve a página nova e a frase dela.
    private func anunciarPagina() {
        let frase = compact
            ? (state.side == .left ? spread.left.resolved() : spread.right.resolved())
            : "\(spread.left.resolved()) \(spread.right.resolved())"
        let anuncio = String(localized: "Now on page \(state.spreadIndex + 1) of \(book.spreads.count). \(frase)")
        AccessibilityNotification.PageScrolled(anuncio).post()
    }

    // MARK: Fechar

    /// O X é a única saída (`interactiveDismissDisabled` no `RootView`). Se
    /// um dia houver outra, ela passa por aqui. Não mora no `onDisappear`:
    /// o Group troca de ramo na primeira medida, e o ramo vazio que some
    /// dispararia o fechamento com o livro recém-aberto.
    private func fechar() {
        if state.aberturaRegistrada && !state.fechamentoRegistrado {
            state.fechamentoRegistrado = true
            state.tempoAberto.pausar()
            // Resumo completo: a sessão pode ter girado com o livro parado em
            // segundo plano, e o evento não pode depender de outro.
            Analytics.shared.track(.readerClosed(
                bookId: book.id, origem: origem, acesso: state.motivoDoAcesso,
                indiceInicial: state.spreadInicial, indiceFinal: state.spreadIndex,
                indiceMaisLonge: state.spreadMaisLonge, spreads: book.spreads.count,
                paginasVistas: state.paginasVistas.count,
                avancos: state.avancos, recuos: state.recuos, empurroes: state.empurroes,
                arrastosIgnorados: state.arrastosIgnorados, trocasDeLayout: state.trocasDeLayout,
                concluido: state.fimRegistrado, duracao: state.tempoAberto.total))
            // Depois do registro, para o próprio fechamento ainda levar o layout.
            Analytics.shared.layoutDoLeitor = nil
        }
        // Livro fechado: o pacote de vídeo pode sair do aparelho, mas a arte
        // do livro lido fica na frente da fila de quem permanece.
        Diagnostico.rastro("leitor fechou \(book.id)")
        Narracao.shared.encerrar()
        MotionStore.shared.soltar(tag: book.spreadMotionTag)
        Pacotes.shared.preservar(book.artTag)
        onClose?()
    }

    // MARK: Analytics

    /// Mesma ordem de `Store.podeLer`.
    private var motivoDoAcesso: MotivoDoAcesso {
        if Store.shared.isPremium { return .premium }
        if Store.livrosGratis.contains(book.id) { return .freeBook }
        return .storyOfWeek
    }

    /// Uma vez por abertura, na primeira medida: antes dela não se sabe se o
    /// livro abriu em uma página ou em duas.
    private func registrarAbertura(tamanho novo: CGSize) {
        guard !state.aberturaRegistrada, novo.width > 0, novo.height > 0 else { return }
        state.aberturaRegistrada = true

        // Do tamanho novo, não do `@State` que acabou de ser escrito.
        let lado = Self.ladoALado(tamanho: novo, horizontal: hSize)
        state.layoutRegistrado = lado
        state.motivoDoAcesso = motivoDoAcesso
        state.spreadInicial = state.spreadIndex
        state.leuDoComeco = state.isAtStart(compact: !lado)
        marcarPaginasVistas(lado)
        state.tempoAberto.retomar()
        state.tempoNaPagina.retomar()

        // Antes do registro, para a abertura já levar o layout.
        Analytics.shared.layoutDoLeitor = lado ? .spread : .single
        Analytics.shared.track(.bookOpened(
            book: book, origem: origem, acesso: state.motivoDoAcesso,
            retomada: state.retomada, indiceInicial: state.spreadIndex,
            deitado: novo.width > novo.height,
            duasMetades: Postura(tamanho: novo, horizontal: hSize).duasMetades))
        verificarArte(lado)
    }

    /// Só virada que aconteceu: toque na borda do livro não vira nada. Aqui e
    /// não no `onChange` do spread, que não vê a virada de esquerda para
    /// direita dentro do mesmo spread em página única.
    private func registrarVirada(_ sentido: ReaderState.Sentido, via entrada: EntradaDaVirada) {
        guard state.aberturaRegistrada, !state.fechamentoRegistrado else { return }
        let lado = ladoALado
        let permanencia = state.tempoNaPagina.total
        state.tempoNaPagina = RelogioAtivo()
        state.tempoNaPagina.retomar()
        marcarPaginasVistas(lado)

        Analytics.shared.track(.pageTurned(
            bookId: book.id, direcao: sentido == .frente ? .forward : .back, entrada: entrada,
            indiceDoSpread: state.spreadIndex,
            lado: lado ? .both : (state.side == .left ? .left : .right),
            spreads: book.spreads.count, permanencia: permanencia))

        if sentido == .frente, !state.fimRegistrado,
           state.isAtEnd(total: book.spreads.count, compact: !lado) {
            state.fimRegistrado = true
            registrarFim(.pageTurn)
        }
        verificarArte(lado)
    }

    private func registrarTrocaDeLayout(de anterior: Bool) {
        let lado = ladoALado
        state.layoutRegistrado = lado
        state.trocasDeLayout += 1
        marcarPaginasVistas(lado)

        Analytics.shared.layoutDoLeitor = lado ? .spread : .single
        Analytics.shared.track(.readerLayoutChanged(
            bookId: book.id, deLadoALado: anterior, paraLadoALado: lado,
            deitado: tamanho.width > tamanho.height,
            duasMetades: Postura(tamanho: tamanho, horizontal: hSize).duasMetades,
            indiceDoSpread: state.spreadIndex))

        // Abrir o Duo na última página de quem já virou alguma: a página que
        // faltava aparece sem virada. Sem virada nenhuma é só retomar no fim.
        if !state.fimRegistrado, state.viradas > 0,
           state.isAtEnd(total: book.spreads.count, compact: !lado) {
            state.fimRegistrado = true
            registrarFim(.layoutChange)
        }
        verificarArte(lado)
    }

    /// Nunca na abertura: retomar no último spread lado a lado começa "no
    /// fim" sem ler nada (`resume_state` = `resumed_at_end` conta isso).
    private func registrarFim(_ gatilho: GatilhoDoFim) {
        Analytics.shared.track(.bookCompleted(
            bookId: book.id, origem: origem, acesso: state.motivoDoAcesso, gatilho: gatilho,
            leuDoComeco: state.leuDoComeco, paginasVistas: state.paginasVistas.count,
            recuos: state.recuos, spreads: book.spreads.count, duracao: state.tempoAberto.total))
    }

    private func marcarPaginasVistas(_ lado: Bool) {
        let base = state.spreadIndex * 2
        if lado {
            state.paginasVistas.insert(base)
            state.paginasVistas.insert(base + 1)
        } else {
            state.paginasVistas.insert(base + (state.side == .right ? 1 : 0))
        }
        state.spreadMaisLonge = max(state.spreadMaisLonge, state.spreadIndex)
    }

    /// Arte que falta vira faixas de cor na tela. Conferido aqui, nas
    /// mudanças de página, e não no `SpreadView` ou no `SafeZoneImage`: o
    /// corpo deles roda a cada quadro de animação.
    private func verificarArte(_ lado: Bool) {
        let nome: String
        let variante: VarianteDaArte
        if lado {
            nome = spread.imageName
            variante = .spread
        } else if state.side == .left {
            nome = spread.leftImageName
            variante = .left
        } else {
            nome = spread.rightImageName
            variante = .right
        }
        guard UIImage(named: nome) == nil, state.artesAusentes.insert(nome).inserted else { return }
        Analytics.shared.track(.pageArtFallbackShown(
            bookId: book.id, indiceDoSpread: state.spreadIndex, variante: variante))
    }
}
