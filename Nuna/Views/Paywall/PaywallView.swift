//
//  PaywallView.swift
//  Nuna
//
//  Assinatura. A tela abre direto, sem portão: ver os planos não compra
//  nada. O portão parental, que a categoria Kids exige antes de qualquer
//  compra, aparece no toque em Assinar — e só ele dispara a compra.
//
//  Paywall próprio em vez de `SubscriptionStoreView`: a view da Apple resolve
//  a compra, mas traz o visual dela, e a UI do Nuna é Papel e Tinta com um
//  acento só. Toda a lógica de StoreKit mora em `Store`; aqui é só tela.
//
//  Três regras da revisão da App Store (diretriz 3.1.2) moldam o layout:
//    - o preço COBRADO é o número mais forte do cartão. O equivalente por mês
//      do anual é linha secundária — invertido, a Apple recusa;
//    - o texto de renovação automática fica colado no botão, com duração e
//      preço reais vindos da loja, e não perdido no fim da rolagem;
//    - Restaurar, Termos e Privacidade ficam no rodapé fixo, sempre à vista.
//
//  Vidro só nos controles que flutuam (fechar, botão de assinar). Preço e
//  texto legal assentam em Papel liso: material translúcido atrás de letra
//  miúda não lê.
//

import SwiftUI
import StoreKit

// MARK: - Paywall

struct PaywallView: View {
    let origem: OrigemDoPaywall
    var onClose: () -> Void

    enum Plano: Hashable {
        case anual, mensal

        var titulo: LocalizedStringResource { self == .anual ? "Yearly" : "Monthly" }
        var periodo: LocalizedStringResource { self == .anual ? "per year" : "per month" }
        var analitico: PlanoDaAssinatura { self == .anual ? .annual : .monthly }
    }

    struct Aviso {
        let titulo: String
        let mensagem: String
    }

    @Environment(\.verticalSizeClass) private var vSize
    @Environment(\.openURL) private var openURL
    @Environment(\.postura) private var postura

    /// Anual pré-selecionado: é o plano com teste grátis e o de menor preço
    /// por mês.
    @State private var plano: Plano = .anual
    @State private var comprando = false
    @State private var restaurando = false
    @State private var pendente = false
    /// Até a primeira tentativa desta tela terminar, falta de plano é espera,
    /// não erro — sem isto a falha do lançamento pisca antes da nova busca.
    @State private var tentouCarregar = false
    @State private var aviso: Aviso?
    @State private var mostrandoAviso = false
    @State private var fechou = false
    @State private var mostrandoPortao = false
    /// Marcado pelo portão ao acertar a conta; a compra só começa depois que
    /// o portão terminou de sair, senão a folha da App Store tenta subir por
    /// cima de uma tela que ainda está descendo.
    @State private var portaoLiberou = false
    /// O que o portão vai liberar: a compra ou um link para fora do app.
    @State private var pedido: DepoisDoPortao = .assinar
    @State private var registrouVisita = false
    @State private var abertoEm = Date()

    private var store: Store { .shared }

    /// No iPad a tela passa de 1000pt; cartão de preço esticado nessa largura
    /// parece formulário. 520 lê como folha — e cabe numa metade do Duo.
    private static let larguraMaxima: CGFloat = 520

    /// Letra do texto legal. Abaixo da `legenda` de propósito: é leitura de
    /// adulto, e o piso de 24pt vale para o texto que a criança acompanha.
    private static let letraMiuda = Font.system(size: 13, weight: .regular, design: .rounded)

    private static let raioCartao: CGFloat = 20

    private static let textoPendente: LocalizedStringResource = "Request sent to a parent for approval"

    private static let beneficios: [(icone: String, texto: LocalizedStringResource)] = [
        ("books.vertical.fill", "Every book unlocked"),
        ("sparkles",            "New books at no extra cost"),
        ("person.2.fill",       "Family Sharing included"),
    ]

    // MARK: Seleção

    /// Os dois planos ou nenhum, a mesma regra da `Store`: com um só, a tela
    /// pré-selecionaria o anual e compararia com um mensal que não existe.
    private var prontos: Bool { store.anual != nil && store.mensal != nil }

    private func produto(de plano: Plano) -> Product? {
        switch plano {
        case .anual:  return store.anual
        case .mensal: return store.mensal
        }
    }

