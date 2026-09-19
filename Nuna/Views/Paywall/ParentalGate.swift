//
//  ParentalGate.swift
//  Nuna
//
//  Portão parental. A categoria Kids (diretriz 1.3) exige um antes de
//  qualquer compra e de qualquer link para fora do app, e ele precisa BARRAR
//  quem tem de três a seis anos — não só atrasar. O paywall e a área dos
//  pais abrem sem ele; ele aparece no toque que compra ou sai do app:
//  Assinar e os links de Terms e Privacy, no `PaywallView`; Gerenciar
//  assinatura e os mesmos dois links, no `ParentsView`.
//
//  Multiplicação em algarismos ("7 × 4"): é o formato que o adulto lê de
//  relance, e a tábua do três ao nove não é conta que criança dessa idade
//  saiba. Resposta digitada, nunca múltipla escolha — com quatro opções,
//  tocar ao acaso passa uma vez em quatro.
//
//  Teclado próprio em vez de `.keyboardType(.numberPad)`: no iPad o teclado
//  numérico vira o teclado inteiro, e o do sistema cobre metade da tela e
//  empurra o layout. Aqui as teclas têm o mesmo tamanho em qualquer pose.
//
//  Quem vê esta tela é um adulto: Papel e Tinta, sem ilustração, um acento só
//  no botão de continuar e no aviso de erro.
//

import SwiftUI

struct ParentalGate: View {
    let proposito: PropositoDoPortao
    var onPass: () -> Void
    var onCancel: () -> Void

    @State private var pergunta = Pergunta.nova()
    @State private var resposta = ""
    @State private var mensagem: LocalizedStringResource?
    @State private var errosSeguidos = 0
    /// Sobe a cada resposta errada: dispara a vibração de erro e conta as
    /// tentativas para o analytics.
    @State private var erros = 0
    @State private var pausado = false
    @State private var pausas = 0
    @State private var registrouVisita = false
    @State private var abertoEm = Date()
    /// Já acertou ou já fechou. Toque durante a animação de saída não conta
    /// de novo, nem como acerto nem como desistência.
    @State private var encerrou = false

    /// Três erros seguidos pausam o teclado. Adulto erra uma conta por dedo
    /// torto, não três; criança apertando tudo erra sem parar, e a pausa
    /// derruba o número de chutes por minuto sem incomodar quem sabe a conta.
    private static let limiteErros = 3
    private static let pausa: Duration = .seconds(10)
    /// A maior resposta possível é 81 (nove vezes nove): dois dígitos bastam.
    private static let maxDigitos = 2
    private static let alturaTecla: CGFloat = 60
    private static let raioTecla: CGFloat = 18

    @Environment(\.postura) private var postura

    var body: some View {
        corpo
            .background(UITokens.surface)
        .safeAreaInset(edge: .top) { barra }
        .sensoryFeedback(.error, trigger: erros)
        .task(id: pausado) { await esperarPausa() }
        // `corpo` é if/else: dobrar o Duo troca o ramo e roda o onAppear de novo.
        .onAppear {
            guard !registrouVisita else { return }
            registrouVisita = true
            abertoEm = .now
            Analytics.shared.track(.parentalGateShown(proposito: proposito))
        }
        // Gesto de "voltar" do VoiceOver (esfregar com dois dedos) fecha o portão.
        .accessibilityAction(.escape, cancelar)
    }

    // MARK: Layout

    /// No Duo aberto na horizontal, a pergunta fica numa metade e o teclado
    /// na outra: tecla em cima da dobra, com o aparelho meio fechado, é toque
    /// que escorrega. A troca de pose só muda a disposição — pergunta,
    /// resposta digitada e pausa continuam as mesmas.
    @ViewBuilder
    private var corpo: some View {
        if postura.duasMetades {
            HStack(spacing: postura.calha) {
                coluna {
                    cabecalho
                    visor
                }
                coluna {
                    teclado
                    continuar
                }
            }
        } else {
            coluna {
                cabecalho
                visor
                teclado
                continuar
            }
        }
    }

