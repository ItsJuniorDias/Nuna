//
//  Narracao.swift
//  Nuna
//
//  A voz que lê a página.
//
//  Cada página tem a sua fala (`fala_spread_<slug>_NN_l`/`_r`), gravada no
//  pipeline e entregue no MESMO pacote da arte do livro — quando o leitor
//  abre, a voz já está no aparelho. Em pé toca a página da tela; deitado, a
//  da esquerda e depois a da direita, como um adulto leria o spread.
//
//  Regras de casa:
//    - ligada de fábrica: quem tem três anos ainda não lê sozinho. O adulto
//      que prefere ler ele mesmo desliga uma vez, e fica desligado;
//    - toca com o aparelho no silencioso: foi alguém que ligou a voz;
//    - não cala a música de ninguém (`mixWithOthers`), e devolve o áudio ao
//      modo ambiente quando o livro fecha;
//    - página sem fala (ainda não gerada) fica muda. Nunca trava a leitura.
//

import AVFoundation
import Foundation
import UIKit   // NSDataAsset

@MainActor
@Observable
final class Narracao {
    static let shared = Narracao()

    /// Ler em voz alta. Guardado entre aberturas.
    private(set) var ligada: Bool

    private static let chave = "narracao.ligada"
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var fila: [String] = []
    @ObservationIgnored private let fim = FimDaFala()
    @ObservationIgnored private var sessaoAtiva = false

    private init() {
        ligada = UserDefaults.standard.object(forKey: Self.chave) as? Bool ?? true
        // Só avança se quem terminou é o áudio que está tocando AGORA. Um
        // "terminei" atrasado da página anterior, chegando logo depois da
        // virada, pularia a primeira fala da página nova.
        fim.aoTerminar = { [weak self] quem in
            guard let self, let atual = self.player, ObjectIdentifier(atual) == quem else { return }
            self.proxima()
        }
    }

    func alternar() {
        ligada.toggle()
        UserDefaults.standard.set(ligada, forKey: Self.chave)
        if !ligada { parar() }
        Diagnostico.rastro("narração \(ligada ? "ligada" : "desligada")")
    }

    /// Lê estas falas em sequência, no lugar do que estava tocando.
    func ler(_ assets: [String]) {
        parar()
        guard ligada else { return }
        fila = assets
        proxima()
    }

    func parar() {
        fila = []
        player?.stop()
        player = nil
    }

    /// Livro fechado: cala e devolve o áudio do aparelho ao modo ambiente,
    /// o mesmo em que os vídeos mudos da Home tocam.
    func encerrar() {
        parar()
        guard sessaoAtiva else { return }
        sessaoAtiva = false
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
    }

    private func proxima() {
        while !fila.isEmpty {
            let nome = fila.removeFirst()
            guard let dados = NSDataAsset(name: nome)?.data,
                  let novo = try? AVAudioPlayer(data: dados,
                                                fileTypeHint: AVFileType.mp3.rawValue)
            else {
                Diagnostico.rastro("narração: \(nome) não está no aparelho")
                continue
            }
            ativarSessao()
            novo.delegate = fim
            novo.prepareToPlay()
            novo.play()
            player = novo
            return
        }
        player = nil
    }

    /// Reprodução, e não ambiente: a voz foi pedida, então toca mesmo com a
    /// chave do silencioso. `mixWithOthers` para não parar o que o adulto
    /// estiver ouvindo; `spokenAudio` avisa o sistema de que é fala.
    private func ativarSessao() {
        guard !sessaoAtiva else { return }
        sessaoAtiva = true
        let sessao = AVAudioSession.sharedInstance()
        try? sessao.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        try? sessao.setActive(true)
    }
}

/// O delegado do `AVAudioPlayer` é um protocolo do Objective-C, chamado de
/// qualquer thread. Fica fora do MainActor e devolve o fim da fala à main.
nonisolated private final class FimDaFala: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    var aoTerminar: (@MainActor @Sendable (ObjectIdentifier) -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let acao = aoTerminar
        let quem = ObjectIdentifier(player)
        Task { @MainActor in acao?(quem) }
    }
}

extension Spread {
    /// `spread_<slug>_07` na página da esquerda → `fala_spread_<slug>_07_l`.
    func falaAsset(_ lado: SpreadView.Side) -> String {
        "fala_\(imageName)_\(lado == .left ? "l" : "r")"
    }
}
