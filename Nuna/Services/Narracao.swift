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
//    - toca com o aparelho no silencioso: foi alguém que ligou a voz. A
//      sessão é `.playback` o app inteiro (`SessaoDeAudio`), definida uma vez
//      na abertura e nunca trocada;
//    - não cala a música de ninguém (`mixWithOthers`);
//    - página sem fala (ainda não gerada) fica muda. Nunca trava a leitura;
//    - só em inglês: as falas foram gravadas em inglês e não têm versão nos
//      outros seis idiomas do app. Fora do inglês a voz fica calada e a
//      interface esconde o botão (ver `ReaderView.topBar`).
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

    /// Lê estas falas em sequência, no lugar do que estava tocando. Fora do
    /// inglês volta calado — as falas só existem em inglês, e tocar áudio
    /// numa língua enquanto o texto está em outra é pior que ficar mudo.
    func ler(_ assets: [String]) {
        parar()
        guard ligada, AppLanguage.atual == "en" else { return }
        fila = assets
        proxima()
    }

    /// A voz é oferecida ao adulto? Só quando o idioma efetivo é inglês.
    /// Consultada pelo `ReaderView` para esconder o botão do topo.
    var disponivel: Bool { AppLanguage.atual == "en" }

    func parar() {
        fila = []
        player?.stop()
        player = nil
    }

    /// Livro fechado: a voz para. A sessão continua em `.playback` — trocar
    /// de categoria com vídeo tocando falhava em silêncio e deixava o app no
    /// modo ambiente, que a chave do silencioso cala.
    func encerrar() {
        parar()
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
            if novo.play() {
                Diagnostico.rastro("narração: \(nome) (\(String(format: "%.1f", novo.duration))s, "
                                   + "sessão \(AVAudioSession.sharedInstance().category.rawValue))")
            } else {
                Diagnostico.rastro("narração: \(nome) NÃO tocou")
            }
            player = novo
            return
        }
        player = nil
    }

    /// A categoria já é `.playback` desde a abertura; aqui só se ativa a
    /// sessão, uma vez. Falha vai para a caixa-preta em vez de sumir num `try?`.
    private func ativarSessao() {
        guard !sessaoAtiva else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            sessaoAtiva = true
        } catch {
            Diagnostico.rastro("narração: sessão não ativou — \(error.localizedDescription)")
        }
    }
}

/// A sessão de áudio do app inteiro: `.playback`, definida UMA vez, na
/// abertura, antes de qualquer vídeo ou voz tocar.
///
/// Antes a sessão alternava — ambiente para os vídeos mudos, reprodução só
/// enquanto a voz tocava —, e cada troca era um `try?`. Com vídeo rodando, a
/// troca podia falhar sem aviso e deixar o app em ambiente, que obedece a
/// chave do silencioso: a voz simplesmente não saía. Fixa, não há troca que
/// falhe.
///
/// `mixWithOthers` mantém o que já valia: o vídeo mudo da Home não para a
/// música de ninguém, e a voz toca junto com ela em vez de interrompê-la.
nonisolated enum SessaoDeAudio {
    static func configurar() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default,
                                                            options: [.mixWithOthers])
            Diagnostico.rastro("áudio: sessão em playback")
        } catch {
            Diagnostico.rastro("áudio: sessão NÃO configurou — \(error.localizedDescription)")
        }
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
