//
//  ParentsView.swift
//  Nuna
//
//  Área dos pais. Quem lê é um adulto: Papel e Tinta, sem ilustração, o
//  mesmo cartão chapado do paywall e das teclas do portão.
//
//  A aba não tem portão na entrada — ver o estado da assinatura não compra
//  nada. O portão fica no que mexe com dinheiro ou sai do app: Assinar,
//  dentro do paywall; Gerenciar assinatura e os links de Terms e Privacy,
//  aqui (diretriz 1.3: nenhum link para fora sem portão).
//
//  Só entra o que o app já faz de verdade. Idioma e narração ganham linha
//  quando existirem: ajuste que não muda nada ensina o pai a desconfiar da
//  tela inteira.
//

import SwiftUI
import StoreKit

struct ParentsView: View {
    let books: [Book]
    var onUnlock: () -> Void

    @AppStorage("onboardingConcluido") private var onboardingDone = false
    @AppStorage(Analytics.chaveCompartilhar) private var compartilharUso = true

    @State private var restaurando = false
    @State private var aviso: PaywallView.Aviso?
    @State private var mostrandoAviso = false
    @State private var confirmandoRecomeco = false
    @State private var mostrandoPortao = false
    /// O que o portão vai liberar. Guardado antes de ele subir, lido depois
    /// que ele sai.
    @State private var pedido: DepoisDoPortao = .gerenciar
    /// Mesmo esquema do paywall: a folha da Apple (ou o Safari) só sobe
    /// depois que o portão terminou de sair.
    @State private var portaoLiberou = false
    @State private var gerenciando = false

    @Environment(\.openURL) private var openURL

    @Environment(\.postura) private var postura

    private var store: Store { .shared }
    private var progress: ReadingProgress { .shared }

    /// Mesma folha do paywall no iPad: lista esticada em 1000pt vira planilha.
    /// Em duas metades cada uma já é estreita, e o limite sai.
    private static let larguraMaxima: CGFloat = 560
    private static let raioCartao: CGFloat = 20
    private static let larguraIcone: CGFloat = 28

    private var disponiveis: Int { books.filter(\.isAvailable).count }
    private var emAndamento: Int { books.filter { progress.started($0.id) }.count }

