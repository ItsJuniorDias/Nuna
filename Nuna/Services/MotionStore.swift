//
//  MotionStore.swift
//  Nuna
//
//  Os vídeos não vêm no download do app. Cada livro tem DUAS tags de
//  On-Demand Resources, e a separação importa:
//
//    motion-<slug>          a capa animada. ~6 MB, pedida pelo cartão da Home
//                           quando ele está em foco.
//    motion-spreads-<slug>  as 12 páginas em movimento. ~35 MB, pedidas só
//                           dentro do leitor, página a página.
//
//  Juntas, focar um livro no carrossel baixaria 40 MB para a capa respirar.
//  O iOS baixa quando alguém pede e apaga sozinho quando o aparelho apertar.
//
//  Fluxo de um clipe:
//    1. já tem arquivo no cache? devolve na hora;
//    2. senão, pede o pacote `motion-<slug>` ao `Pacotes` — sem rede nenhuma
//       se ele já estiver no aparelho;
//    3. lê o `NSDataAsset` e grava em Caches, porque `AVPlayer` quer URL;
//    4. o pacote fica vivo enquanto o livro estiver aberto, e é solto depois.
//
//  Falhou (sem rede, sem espaço, pacote ausente)? Devolve nil, e a tela fica
//  na arte parada. Motion é enfeite: nunca pode impedir a leitura.
//

import Foundation
import UIKit   // NSDataAsset

@MainActor
@Observable
final class MotionStore {
    static let shared = MotionStore()

    /// Caminho já materializado, por nome de asset.
    private var prontos: [String: URL] = [:]
    /// No máximo isto de clipes fica em Caches; o resto é apagado do mais
    /// velho para o mais novo.
    ///
    /// Tem que caber um livro INTEIRO com folga: 12 spreads + capa, mais as
    /// capas da semana. Com o teto em 16 o próprio livro aberto se comia — o
    /// clipe da página seguinte apagava o da página que estava tocando.
    private static let tetoDeArquivos = 40

    /// Onde os clipes ficam depois de saírem do data asset. `lazy` não entra
    /// em classe `@Observable`: a pasta nasce no init.
    private let pasta: URL

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory,
                                            in: .userDomainMask)[0]
            .appendingPathComponent("motion", isDirectory: true)
        try? FileManager.default.createDirectory(at: base,
                                                 withIntermediateDirectories: true)
        pasta = base
        limparExcesso()
    }

    // MARK: Uso

    /// URL local do clipe, baixando o pacote do livro se precisar.
    ///
    /// Nada aqui guarda fracasso: quem chama tenta de novo, e o pacote pode
    /// estar a caminho. Lista negra de asset foi o que escondeu um livro
    /// inteiro quando o catálogo demorou um instante para montar o pacote.
    func url(asset: String, tag: String) async -> URL? {
        // Conferir que o arquivo continua lá: Caches é do sistema, e ele
        // limpa quando quer. URL guardada não é arquivo garantido.
        if let pronta = prontos[asset] {
            if FileManager.default.fileExists(atPath: pronta.path) { return pronta }
            prontos[asset] = nil
        }

        let arquivo = pasta.appendingPathComponent("\(asset).mp4")
        if let tamanho = try? arquivo.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           tamanho > 0 {
            prontos[asset] = arquivo
            return arquivo
        }

        // As páginas em movimento são as que a criança está olhando AGORA:
        // passam na frente das capas e das artes antecipadas em segundo plano.
        let urgente = tag.hasPrefix("motion-spreads-")
        guard await Pacotes.shared.garantir(tag, urgente: urgente) else {
            return nil
        }

        // O pacote chegou, mas o catálogo leva um instante para montá-lo: o
        // primeiro `NSDataAsset` volta vazio e o segundo vem cheio. Era isto
        // que derrubava o motion de um livro inteiro.
        var dados = NSDataAsset(name: asset)?.data
        if dados == nil || dados?.isEmpty == true {
            try? await Task.sleep(for: .milliseconds(400))
            dados = NSDataAsset(name: asset)?.data
        }
        guard let dados, !dados.isEmpty else { return nil }

        do {
            try dados.write(to: arquivo, options: .atomic)
        } catch {
            Diagnostico.rastro("motion: não gravou \(asset) (\(error.localizedDescription))")
            return nil
        }
        Diagnostico.rastro("motion: \(asset) materializado "
                           + "(\(dados.count / 1024 / 1024) MB)")
        prontos[asset] = arquivo
        limparExcesso(exceto: arquivo)
        return arquivo
    }

    /// Livro fechado: solta o pacote de vídeo. Os arquivos já materializados
    /// em Caches seguem valendo, então reabrir o livro não baixa de novo.
    func soltar(tag: String) {
        Pacotes.shared.soltar(tag)
    }

    // MARK: Cache

    private func limparExcesso(exceto: URL? = nil) {
        let fm = FileManager.default
        guard let arquivos = try? fm.contentsOfDirectory(
            at: pasta, includingPropertiesForKeys: [.contentAccessDateKey]) else { return }
        guard arquivos.count > Self.tetoDeArquivos else { return }

        let porUso = arquivos.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate) ?? .distantPast
            return a < b
        }
        for velho in porUso.prefix(arquivos.count - Self.tetoDeArquivos) {
            // Nunca o que acabou de ser pedido: pode estar tocando agora.
            guard velho != exceto else { continue }
            Diagnostico.rastro("motion: apagando do cache \(velho.lastPathComponent)")
            try? fm.removeItem(at: velho)
            prontos = prontos.filter { $0.value != velho }
        }
    }
}

// MARK: - Onde mora cada clipe

extension Book {
    /// Tag de ODR da capa animada. Todos os 50 livros têm.
    var motionTag: String { "motion-\(id)" }
    /// Tag das páginas em movimento. Só alguns livros têm — nos outros ela
    /// não existe no bundle, e o `Pacotes` descobre isso na primeira tentativa
    /// e não tenta de novo.
    var spreadMotionTag: String { "motion-spreads-\(id)" }
    var coverMotionAsset: String { "motion_\(id)" }
}

extension Spread {
    /// `spread_<slug>_07` → `motion_spread_<slug>_07`.
    var motionAsset: String { "motion_\(imageName)" }
    /// O spread não sabe o slug do livro fora do `bookId` injetado no decode.
    var motionTag: String { "motion-spreads-\(bookId)" }
}
