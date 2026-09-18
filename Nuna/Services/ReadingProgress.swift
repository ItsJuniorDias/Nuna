//
//  ReadingProgress.swift
//  Nuna
//
//  Onde a criança parou, por livro.
//
//  Sem isto o botão "Continuar" mente: ele volta sempre pra página 1. Ou o
//  rótulo muda para "Ler", ou o progresso existe de verdade — e progresso é
//  o que a pessoa espera de um app de leitura.
//

import Foundation

@Observable
final class ReadingProgress {
    static let shared = ReadingProgress()

    private static let chave = "reading.progress"
    private static let chaveDatas = "reading.lastRead"
    private var cache: [String: Int]
    /// Quando cada livro foi lido pela última vez. Sem isto, "continuar" era
    /// o primeiro livro da estante com progresso — e não o que a criança
    /// estava lendo agora.
    private var datas: [String: Date]

    private init() {
        cache = UserDefaults.standard.dictionary(forKey: Self.chave) as? [String: Int] ?? [:]
        datas = UserDefaults.standard.dictionary(forKey: Self.chaveDatas) as? [String: Date] ?? [:]
    }

    /// Índice do spread onde parou. Zero quando nunca abriu.
    func spread(for id: String) -> Int { cache[id] ?? 0 }

    func started(_ id: String) -> Bool { (cache[id] ?? 0) > 0 }

    /// Chegou na última página. Livro terminado sai do "continuar": ficar lá
    /// dizendo "página 12 de 12" é lembrete do que já acabou.
    func concluido(_ id: String, total: Int) -> Bool {
        total > 0 && (cache[id] ?? 0) >= total - 1
    }

    func ultimaLeitura(_ id: String) -> Date { datas[id] ?? .distantPast }

    func save(_ index: Int, for id: String) {
        datas[id] = .now
        UserDefaults.standard.set(datas, forKey: Self.chaveDatas)
        guard cache[id] != index else { return }
        cache[id] = index
        UserDefaults.standard.set(cache, forKey: Self.chave)
    }

    /// O livro abriu: já conta como "em leitura", mesmo parado na página 1.
    /// Antes só a primeira virada colocava o livro no "continuar".
    func marcarAberto(_ id: String) {
        datas[id] = .now
        if cache[id] == nil { cache[id] = 0 }
        UserDefaults.standard.set(datas, forKey: Self.chaveDatas)
        UserDefaults.standard.set(cache, forKey: Self.chave)
    }

    /// Foi aberto alguma vez, mesmo que não tenha virado página.
    func emLeitura(_ id: String) -> Bool { datas[id] != nil }

    /// "Recomeçar leituras" da área dos pais.
    func resetAll() {
        cache = [:]
        datas = [:]
        UserDefaults.standard.removeObject(forKey: Self.chave)
        UserDefaults.standard.removeObject(forKey: Self.chaveDatas)
    }

    func reset(_ id: String) {
        cache.removeValue(forKey: id)
        datas.removeValue(forKey: id)
        UserDefaults.standard.set(cache, forKey: Self.chave)
        UserDefaults.standard.set(datas, forKey: Self.chaveDatas)
    }
}