    // MARK: View

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                cabecalho
                // Duo aberto na horizontal: assinatura numa metade, leitura e
                // sobre na outra, nenhum cartão atravessando a dobra.
                DuasMetades {
                    secao("Subscription", icon: "sparkles") { assinatura }
                } segunda: {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        secao("Reading", icon: "book.fill") { leitura }
                        secao("About Nuna", icon: "info.circle") { sobre }
                    }
                }
            }
            .frame(maxWidth: postura.duasMetades ? .infinity : Self.larguraMaxima,
                   alignment: .leading)
            .padding(.horizontal, Space.lg)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.xxxl)
            .frame(maxWidth: .infinity)
        }
        .background(UITokens.surface)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
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
        .manageSubscriptionsSheet(isPresented: $gerenciando)
        .confirmationDialog("Restart every book?",
                            isPresented: $confirmandoRecomeco,
                            titleVisibility: .visible) {
            Button("Restart", role: .destructive) {
                // Antes de apagar: depois não há o que contar.
                if emAndamento > 0 {
                    Analytics.shared.track(.readingProgressReset(livrosEmAndamento: emAndamento))
                }
                withAnimation { progress.resetAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every book goes back to the first page.")
        }
        .alert(aviso?.titulo ?? "", isPresented: $mostrandoAviso, presenting: aviso) { _ in
            Button("OK", role: .cancel) {}
        } message: { aviso in
            Text(aviso.mensagem)
        }
    }

    // MARK: Cabeçalho

    /// Mesmo desenho do "Nuna" da Home: trocar de aba não pode parecer
    /// trocar de app.
    private var cabecalho: some View {
        VStack(alignment: .leading, spacing: 4) {
            // sem cadeado: a aba abre sem portão, e o ícone prometeria um
            Text("Grown-ups only")
                .font(TypeScale.legenda.weight(.medium))
                .foregroundStyle(UITokens.inkSecondary)
            Text("For Parents")
                .font(.system(size: 40, weight: .semibold, design: .serif))
                .foregroundStyle(UITokens.ink)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, Space.xs)
    }

    private func secao<C: View>(_ titulo: LocalizedStringResource, icon: String,
                                @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(titulo, icon: icon)
            content()
        }
    }

    // MARK: Assinatura

    @ViewBuilder
    private var assinatura: some View {
        if store.isPremium {
            cartao {
                resumo(icone: "checkmark.seal.fill",
                       titulo: "Subscription active",
                       texto: "Every story is unlocked, including for everyone in your Family Sharing group.")
                divisor
                Button { pedirPortao(.gerenciar) } label: {
                    rotuloLinha("Manage subscription", icone: "creditcard",
                                acessorio: .seta)
                }
                .buttonStyle(LinhaStyle())
                .accessibilityHint("Asks a math question before opening")
            }
        } else {
            cartao {
                resumo(icone: "books.vertical.fill",
                       titulo: "Nuna Premium",
                       texto: textoPremium)

                Button(action: onUnlock) {
                    Text("See plans")
                        .font(TypeScale.ui.weight(.semibold))
                        // largura DENTRO do rótulo, senão a cápsula de vidro não estica
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(UITokens.accent)
                .controlSize(.large)
                .padding(.horizontal, Space.md)
                .padding(.bottom, Space.md)

                divisor
                Button(action: restaurar) {
                    rotuloLinha(restaurando ? "Restoring…" : "Restore Purchases",
                                icone: "arrow.clockwise", acessorio: .nenhum)
                }
                .buttonStyle(LinhaStyle())
                .disabled(restaurando)
            }
        }
    }

    private var textoPremium: LocalizedStringResource {
        store.trialEligible
            ? "Three stories a week are always free. Subscribe to unlock the whole library. The yearly plan starts with a 7-day free trial."
            : "Three stories a week are always free. Subscribe to unlock the whole library."
    }

    // MARK: Leitura

    private var leitura: some View {
        cartao {
            HStack(spacing: 0) {
                numero(emAndamento, "in progress")
                numero(disponiveis,
                       disponiveis == 1 ? "book in the app" : "books in the app")
            }
            // Separador em overlay: dentro do HStack, numa ScrollView, o
            // retângulo não sabe a altura e fica com 10pt.
            .overlay {
                Rectangle()
                    .fill(UITokens.ink.opacity(0.08))
                    .frame(width: 1)
                    .padding(.vertical, Space.md)
                    .accessibilityHidden(true)
            }

            divisorCheio
            Button { confirmandoRecomeco = true } label: {
                rotuloLinha("Restart all books", icone: "arrow.counterclockwise",
                            acessorio: .nenhum)
            }
            .buttonStyle(LinhaStyle())
            .disabled(emAndamento == 0)
            .accessibilityHint("Sends every book back to the first page")

            divisor
            Button {
                withAnimation(.easeInOut(duration: 0.35)) { onboardingDone = false }
            } label: {
                rotuloLinha("Replay the intro", icone: "play.rectangle",
                            acessorio: .seta)
            }
            .buttonStyle(LinhaStyle())
        }
    }

    private func numero(_ valor: Int, _ rotulo: LocalizedStringResource) -> some View {
        VStack(spacing: 2) {
            Text(valor, format: .number)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(UITokens.ink)
                .contentTransition(.numericText())
            Text(rotulo)
                .font(TypeScale.legenda)
                .foregroundStyle(UITokens.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.md)
        .accessibilityElement(children: .combine)
    }

    // MARK: Sobre

    private var sobre: some View {
        cartao {
            compartilharDadosDeUso

            divisor
            Button { pedirPortao(.abrir(Store.Links.termos)) } label: {
                rotuloLinha("Terms of Use", icone: "doc.text", acessorio: .externo)
            }
            .buttonStyle(LinhaStyle())
            .accessibilityHint("Asks a math question, then opens outside the app")

            divisor
            Button { pedirPortao(.abrir(Store.Links.privacidade)) } label: {
                rotuloLinha("Privacy Policy", icone: "hand.raised",
                            acessorio: .externo)
            }
            .buttonStyle(LinhaStyle())
            .accessibilityHint("Asks a math question, then opens outside the app")

            divisor
            rotuloLinha("Version", icone: "info.circle", acessorio: .nenhum,
                        detalhe: versao)
                .accessibilityElement(children: .combine)
        }
    }

    /// Sem portão: desligar só protege, e vem ligado por padrão. Nenhum
    /// evento registra a escolha, em nenhum dos dois sentidos.
    private var compartilharDadosDeUso: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "chart.bar")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(UITokens.accent)
                .frame(width: Self.larguraIcone, height: Self.larguraIcone)
                .accessibilityHidden(true)

            Toggle(isOn: $compartilharUso) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share anonymous usage data")
                        .font(TypeScale.ui)
                        .foregroundStyle(UITokens.ink)
                    Text("Helps us improve Nuna. Never names or anything your child types.")
                        .font(TypeScale.legenda)
                        .foregroundStyle(UITokens.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(UITokens.accent)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .frame(minHeight: 52)
        .onChange(of: compartilharUso) { _, ligado in
            Analytics.shared.definirCompartilhamento(ligado)
        }
    }

    private var versao: String {
        let info = Bundle.main.infoDictionary
        let curta = info?["CFBundleShortVersionString"] as? String ?? "—"
        guard let build = info?["CFBundleVersion"] as? String else { return curta }
        return "\(curta) (\(build))"
    }

    // MARK: Peças

    /// Cartão chapado de Papel claro, como os planos do paywall: lista de
    /// ajuste lê melhor sobre campo liso do que sobre vidro.
    private func cartao<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        let forma = RoundedRectangle(cornerRadius: Self.raioCartao, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(UITokens.surfaceRaised, in: forma)
        // o realce de toque da linha não pode vazar pelos cantos
        .clipShape(forma)
        .overlay { forma.strokeBorder(UITokens.ink.opacity(0.10)) }
    }

    private func resumo(icone: String, titulo: LocalizedStringResource,
                        texto: LocalizedStringResource) -> some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Image(systemName: icone)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(UITokens.accent)
                .frame(width: Self.larguraIcone, height: Self.larguraIcone)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(titulo)
                    .font(TypeScale.ui.weight(.semibold))
                    .foregroundStyle(UITokens.ink)
                Text(texto)
                    .font(TypeScale.legenda)
                    .foregroundStyle(UITokens.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private enum Acessorio { case seta, externo, nenhum }

    private func rotuloLinha(_ titulo: LocalizedStringResource, icone: String,
                             acessorio: Acessorio,
                             detalhe: String? = nil) -> some View {
        HStack(spacing: Space.sm) {
            Image(systemName: icone)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(UITokens.accent)
                .frame(width: Self.larguraIcone, height: Self.larguraIcone)
                .accessibilityHidden(true)

            Text(titulo)
                .font(TypeScale.ui)
                .foregroundStyle(UITokens.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let detalhe {
                Text(detalhe)
                    .font(TypeScale.legenda)
                    .foregroundStyle(UITokens.inkSecondary)
                    .monospacedDigit()
            }

            switch acessorio {
            case .seta:
                seta("chevron.forward")
            case .externo:
                seta("arrow.up.forward")
            case .nenhum:
                EmptyView()
            }
        }
        .padding(.horizontal, Space.md)
        .frame(minHeight: 52)
        .contentShape(.rect)
    }

    private func seta(_ nome: String) -> some View {
        Image(systemName: nome)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(UITokens.inkSecondary.opacity(0.6))
            .accessibilityHidden(true)
    }

    /// Começa depois do ícone, como nas listas do sistema.
    private var divisor: some View {
        Rectangle()
            .fill(UITokens.ink.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, Space.md + Self.larguraIcone + Space.sm)
            .accessibilityHidden(true)
    }

    private var divisorCheio: some View {
        Rectangle()
            .fill(UITokens.ink.opacity(0.08))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    // MARK: Ações

    private func pedirPortao(_ destino: DepoisDoPortao) {
        pedido = destino
        portaoLiberou = false
        mostrandoPortao = true
    }

    private func aposPortao() {
        guard portaoLiberou else { return }
        portaoLiberou = false
        switch pedido {
        case .gerenciar:       gerenciando = true
        case .abrir(let url):  openURL(url)
        }
    }

    private func restaurar() {
        guard !restaurando else { return }
        Analytics.shared.track(.restoreTapped(tela: .parents, origem: nil))
        restaurando = true

        Task {
            defer { restaurando = false }
            do {
                let concluiu = try await store.restaurar()
                Analytics.shared.track(.restoreFinished(
                    tela: .parents,
                    resultado: !concluiu ? .cancelled
                        : store.isPremium ? .subscriptionFound : .noSubscriptionFound,
                    erro: nil, origem: nil))
                // Aqui a tela não fecha sozinha como o paywall: sem aviso, o
                // toque que deu certo terminaria em silêncio.
                aviso = store.isPremium
                    ? PaywallView.Aviso(
                        titulo: String(localized: "Subscription restored"),
                        mensagem: String(localized: "Every story is unlocked on this device."))
                    : PaywallView.Aviso(
                        titulo: String(localized: "No subscription found"),
                        mensagem: String(localized: "This Apple Account doesn't have an active Nuna subscription. If someone else in your family subscribed, make sure Family Sharing is turned on in Settings."))
                mostrandoAviso = true
            } catch {
                Analytics.shared.track(.restoreFinished(
                    tela: .parents, resultado: .failed,
                    erro: Store.categoriaDoErro(error), origem: nil))
                guard let mensagem = PaywallView.mensagem(de: error) else { return }
                aviso = PaywallView.Aviso(titulo: String(localized: "Couldn't restore purchases"),
                                          mensagem: mensagem)
                mostrandoAviso = true
            }
        }
    }
}

/// O que vem depois do portão da área dos pais.
private enum DepoisDoPortao {
    case gerenciar
    case abrir(URL)

    var proposito: PropositoDoPortao {
        switch self {
        case .gerenciar: .manageSubscription
        case .abrir:     .externalLink
        }
    }
}

/// Linha de lista sem vidro: o toque escurece a linha inteira, como nos
/// Ajustes do sistema.
private struct LinhaStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(UITokens.ink.opacity(configuration.isPressed ? 0.06 : 0))
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    ParentsView(books: [], onUnlock: {})
        .medirPostura()
}
