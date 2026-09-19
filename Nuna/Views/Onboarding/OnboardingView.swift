//
//  OnboardingView.swift
//  Nuna
//
//  Três telas. O título assenta dentro da faixa de Papel da própria arte, e
//  como o fundo do app é o mesmo Papel a emenda some.
//
//  Sem vidro sobre o texto: material translúcido sobre texto de leitura
//  infantil é ilegível.
//

import SwiftUI

struct OnboardingView: View {
    let content: OnboardingContent
    let gatilho: GatilhoDoOnboarding
    var onFinish: (FimDoOnboarding) -> Void

    @State private var index = 0
    @State private var registrouInicio = false
    @State private var iniciadoEm = Date()
    /// A troca de página que vem a seguir foi pelo botão, não pelo arrasto.
    @State private var avancouPeloBotao = false
    @Environment(\.postura) private var postura

    private var page: OnboardingPage { content.pages[index] }
    private var isLast: Bool { index == content.pages.count - 1 }

    var body: some View {
        Group {
            if postura.duasMetades {
                // Duo aberto na horizontal: a arte (2:3, em pé) centrada
                // cairia bem em cima da dobra. Arte numa metade, botões na
                // outra. A página atual mora em `index`, então abrir ou
                // fechar o aparelho não volta o onboarding pro começo.
                HStack(spacing: postura.calha) {
                    illustration
                        .frame(maxWidth: .infinity)
                    controls
                        .frame(maxWidth: 360)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    illustration
                    controls
                }
            }
        }
        .background(UITokens.surface)
        .overlay(alignment: .topTrailing) { skip }
        .animation(.easeInOut(duration: 0.3), value: index)
        // Dobrar o Duo ou girar o iPad troca HStack por VStack, e o onAppear
        // roda de novo no ramo novo. O replay cria outra OnboardingView, com
        // estado zerado, e registra de novo — como deve.
        .onAppear {
            guard !registrouInicio else { return }
            registrouInicio = true
            iniciadoEm = .now
            Analytics.shared.track(.onboardingStarted(
                gatilho: gatilho, paginas: content.pages.count,
                imagensFaltando: content.pages.filter { UIImage(named: $0.image) == nil }.count))
        }
        // `index` sobrevive à troca de pose, então isto só dispara quando a
        // página muda de verdade.
        .onChange(of: index) { antigo, novo in
            Analytics.shared.track(.onboardingPageViewed(
                indice: novo, paginas: content.pages.count,
                direcao: novo > antigo ? .forward : .back,
                metodo: avancouPeloBotao ? .nextButton : .swipe))
            avancouPeloBotao = false
        }
    }

    // MARK: Ilustração + texto na faixa reservada

    private var illustration: some View {
        TabView(selection: $index) {
            ForEach(Array(content.pages.enumerated()), id: \.element.id) { i, p in
                SafeZoneImage(name: p.image, colors: p.colors, bands: p.bands,
                              textPadding: Space.xl) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.title.resolved())
                            .font(TypeScale.titulo)
                            .foregroundStyle(UITokens.ink)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)

                        Text(p.body.resolved())
                            .font(.system(size: 19, weight: .regular, design: .serif))
                            .foregroundStyle(UITokens.inkSecondary)
                            .lineSpacing(3)
                            .lineLimit(3)
                            .minimumScaleFactor(0.75)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
                .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    // MARK: Controles

    private var controls: some View {
        VStack(spacing: Space.lg) {
            dots
            cta
        }
        .padding(.horizontal, Space.xl)
        .padding(.top, Space.md)
        .padding(.bottom, Space.lg)
        .background(UITokens.surface)
    }

    @ViewBuilder
    private var cta: some View {
        // Escalada deliberada: as duas primeiras telas levam um botão quieto,
        // e só a última recebe o acento cheio. Vermelho sólido em toda página
        // brigaria com a ilustração, que é o que a pessoa veio ver.
        if isLast {
            Button(content.cta.resolved()) { onFinish(.concluiu(iniciadoEm: iniciadoEm)) }
                .buttonStyle(.glassProminent)
                .tint(UITokens.accent)
                .controlSize(.large)
                .font(TypeScale.ui.weight(.semibold))
                .frame(maxWidth: .infinity)
        } else {
            Button {
                avancouPeloBotao = true
                withAnimation { index += 1 }
            } label: {
                Label(content.next.resolved(), systemImage: "arrow.forward")
                    .labelStyle(.titleAndIcon)
                    .font(TypeScale.ui.weight(.medium))
            }
            .buttonStyle(.glass)
            .tint(UITokens.accent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
    }

    private var skip: some View {
        Button(content.skip.resolved()) { onFinish(.pulou(pagina: index, iniciadoEm: iniciadoEm)) }
            .font(TypeScale.legenda.weight(.medium))
            .foregroundStyle(UITokens.inkSecondary)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xxs)
            .glassEffect(.regular.interactive(), in: .capsule)
            .padding(.trailing, Space.md)
            .padding(.top, Space.xs)
            .opacity(isLast ? 0 : 1)
            .allowsHitTesting(!isLast)
    }

    private var dots: some View {
        HStack(spacing: Space.xs) {
            ForEach(content.pages.indices, id: \.self) { i in
                Capsule()
                    .fill(i == index ? UITokens.accent : UITokens.inkSecondary.opacity(0.25))
                    .frame(width: i == index ? 20 : 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}