    private var comTeste: Bool { plano == .anual && store.trialEligible }

    private var rotuloCTA: LocalizedStringResource { comTeste ? "Start 7-day free trial" : "Subscribe" }

    // MARK: View

    var body: some View {
        corpo
        .background(UITokens.surface)
        .safeAreaInset(edge: .top, spacing: 0) { barra }
        .sensoryFeedback(.selection, trigger: plano)
        .task { await prepararLoja() }
        // `corpo` é if/else: trocar de pose no Duo, ou o portão cobrindo e
        // descobrindo a tela, roda o onAppear de novo.
        .onAppear { registrarVisita() }
        // Cobre o que chega sem toque nesta tela: o "sim" do responsável no
        // Pedir Compra, o Restaurar, a assinatura feita em outro aparelho.
        // Depois de uma compra este onChange pode chegar antes do `.sucesso`.
        .onChange(of: store.isPremium, initial: true) { _, premium in
            guard premium else { return }
            fechar(comprando ? .purchaseCompleted
                   : restaurando ? .restored
                   : .premiumActivatedElsewhere)
        }
        .alert(aviso?.titulo ?? "", isPresented: $mostrandoAviso, presenting: aviso) { _ in
            Button("OK", role: .cancel) {}
        } message: { aviso in
            Text(aviso.mensagem)
        }
        // Cada toque em Assinar pede a conta de novo: lembrar a resposta
        // deixaria a criança que pega o aparelho depois comprar com um toque.
        // Terms e Privacy também passam por aqui — o paywall abre sem portão,
        // e a diretriz 1.3 não aceita link para fora sem ele.
        .fullScreenCover(isPresented: $mostrandoPortao, onDismiss: aposPortao) {
            ParentalGate(
                proposito: pedido.proposito,
                onPass: {
                    portaoLiberou = true
                    mostrandoPortao = false
                },
                onCancel: { mostrandoPortao = false }
            )
            .medirPostura()
        }
        // Gesto de "voltar" do VoiceOver fecha, igual ao portão.
        .accessibilityAction(.escape) { fechar(.dismissed) }
    }

    // MARK: Barra

