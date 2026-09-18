//
//  MotionVideo.swift
//  Nuna
//
//  O único lugar do app com AVFoundation. Toca um clipe curto em laço por cima
//  da arte parada, que continua embaixo como primeiro quadro — é dela que o
//  pipeline gera o vídeo, então a troca não tem corte.
//
//  O fade no fim existe porque laço perfeito não dá: o último quadro não é o
//  primeiro, e a volta seca pula. O vídeo some meio segundo antes de acabar, a
//  arte parada aparece por baixo, e ele volta já no começo.
//
//  Recorte. O clipe do spread é 16:9 com a arte 3:2 no meio e Papel nas
//  laterais — foi assim que o modelo aceitou gerar sem cortar a arte. Aqui a
//  moldura é a da arte, e `resizeAspectFill` come exatamente as tarjas de
//  Papel. Numa página só, a moldura mostra metade: o vídeo entra no dobro da
//  largura, deslocado meia tela, e o resto é cortado.
//
//  Regras de casa:
//    - mudo, e a sessão de áudio é "ambiente": não cala a música do adulto;
//    - só o que está na frente toca, um clipe por vez;
//    - Reduzir Movimento ou Modo de Baixo Consumo: fica na arte parada.
//

import AVFoundation
import SwiftUI

/// Dono do `AVPlayer`, fora da struct da view.
///
/// Isto não é firula de arquitetura: `addPeriodicTimeObserver` PRECISA de um
/// `removeTimeObserver` antes de o player morrer, e o AVFoundation derruba o
/// app quando isso não acontece. Estado de `View` some sem avisar — o
/// `onDisappear` nem sempre roda quando a página é trocada no meio de uma
/// transição. Numa classe, o `deinit` sempre roda, e é ele que limpa.
/// UM player para o app inteiro, criado uma vez e vivo até o app fechar.
///
/// Antes cada página tinha o seu: virar a página criava um `AVQueuePlayer` e um
/// `AVPlayerLooper` e matava os anteriores NO MEIO da transição, com o
/// observador de tempo ligado e o KVO do laço aberto no item que estava
/// trocando. É daí que vinham as quedas ao passar de um motion para outro —
/// intermitentes, porque dependem de onde o laço estava quando a página virou.
///
/// Como nunca há dois clipes tocando ao mesmo tempo (só a página da frente, ou
/// só o cartão em foco), um player basta. Quem vai aparecer **assume** o
/// player, e quem estava com ele é avisado e para de desenhar. Nada nasce e
/// nada morre numa virada: só o item muda.
// `@unchecked`: tudo aqui é tocado na main — as views e o observador de tempo,
// que roda em `.main`. O compilador não tem como ver isso sozinho.
nonisolated final class TocadorDeMotion: @unchecked Sendable {
    static let shared = TocadorDeMotion()

    /// Quanto o vídeo leva para entrar e para sair.
    static let fade: TimeInterval = 0.45

    let player = AVQueuePlayer()
    private var laco: AVPlayerLooper?
    private var clipe: URL?

    /// Quem está com o player agora.
    private var dono: UUID?
    /// Visibilidade do clipe para o dono atual (o fade do fim do laço).
    private var aviso: ((Bool) -> Void)?
    /// Avisa o dono anterior que a camada não é mais dele.
    private var perdeu: (() -> Void)?
    /// Pilha de quem quer tocar. Existe por causa de um caso só: o cartão da
    /// Home continua vivo atrás do leitor, e quando o leitor fecha alguém
    /// precisa devolver o player para ele.
    private var fila: [(id: UUID, retomar: () -> Void)] = []

    private init() {
        player.isMuted = true
        player.actionAtItemEnd = .none
        // A sessão de áudio é do app inteiro (`SessaoDeAudio`, na abertura):
        // `.playback` com `mixWithOthers`, então este vídeo mudo não cala o
        // podcast de quem está com a criança no colo.

        // Um observador para a vida do app. Não é removido porque o player
        // não morre — e era justamente o par registrar/remover a cada página
        // que o AVFoundation não perdoava.
        _ = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { [weak self] agora in
            guard let self,
                  let duracao = self.player.currentItem?.duration.seconds,
                  duracao.isFinite, duracao > 0 else { return }
            let falta = duracao - agora.seconds
            self.aviso?(falta > Self.fade && agora.seconds > 0.05)
        }
    }

    /// Esta view passa a ser a dona da camada e do clipe.
    func assumir(_ id: UUID, url: URL,
                 visibilidade: @escaping (Bool) -> Void,
                 perdendo: @escaping () -> Void,
                 retomando: @escaping () -> Void) {
        fila.removeAll { $0.id == id }
        fila.append((id, retomando))

        if dono != id {
            perdeu?()
            dono = id
        }
        aviso = visibilidade
        perdeu = perdendo
        carregar(url)
        player.play()
    }

    /// Esta view saiu de cena. Se o player era dela, passa para quem ficou
    /// esperando; se não era, só sai da fila.
    func soltar(_ id: UUID) {
        fila.removeAll { $0.id == id }
        guard dono == id else { return }

        aviso?(false)
        aviso = nil
        perdeu = nil
        dono = nil
        player.pause()
        fila.last?.retomar()
    }

    func tocar() { player.play() }
    func pausar() { player.pause() }

    /// Troca o clipe sem trocar o player: solta o laço antigo antes, esvazia a
    /// fila e só então monta o novo. O `AVPlayerLooper` observa o item por
    /// KVO — soltar sem `disableLooping()` é pedir para cair.
    private func carregar(_ nova: URL) {
        guard nova != clipe else { return }
        clipe = nova
        aviso?(false)
        laco?.disableLooping()
        laco = nil
        player.pause()
        player.removeAllItems()
        laco = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: nova))
        Diagnostico.rastro("motion: laço novo em \(nova.lastPathComponent)")
    }
}