    private func coluna<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        ScrollView {
            VStack(spacing: Space.lg) {
                content()
            }
            // No iPad e no display aberto a coluna não estica: teclado de
            // 700pt de largura não parece teclado.
            .frame(maxWidth: 420)
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.md)
            .frame(maxWidth: .infinity)
        }
        // Parado quando cabe, rolável quando não cabe (iPhone deitado, tela
        // pequena) — nunca corta o botão de continuar.
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.center, for: .alignment)
    }

    // MARK: Barra

    private var barra: some View {
        HStack {
            Button(action: cancelar) {
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

    // MARK: Pergunta

    private var cabecalho: some View {
        VStack(spacing: Space.sm) {
            Label("Grown-ups only", systemImage: "lock.fill")
                .font(TypeScale.legenda.weight(.semibold))
                .foregroundStyle(UITokens.inkSecondary)
                .accessibilityAddTraits(.isHeader)

            Text(pergunta.texto)
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(UITokens.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: pergunta)
                // "7 × 4" o VoiceOver lê de jeito imprevisível; por extenso não
                .accessibilityLabel(pergunta.falada)

            Text("Type the answer to continue.")
                .font(TypeScale.legenda)
                .foregroundStyle(UITokens.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Visor

    private var visor: some View {
        VStack(spacing: Space.xs) {
            Text(resposta.isEmpty ? "?" : resposta)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(resposta.isEmpty ? UITokens.inkSecondary.opacity(0.4) : UITokens.ink)
                .frame(width: 140, height: 72)
                .background(UITokens.surfaceRaised, in: .rect(cornerRadius: Self.raioTecla))
                .overlay {
                    RoundedRectangle(cornerRadius: Self.raioTecla, style: .continuous)
                        .strokeBorder(mensagem == nil ? UITokens.ink.opacity(0.1) : UITokens.erro,
                                      lineWidth: mensagem == nil ? 1 : 2)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Answer")
                .accessibilityValue(resposta.isEmpty ? Text("empty") : Text(verbatim: resposta))

            // Linha reservada mesmo sem mensagem: o aviso aparecer não pode
            // empurrar o teclado para baixo do dedo de quem está digitando.
            // Espaço em branco vai verbatim para o Xcode não extrair " " como
            // chave do catálogo (ele não gera símbolo pra chave só com espaço).
            Group {
                if let mensagem { Text(mensagem) } else { Text(verbatim: " ") }
            }
            .font(TypeScale.legenda.weight(.medium))
            .foregroundStyle(UITokens.accent)
            .multilineTextAlignment(.center)
            .frame(minHeight: 20)
            .accessibilityHidden(mensagem == nil)
        }
    }

    // MARK: Teclado

    private enum Tecla: Hashable {
        case digito(Int), apagar, vazio
    }

    /// Disposição do teclado de telefone — a que o adulto já tem na mão.
    private static let linhas: [[Tecla]] = [
        [.digito(1), .digito(2), .digito(3)],
        [.digito(4), .digito(5), .digito(6)],
        [.digito(7), .digito(8), .digito(9)],
        [.vazio,     .digito(0), .apagar],
    ]

    private var teclado: some View {
        VStack(spacing: Space.sm) {
            ForEach(Self.linhas, id: \.self) { linha in
                HStack(spacing: Space.sm) {
                    ForEach(linha, id: \.self) { tecla in
                        botao(tecla)
                    }
                }
            }
        }
        .disabled(pausado)
    }

    @ViewBuilder
    private func botao(_ tecla: Tecla) -> some View {
        switch tecla {
        case .digito(let n):
            Button { digitar(n) } label: {
                Text(String(n))
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .foregroundStyle(UITokens.ink)
            }
            .buttonStyle(TeclaStyle())

        case .apagar:
            Button(action: apagar) {
                Image(systemName: "delete.backward")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(UITokens.ink)
            }
            .buttonStyle(TeclaStyle(discreta: true))
            .disabled(resposta.isEmpty)
            .accessibilityLabel("Delete")

        case .vazio:
            Color.clear
                .frame(maxWidth: .infinity, minHeight: Self.alturaTecla)
                .accessibilityHidden(true)
        }
    }

    /// Tecla chapada de Papel claro, não vidro: vidro é para controle que
    /// flutua sobre arte, e aqui não há arte. Doze pílulas translúcidas
    /// sobre campo liso só viram ruído.
    private struct TeclaStyle: ButtonStyle {
        /// Sem fundo, como o apagar do teclado do sistema.
        var discreta = false

        @Environment(\.isEnabled) private var isEnabled

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .frame(maxWidth: .infinity, minHeight: ParentalGate.alturaTecla)
                .contentShape(.rect(cornerRadius: ParentalGate.raioTecla))
                .background {
                    if !discreta {
                        RoundedRectangle(cornerRadius: ParentalGate.raioTecla, style: .continuous)
                            .fill(UITokens.surfaceRaised)
                        RoundedRectangle(cornerRadius: ParentalGate.raioTecla, style: .continuous)
                            .strokeBorder(UITokens.ink.opacity(0.08))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: ParentalGate.raioTecla, style: .continuous)
                        .fill(UITokens.ink.opacity(configuration.isPressed ? 0.08 : 0))
                }
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }

    // MARK: Continuar

    private var continuar: some View {
        Button(action: conferir) {
            Text("Continue")
                .font(TypeScale.ui.weight(.semibold))
                // largura DENTRO do rótulo, senão a cápsula de vidro não estica
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(UITokens.accent)
        .controlSize(.large)
        .disabled(resposta.isEmpty || pausado)
        .accessibilityHint("Checks the answer")
    }

    // MARK: Ações

    private func digitar(_ n: Int) {
        guard !pausado, resposta.count < Self.maxDigitos else { return }
        // nenhuma resposta possível começa com zero
        guard !(resposta.isEmpty && n == 0) else { return }
        resposta.append(String(n))
        mensagem = nil
    }

    private func apagar() {
        guard !resposta.isEmpty else { return }
        resposta.removeLast()
    }

    private func conferir() {
        guard !pausado, !encerrou, let valor = Int(resposta) else { return }

        if valor == pergunta.resposta {
            encerrou = true
            // Antes do `onPass`, que fecha a tela.
            Analytics.shared.track(.parentalGatePassed(
                proposito: proposito, erros: erros, pausou: pausas > 0,
                duracao: Date.now.timeIntervalSince(abertoEm)))
            onPass()
            return
        }

        // Errou: pergunta NOVA, nunca a mesma. Se ficasse, bastaria tentar
        // os números um a um até acertar.
        erros += 1
        errosSeguidos += 1
        resposta = ""
        pergunta = .nova(diferenteDe: pergunta)

        let aviso: LocalizedStringResource
        if errosSeguidos >= Self.limiteErros {
            pausado = true
            pausas += 1
            aviso = "Too many tries. Please wait a moment."
        } else {
            aviso = "That's not right. Try this new question."
        }
        // Só contagens: a pergunta e a resposta digitada não saem daqui.
        Analytics.shared.track(.parentalGateFailed(
            proposito: proposito, errosSeguidos: errosSeguidos, causouPausa: pausado))
        mensagem = aviso

        let anuncio = "\(String(localized: aviso)) \(pergunta.falada)"
        AccessibilityNotification.Announcement(anuncio).post()
    }

    /// O X e o gesto de voltar do VoiceOver. O evento não diz qual dos dois:
    /// o gesto revelaria quem usa VoiceOver.
    private func cancelar() {
        guard !encerrou else { return }
        encerrou = true
        Analytics.shared.track(.parentalGateCancelled(
            proposito: proposito, erros: erros, emPausa: pausado,
            tinhaResposta: !resposta.isEmpty))
        onCancel()
    }

    private func esperarPausa() async {
        guard pausado else { return }
        do {
            try await Task.sleep(for: Self.pausa)
        } catch {
            // tarefa cancelada: a tela fechou, não há o que liberar
            return
        }
        pausado = false
        errosSeguidos = 0
        mensagem = nil

        let anuncio = String(localized: "You can try again. \(pergunta.falada)")
        AccessibilityNotification.Announcement(anuncio).post()
    }
}

// MARK: - Pergunta

extension ParentalGate {
    /// Multiplicação de dois fatores entre três e nove, em algarismos na tela
    /// e por extenso para o VoiceOver. Fora dessa faixa a conta vira coisa que criança já ouviu ("dois vezes
    /// dois", "dez vezes dez") ou sai da tábua que o adulto faz de cabeça.
    struct Pergunta: Equatable {
        let a: Int
        let b: Int

        static let fatores = 3...9

        var resposta: Int { a * b }

        var texto: String { "\(a) × \(b)" }

        var falada: String {
            String(localized: "What is \(Self.extenso(a)) times \(Self.extenso(b))?")
        }

        /// Sorteia uma conta cujo RESULTADO difere do anterior — trocar "sete
        /// vezes oito" por "oito vezes sete" não é pergunta nova.
        static func nova(diferenteDe anterior: Pergunta? = nil) -> Pergunta {
            var sorteada: Pergunta
            repeat {
                sorteada = Pergunta(a: .random(in: fatores), b: .random(in: fatores))
            } while sorteada.resposta == anterior?.resposta
            return sorteada
        }

        /// Número por extenso no idioma do aparelho — "seven", "sete", "sept",
        /// "sieben" — via NumberFormatter, para o VoiceOver soletrar a conta
        /// como um adulto leria.
        private static func extenso(_ n: Int) -> String {
            let f = NumberFormatter()
            f.numberStyle = .spellOut
            f.locale = .current
            return f.string(from: NSNumber(value: n)) ?? String(n)
        }
    }
}

#Preview {
    ParentalGate(proposito: .subscribe, onPass: {}, onCancel: {})
        .medirPostura()
}