    /// Mesmo botão e mesmo lugar do portão: o X não troca de canto quando o
    /// portão sobe por cima desta tela.
    private var barra: some View {
        HStack {
            Button { fechar(.dismissed) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(UITokens.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Close")

            Spacer()
        }
        .padding(.horizontal, Space.md)
        .padding(.top, Space.xs)
    }

    // MARK: Layout

    /// Uma coluna com o rodapé preso embaixo; no Duo aberto na horizontal,
    /// duas metades. A da esquerda apresenta (capas, título, benefícios) e a
    /// da direita vende (planos, botão, texto legal) — o botão de assinar e o
    /// texto de renovação ficam juntos, como a revisão pede, e nada disso
    /// pousa na dobra. Plano escolhido e compra em andamento sobrevivem à
    /// troca de pose: moram nesta view, não nas colunas.
    @ViewBuilder
    private var corpo: some View {
        if postura.duasMetades {
            HStack(spacing: postura.calha) {
                ScrollView {
                    folha {
                        hero
                        cabecalho
                        listaBeneficios
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .defaultScrollAnchor(.center, for: .alignment)

                ScrollView {
                    folha { secaoPlanos }
                }
                .scrollBounceBehavior(.basedOnSize)
                .defaultScrollAnchor(.center, for: .alignment)
                .safeAreaInset(edge: .bottom, spacing: 0) { rodape }
            }
        } else {
            ScrollView {
                folha {
                    // Telefone deitado não tem altura para arte E planos; a arte sai.
                    if vSize != .compact { hero }
                    cabecalho
                    listaBeneficios
                    secaoPlanos
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: 0) { rodape }
        }
    }

    private func folha<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: Space.lg) {
            content()
        }
        .frame(maxWidth: Self.larguraMaxima)
        .padding(.horizontal, Space.lg)
        .padding(.top, Space.xs)
        .padding(.bottom, Space.lg)
        .frame(maxWidth: .infinity)
    }

    /// Três capas em leque. Mostra o que a assinatura abre com a arte dos
    /// próprios livros, sem ilustração feita só para vender.
    private var hero: some View {
        ZStack {
            capa("a-chuva-da-nuna", largura: 76)
                .rotationEffect(.degrees(-9))
                .offset(x: -64, y: 10)
            capa("a-praia-da-nuna", largura: 76)
                .rotationEffect(.degrees(9))
                .offset(x: 64, y: 10)
            capa("o-quintal-da-nuna", largura: 92)
        }
        .frame(height: 150)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func capa(_ id: String, largura: CGFloat) -> some View {
        let forma = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Image("cover_\(id)")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: largura, height: largura * 1.5)
            .clipShape(forma)
            .overlay { forma.strokeBorder(UITokens.ink.opacity(0.10), lineWidth: 0.5) }
            .shadow(color: UITokens.ink.opacity(0.16), radius: 10, x: 0, y: 6)
    }

    private var cabecalho: some View {
        VStack(spacing: Space.xs) {
            Text("All of Nuna's stories")
                .font(TypeScale.titulo)
                .foregroundStyle(UITokens.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text("The whole library, to read together.")
                .font(TypeScale.ui)
                .foregroundStyle(UITokens.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    /// Bloco centrado, linhas alinhadas à esquerda: ícones em coluna leem como
    /// lista; centrar cada linha faria os ícones dançarem.
    private var listaBeneficios: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ForEach(Self.beneficios, id: \.icone) { item in
                HStack(spacing: Space.sm) {
                    Image(systemName: item.icone)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(UITokens.accent)
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)

                    Text(item.texto)
                        .font(TypeScale.ui)
                        .foregroundStyle(UITokens.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Planos

    @ViewBuilder
    private var secaoPlanos: some View {
        if let anual = store.anual, let mensal = store.mensal {
            VStack(spacing: Space.sm) {
                cartao(.anual, produto: anual)
                cartao(.mensal, produto: mensal)
            }
            // folga para os selos do anual, que montam na borda do cartão
            .padding(.top, Space.xs)
            .disabled(comprando)
        } else if store.carregandoProdutos || !tentouCarregar {
            carregandoPlanos
        } else {
            falhaPlanos(store.erroProdutos ?? String(localized: "Couldn't load the plans right now."))
        }
    }

    /// Cartão chapado de Papel claro, não vidro: aqui o adulto lê preço, e
    /// preço lê melhor sobre campo liso — o mesmo material das teclas do
    /// portão.
    private func cartao(_ p: Plano, produto: Product) -> some View {
        let selecionado = plano == p
        let forma = RoundedRectangle(cornerRadius: Self.raioCartao, style: .continuous)

        return Button {
            guard p != plano else { return }
            Analytics.shared.track(.planSelected(plano: p.analitico,
                                                 trialEligible: store.trialEligible, origem: origem))
            withAnimation(.snappy(duration: 0.25)) { plano = p }
        } label: {
            HStack(spacing: Space.sm) {
                Image(systemName: selecionado ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(selecionado ? UITokens.accent : UITokens.inkSecondary.opacity(0.45))

                VStack(alignment: .leading, spacing: 2) {
                    Text(p.titulo)
                        .font(TypeScale.ui.weight(.semibold))
                        .foregroundStyle(UITokens.ink)
                    detalhe(p, produto: produto)
                        .font(TypeScale.legenda)
                        .foregroundStyle(UITokens.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Space.xs)

                // O valor cobrado nunca encolhe nem quebra: é ele que a
                // revisão confere, e é ele que vem na fatura.
                VStack(alignment: .trailing, spacing: 0) {
                    Text(produto.displayPrice)
                        .font(TypeScale.ui.weight(.bold))
                        .foregroundStyle(UITokens.ink)
                        .monospacedDigit()
                    Text(p.periodo)
                        .font(TypeScale.legenda)
                        .foregroundStyle(UITokens.inkSecondary)
                }
                .fixedSize()
            }
            .padding(Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                forma.fill(UITokens.surfaceRaised)
                forma.fill(UITokens.accentSuave.opacity(selecionado ? 0.18 : 0))
            }
            .overlay {
                forma.strokeBorder(selecionado ? UITokens.accent : UITokens.ink.opacity(0.10),
                                   lineWidth: selecionado ? 2 : 1)
            }
            .contentShape(forma)
        }
        .buttonStyle(CartaoPlanoStyle())
        .accessibilityLabel(rotuloAcessivel(p, produto: produto))
        .accessibilityAddTraits(selecionado ? .isSelected : [])
        .overlay(alignment: .topTrailing) {
            if p == .anual && (economiaAnual != nil || store.trialEligible) {
                HStack(spacing: Space.xxs) {
                    if let economia = economiaAnual {
                        selo("Save \(economia)%", cor: UITokens.ink)
                    }
                    if store.trialEligible {
                        selo("7 days free", cor: UITokens.accentSuave,
                             corDoTexto: UITokens.ink)
                    }
                }
                .offset(y: -11)
                .padding(.trailing, Space.md)
                .accessibilityHidden(true)   // já entra no rótulo do cartão
            }
        }
    }

    private func detalhe(_ p: Plano, produto: Product) -> Text {
        switch p {
        case .anual:
            let porMes = (produto.price / 12).formatted(produto.priceFormatStyle)
            return Text("Just \(porMes) per month")
        case .mensal:
            return Text("Billed every month")
        }
    }

    /// Uma frase inteira por combinação. Fragmentos como ", save %lld%%"
    /// virariam chaves com nomes iguais aos das versões sem vírgula, e o
    /// Xcode 27 recusa quando geraria dois símbolos Swift com o mesmo nome.
    private func rotuloAcessivel(_ p: Plano, produto: Product) -> Text {
        let titulo = String(localized: p.titulo)
        let periodo = String(localized: p.periodo)
        let precoPeriodo = "\(produto.displayPrice) \(periodo)"
        if p == .mensal {
            return Text("\(titulo) plan, \(precoPeriodo), billed every month")
        }
        let porMes = (produto.price / 12).formatted(produto.priceFormatStyle)
        switch (economiaAnual, store.trialEligible) {
        case (nil, false):
            return Text("\(titulo) plan, \(precoPeriodo), just \(porMes) per month")
        case (nil, true):
            return Text("\(titulo) plan, \(precoPeriodo), just \(porMes) per month, 7 days free")
        case (let saving?, false):
            return Text("\(titulo) plan, \(precoPeriodo), just \(porMes) per month, save \(saving)%")
        case (let saving?, true):
            return Text("\(titulo) plan, \(precoPeriodo), just \(porMes) per month, save \(saving)%, 7 days free")
        }
    }

    /// Quanto o anual sai mais barato que doze meses do mensal, em
    /// porcentagem inteira. Vem dos preços reais da loja, então acompanha
    /// cada país e cada mudança de preço sem tocar no código.
    ///
    /// Arredonda para BAIXO: prometer 34% quando a conta dá 33,6% é o tipo
    /// de exagero que a revisão (diretriz 3.1.2) recusa. Abaixo de 5% o selo
    /// some — "Economize 2%" mais afasta do que convence.
    private var economiaAnual: Int? {
        guard let anual = store.anual, let mensal = store.mensal,
              mensal.price > 0 else { return nil }
        let doseMeses = mensal.price * 12
        var fracao = (doseMeses - anual.price) / doseMeses * 100
        var inteira = Decimal()
        NSDecimalRound(&inteira, &fracao, 0, .down)
        let porcentagem = NSDecimalNumber(decimal: inteira).intValue
        return porcentagem >= 5 ? porcentagem : nil
    }

    /// Cor cheia, não vidro: é marcação sobre Papel, não controle. Economia
    /// em Tinta e teste em acento, para os dois selos não virarem um só.
    private func selo(_ texto: LocalizedStringKey, cor: Color,
                      corDoTexto: Color = UITokens.inkOnArt) -> some View {
        Text(texto)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(corDoTexto)
            .padding(.horizontal, Space.xs)
            .padding(.vertical, 3)
            .background(cor, in: .capsule)
            .fixedSize()
    }

    private var carregandoPlanos: some View {
        VStack(spacing: Space.sm) {
            ProgressView()
                .tint(UITokens.inkSecondary)
            Text("Loading plans…")
                .font(TypeScale.legenda)
                .foregroundStyle(UITokens.inkSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 164)
        .accessibilityElement(children: .combine)
    }

    private func falhaPlanos(_ mensagem: String) -> some View {
        VStack(spacing: Space.md) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(UITokens.inkSecondary)
                .accessibilityHidden(true)

            Text(mensagem)
                .font(TypeScale.ui)
                .foregroundStyle(UITokens.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await store.carregarProdutos(contexto: .paywallRetry) }
            } label: {
                Label("Try again", systemImage: "arrow.clockwise")
                    .font(TypeScale.ui.weight(.medium))
            }
            .buttonStyle(.glass)
            .tint(UITokens.accent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, minHeight: 164)
    }

    // MARK: Rodapé

    private var rodape: some View {
        VStack(spacing: Space.sm) {
            if pendente {
                Label {
                    Text(Self.textoPendente)
                } icon: {
                    Image(systemName: "hourglass")
                }
                .font(TypeScale.legenda.weight(.medium))
                .foregroundStyle(UITokens.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
            }

            botaoAssinar

            // Sem produto não há preço real para declarar; melhor calar do
            // que escrever um valor que a loja não confirmou.
            if prontos, let item = produto(de: plano) {
                divulgacao(plano, produto: item)
                    .font(Self.letraMiuda)
                    .foregroundStyle(UITokens.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            linksLegais
        }
        .frame(maxWidth: Self.larguraMaxima)
        .padding(.horizontal, Space.lg)
        .padding(.top, Space.sm)
        .padding(.bottom, Space.xs)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) { fundoRodape }
        .animation(.easeInOut(duration: 0.2), value: pendente)
    }

    /// Papel liso atrás do texto legal, com um degradê curto em cima para os
    /// planos sumirem por baixo em vez de serem cortados numa linha seca.
    private var fundoRodape: some View {
        UITokens.surface
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .top) {
                LinearGradient(colors: [UITokens.surface.opacity(0), UITokens.surface],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: Space.lg)
                    .offset(y: -Space.lg)
                    .allowsHitTesting(false)
            }
    }

    private var botaoAssinar: some View {
        Button(action: pedirPortao) {
            ZStack {
                // o texto segura a largura enquanto o indicador gira, senão
                // o botão encolhe e salta embaixo do dedo
                Text(rotuloCTA)
                    .opacity(comprando ? 0 : 1)
                if comprando {
                    ProgressView()
                        .tint(UITokens.inkOnArt)
                }
            }
            .font(TypeScale.ui.weight(.semibold))
            // largura DENTRO do rótulo, senão a cápsula de vidro não estica
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(UITokens.accent)
        .controlSize(.large)
        .disabled(!prontos || comprando || restaurando)
        .accessibilityLabel(comprando ? Text("Processing subscription") : Text(rotuloCTA))
    }

    /// Texto de renovação automática: plano, duração, preço real da loja e
    /// como cancelar. Com teste, diz com todas as letras que os 7 dias viram
    /// assinatura paga — surpresa na fatura vira reembolso e nota baixa.
    private func divulgacao(_ p: Plano, produto: Product) -> Text {
        let preco = produto.displayPrice
        switch p {
        case .anual where store.trialEligible:
            return Text("Free for 7 days, then \(preco) per year. Payment is charged to your Apple Account, and the subscription renews automatically unless canceled at least 24 hours before the trial ends. Cancel anytime in Settings.")
        case .anual:
            return Text("Yearly subscription for \(preco) per year. Payment is charged to your Apple Account, and the subscription renews automatically unless canceled at least 24 hours before renewal. Cancel anytime in Settings.")
        case .mensal:
            return Text("Monthly subscription for \(preco) per month. Payment is charged to your Apple Account, and the subscription renews automatically unless canceled at least 24 hours before renewal. Cancel anytime in Settings.")
        }
    }

    /// Numa linha quando cabe. Em 320pt a linha pede mais que a largura e vira
    /// duas, com Restaurar em cima — nunca quebra no meio de um link.
    private var linksLegais: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.xxs) {
                botaoRestaurar
                separador
                linkTermos
                separador
                linkPrivacidade
            }
            VStack(spacing: 0) {
                botaoRestaurar
                HStack(spacing: Space.xxs) {
                    linkTermos
                    separador
                    linkPrivacidade
                }
            }
        }
        .font(Self.letraMiuda.weight(.medium))
        .lineLimit(1)
    }

    private var botaoRestaurar: some View {
        Button(action: restaurar) {
            Text(restaurando ? "Restoring…" : "Restore Purchases")
                .foregroundStyle(UITokens.inkSecondary)
                .padding(.vertical, Space.xxs)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(restaurando || comprando)
    }

    private var linkTermos: some View {
        Button { pedirPortao(abrindo: Store.Links.termos) } label: {
            Text("Terms of Use")
                .foregroundStyle(UITokens.inkSecondary)
                .padding(.vertical, Space.xxs)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Asks a math question, then opens outside the app")
    }

    private var linkPrivacidade: some View {
        Button { pedirPortao(abrindo: Store.Links.privacidade) } label: {
            Text("Privacy")
                .foregroundStyle(UITokens.inkSecondary)
                .padding(.vertical, Space.xxs)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Privacy Policy")
        .accessibilityHint("Asks a math question, then opens outside the app")
    }

    private var separador: some View {
        Text(verbatim: "·")
            .foregroundStyle(UITokens.inkSecondary)
            .accessibilityHidden(true)
    }

    // MARK: Ações

    /// `onClose` uma vez só: a compra que dá certo fecha pelo resultado E pela
    /// mudança de `isPremium`, e fechar duas vezes o mesmo cover é bug à espera.
    /// A mesma trava faz o `paywall_closed` sair uma vez por apresentação.
    private func fechar(_ motivo: MotivoDoFechamento) {
        guard !fechou else { return }
        fechou = true
        // Quem já assina fecha antes do onAppear; a visita vem antes do fim.
        registrarVisita()
        Analytics.shared.track(.paywallClosed(
            origem: origem, motivo: motivo, planosProntos: prontos, plano: plano.analitico,
            pendente: pendente, duracao: Date.now.timeIntervalSince(abertoEm)))
        onClose()
    }

    /// Uma vez por apresentação.
    private func registrarVisita() {
        guard !registrouVisita else { return }
        registrouVisita = true
        abertoEm = .now
        Analytics.shared.track(.paywallViewed(origem: origem, planosProntos: prontos,
                                              trialEligible: store.trialEligible))
    }

    /// A `Store` nasce no lançamento; chamar `start()` de novo não faz nada, e
    /// garante a loja viva quando a tela abre por outro caminho (a prévia do
    /// Xcode, por exemplo). Se o lançamento foi sem internet, a busca é refeita
    /// aqui — sem isto o paywall ficaria sem planos até reiniciar o app.
    private func prepararLoja() async {
        await store.start()
        if !prontos && !store.carregandoProdutos {
            await store.carregarProdutos(contexto: .paywallOpen)
        } else if prontos {
            // A elegibilidade ao teste pode ter mudado desde o lançamento:
            // outra conta Apple, ou um teste usado em outro aparelho.
            await store.atualizarAssinatura(motivo: .paywallOpen)
        }
        tentouCarregar = true
    }

    private func pedirPortao() {
        guard prontos, !comprando, !restaurando else { return }
        Analytics.shared.track(.subscribeTapped(plano: plano.analitico,
                                                variante: comTeste ? .freeTrial : .subscribe,
                                                origem: origem))
        pedido = .assinar
        portaoLiberou = false
        mostrandoPortao = true
    }

    /// Terms e Privacy. Sem as travas da compra: ler os termos não depende
    /// dos planos terem carregado.
    private func pedirPortao(abrindo url: URL) {
        guard !mostrandoPortao else { return }
        pedido = .abrir(url)
        portaoLiberou = false
        mostrandoPortao = true
    }

    private func aposPortao() {
        guard portaoLiberou else { return }
        portaoLiberou = false
        switch pedido {
        case .assinar:         assinar()
        case .abrir(let url):  openURL(url)
        }
    }

    /// Só chamada depois do portão: nenhum outro caminho compra.
    private func assinar() {
        guard prontos, let item = produto(de: plano), !comprando else { return }
        // Antes da compra: ela confere a assinatura, e a elegibilidade ao
        // teste já vira `false` quando o `.sucesso` volta.
        let planoDaCompra = plano.analitico
        let comTesteNaCompra = comTeste
        comprando = true
        pendente = false

        Task {
            defer { comprando = false }
            do {
                switch try await store.comprar(item) {
                case .sucesso:
                    Analytics.shared.track(.purchaseCompleted(
                        plano: planoDaCompra, comTeste: comTesteNaCompra, origem: origem))
                    fechar(.purchaseCompleted)
                case .pendente:
                    // Pedir Compra: o responsável aprova no aparelho dele, e o
                    // "sim" chega pela escuta da `Store` — o `onChange` fecha.
                    Analytics.shared.track(.purchasePending(
                        plano: planoDaCompra, comTeste: comTesteNaCompra, origem: origem))
                    pendente = true
                    AccessibilityNotification.Announcement(String(localized: Self.textoPendente)).post()
                case .cancelado:
                    Analytics.shared.track(.purchaseCancelled(
                        plano: planoDaCompra, comTeste: comTesteNaCompra, origem: origem))
                }
            } catch {
                Analytics.shared.track(.purchaseFailed(
                    plano: planoDaCompra, comTeste: comTesteNaCompra, origem: origem,
                    erro: Store.categoriaDoErro(error)))
                avisar(titulo: "Couldn't subscribe", error)
            }
        }
    }

    private func restaurar() {
        guard !restaurando else { return }
        Analytics.shared.track(.restoreTapped(tela: .paywall, origem: origem))
        restaurando = true

        Task {
            defer { restaurando = false }
            do {
                let concluiu = try await store.restaurar()
                // A tela pode já ter fechado; a tarefa segue e registra uma vez.
                Analytics.shared.track(.restoreFinished(
                    tela: .paywall,
                    resultado: !concluiu ? .cancelled
                        : store.isPremium ? .subscriptionFound : .noSubscriptionFound,
                    erro: nil, origem: origem))
                // Com assinatura, o `onChange` de `isPremium` fecha a tela — mas
                // pode rodar só depois do `defer` baixar `restaurando`, e aí o
                // motivo sairia errado. Fechar aqui também; a trava de
                // `fechar` deixa valer só o primeiro.
                // Sem assinatura, o toque não pode terminar em silêncio.
                if store.isPremium {
                    fechar(.restored)
                } else {
                    aviso = Aviso(
                        titulo: String(localized: "No subscription found"),
                        mensagem: String(localized: "This Apple Account doesn't have an active Nuna subscription. If someone else in your family subscribed, make sure Family Sharing is turned on in Settings.")
                    )
                    mostrandoAviso = true
                }
            } catch {
                Analytics.shared.track(.restoreFinished(
                    tela: .paywall, resultado: .failed,
                    erro: Store.categoriaDoErro(error), origem: origem))
                avisar(titulo: "Couldn't restore purchases", error)
            }
        }
    }

    private func avisar(titulo: LocalizedStringResource, _ error: Error) {
        guard let mensagem = Self.mensagem(de: error) else { return }
        aviso = Aviso(titulo: String(localized: titulo), mensagem: mensagem)
        mostrandoAviso = true
    }

    /// Mensagem para o adulto, ou nil quando ele só desistiu — cancelar não é
    /// erro e não merece alerta. O texto do StoreKit vem no idioma do sistema,
    /// mas às vezes é técnico demais; aqui trocamos por uma frase reescrita.
    /// Usada também pelo Restaurar da área dos pais.
    static func mensagem(de error: Error) -> String? {
        let generica = String(localized: "The App Store isn't responding right now. Please try again in a moment.")
        switch error {
        case StoreKitError.userCancelled:
            return nil
        case StoreKitError.networkError:
            return String(localized: "Can't connect to the App Store. Check your internet connection and try again.")
        case StoreKitError.notAvailableInStorefront:
            return String(localized: "This subscription isn't available in your country's App Store.")
        case Product.PurchaseError.purchaseNotAllowed:
            return String(localized: "Purchases are turned off on this device. You can allow them in Settings > Screen Time.")
        case is StoreKitError, is Product.PurchaseError:
            return generica
        case let proprio as LocalizedError:
            // Erro da própria `Store` (compra não verificada) já vem com o
            // texto pronto: exibe direto, sem passar pelo catálogo.
            return proprio.errorDescription ?? generica
        default:
            return generica
        }
    }
}

/// O que vem depois do portão do paywall.
private enum DepoisDoPortao {
    case assinar
    case abrir(URL)

    var proposito: PropositoDoPortao {
        switch self {
        case .assinar: .subscribe
        case .abrir:   .externalLink
        }
    }
}

/// Sem vidro, o toque precisa de resposta no próprio cartão: ele cede um
/// pouco sob o dedo, como o cartão da história da semana.
private struct CartaoPlanoStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: configuration.isPressed)
    }
}

// Sem a configuração de StoreKit ativa, a prévia fica em "Carregando planos"
// ou cai no estado de nova tentativa — os dois também precisam ser revisados.
#Preview("Paywall") {
    PaywallView(origem: .cabecalhoDaHome) {}
        .medirPostura()
}