struct MotionVideo: View {
    /// Qual pedaço do clipe aparece nesta moldura.
    enum Recorte { case inteiro, esquerda, direita }

    let url: URL
    var tocando: Bool
    var recorte: Recorte = .inteiro

    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento
    @Environment(\.scenePhase) private var fase

    /// Identidade desta moldura junto ao player compartilhado.
    @State private var eu = UUID()
    /// O player está comigo agora? Só o dono desenha a camada — duas camadas
    /// no mesmo player disputariam o quadro.
    @State private var meu = false
    @State private var visivel = false

    static let fade = TocadorDeMotion.fade

    /// Dá para animar agora? Bateria fraca e Reduzir Movimento mandam mais
    /// que qualquer tela.
    private var permitido: Bool {
        !reduzirMovimento && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        GeometryReader { geo in
            let largura = recorte == .inteiro ? geo.size.width : geo.size.width * 2
            let desloca: CGFloat = {
                switch recorte {
                case .inteiro:  return 0
                case .esquerda: return geo.size.width / 2
                case .direita:  return -geo.size.width / 2
                }
            }()

            ZStack {
                Color.clear
                if meu {
                    CamadaDeVideo(player: TocadorDeMotion.shared.player)
                        .frame(width: largura, height: geo.size.height)
                        .offset(x: desloca)
                        .opacity(visivel && tocando ? 1 : 0)
                        .animation(.easeInOut(duration: Self.fade),
                                   value: visivel && tocando)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .allowsHitTesting(false)     // o toque continua sendo de quem está atrás
        .accessibilityHidden(true)   // quem conta a cena é o texto da página
        .onAppear { if tocando { assumir() } }
        .onDisappear { soltar() }
        .onChange(of: tocando) { _, agora in
            if agora { assumir() } else { soltar() }
        }
        // Página nova: o MESMO player recebe o clipe novo.
        .onChange(of: url) { _, _ in
            visivel = false
            if tocando { assumir() }
        }
        .onChange(of: fase) { _, agora in
            guard meu else { return }
            if agora == .active {
                if tocando { TocadorDeMotion.shared.tocar() }
            } else {
                TocadorDeMotion.shared.pausar()
            }
        }
    }

    private func assumir() {
        guard permitido else { return }
        visivel = false
        Motion.log("assumir \(url.lastPathComponent) recorte=\(recorte)")
        TocadorDeMotion.shared.assumir(
            eu, url: url,
            visibilidade: { aparecer in if visivel != aparecer { visivel = aparecer } },
            perdendo: { meu = false; visivel = false },
            retomando: { assumir() }
        )
        meu = true
        Motion.log("tocando \(url.lastPathComponent) recorte=\(recorte)")
    }

    private func soltar() {
        visivel = false
        meu = false
        Motion.log("soltar \(url.lastPathComponent)")
        TocadorDeMotion.shared.soltar(eu)
    }
}

/// `AVPlayerLayer` cru: `VideoPlayer` traz controles, e controle de vídeo numa
/// página de livro infantil é convite para o dedo errado.
private struct CamadaDeVideo: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> VistaDeVideo {
        let v = VistaDeVideo()
        v.isUserInteractionEnabled = false
        v.camada.player = player
        v.camada.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ v: VistaDeVideo, context: Context) {
        if v.camada.player !== player { v.camada.player = player }
    }

    /// A camada sai da tela mas o player continua vivo: solta a referência
    /// aqui, senão sobram camadas velhas apontando para ele e a página nova
    /// disputa o quadro com uma que já não existe.
    static func dismantleUIView(_ v: VistaDeVideo, coordinator: ()) {
        v.camada.player = nil
    }
}

final class VistaDeVideo: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var camada: AVPlayerLayer { layer as! AVPlayerLayer }
}

// MARK: - Do pacote sob demanda para a tela

/// O vídeo de uma arte, resolvido pelo `MotionStore`.
///
/// Os clipes não vêm no download do app: cada livro é uma tag de On-Demand
/// Resources. Esta view pede o arquivo só quando é para tocar de verdade —
/// com Reduzir Movimento, ou fora de foco, nem rede ela gasta. Enquanto não
/// chega, quem aparece é a arte parada que está embaixo.
struct MotionArte: View {
    let fonte: FonteDeMotion
    var tocando: Bool

    @Environment(\.accessibilityReduceMotion) private var reduzirMovimento
    @State private var url: URL?
    /// Qual asset o `url` acima resolve. Sem isto, virar a página trocava a
    /// fonte e o vídeo da página anterior continuava rodando.
    @State private var resolvido: String?

    /// Baixar um vídeo que não vai tocar é gastar rede da casa à toa.
    private var vaiTocar: Bool {
        tocando && !reduzirMovimento
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        // `Color.clear` por baixo: com o `if` sozinho, a view fica vazia
        // enquanto o vídeo não chega, e view vazia é terreno instável para
        // modificadores — inclusive para o `.task` que busca o arquivo.
        ZStack {
            Color.clear
            if let url, resolvido == fonte.asset {
                MotionVideo(url: url, tocando: tocando, recorte: fonte.recorte)
            }
        }
        // O pacote pode estar chegando ainda: tenta de novo algumas vezes,
        // com espera crescente, em vez de desistir na primeira.
        .task(id: "\(fonte.asset)|\(vaiTocar)") {
            guard vaiTocar else { return }
            if resolvido == fonte.asset, url != nil { return }
            url = nil
            for tentativa in 0..<4 {
                if let pronta = await MotionStore.shared.url(asset: fonte.asset,
                                                             tag: fonte.tag) {
                    url = pronta
                    resolvido = fonte.asset
                    Motion.log("\(fonte.asset) pronto (\(fonte.recorte))")
                    return
                }
                guard !Task.isCancelled else { return }
                Motion.log("\(fonte.asset) ainda não veio, tentativa \(tentativa + 1)")
                try? await Task.sleep(for: .seconds(Double(tentativa + 1) * 1.5))
                // De novo DEPOIS da espera: cancelada, a espera volta na hora,
                // e sem esta linha a página que está saindo recomeçava o
                // download de 70 MB um segundo depois de o livro fechar.
                guard !Task.isCancelled else { return }
            }
            Motion.log("\(fonte.asset) DESISTIU")
        }
    }
}

/// Rastro do motion no console, só em Debug. Quando algo não aparece na tela,
/// a primeira pergunta é sempre a mesma: o arquivo chegou?
enum Motion {
    static func log(_ texto: @autoclosure () -> String) {
        // Vai para a caixa-preta: quando o app cai, o que o vídeo estava
        // fazendo aparece no relatório junto com as viradas de página.
        Diagnostico.rastro("motion: \(texto())")
    }
}
