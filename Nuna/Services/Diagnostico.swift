//
//  Diagnostico.swift
//  Nuna
//
//  Caixa-preta. O app grava o que estava fazendo pouco antes de morrer.
//
//  O crash acontece num iPhone de verdade, e relatório de aparelho não chega
//  na máquina de quem escreve o código. Sem ele sobra adivinhação — e já
//  gastamos três rodadas adivinhando. Então o app passa a contar sozinho:
//
//    1. cada ação importante (virar página, montar vídeo, pedir pacote) vira
//       uma linha com o relógio e a memória em uso, escrita NO DISCO na hora;
//    2. exceção do Objective-C e sinal fatal (SIGABRT, SIGTRAP, SIGSEGV…)
//       gravam motivo e pilha antes do processo cair;
//    3. na abertura seguinte, tudo isso sai no console em bloco, pronto para
//       copiar.
//
//  Por que escrever a cada linha, e não guardar na memória: quando o iOS mata
//  o app por falta de memória NÃO existe sinal nem relatório — o app some. O
//  rastro em disco é o único jeito de saber que foi isso, e a memória em cada
//  linha mostra a curva subindo até o corte.
//
//  Custo: algumas dezenas de bytes por virada de página. Fica ligado até o
//  crash ter nome.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

nonisolated enum Diagnostico {
    /// Linhas guardadas em memória para o relatório de crash.
    private static let maximo = 120
    private static let trava = NSLock()
    nonisolated(unsafe) private static var rastros: [String] = []
    nonisolated(unsafe) private static var marcoZero = Date()
    nonisolated(unsafe) private static var saida: FileHandle?

    // MARK: Onde fica

    private static var pasta: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    /// O rastro desta execução.
    private static var arquivoDoRastro: URL { pasta.appendingPathComponent("nuna-rastro.txt") }
    /// O rastro da execução anterior — o que interessa quando ela não voltou.
    private static var arquivoAnterior: URL { pasta.appendingPathComponent("nuna-rastro-anterior.txt") }
    /// Motivo e pilha, quando deu tempo de gravar.
    private static var arquivoDoCrash: URL { pasta.appendingPathComponent("nuna-crash.txt") }
    /// O último crash já impresso. Guardado, não apagado: quem reabre o app
    /// pela tela inicial não vê o console, e o relatório tem que continuar lá
    /// para ser puxado do aparelho (`devicectl device copy from`).
    private static var arquivoDoCrashAnterior: URL { pasta.appendingPathComponent("nuna-crash-anterior.txt") }

    // MARK: Instalação

    /// Chamado uma vez, no `init` do app. Imprime o que sobrou da execução
    /// passada e arma os ganchos desta.
    static func instalar() {
        imprimirPendente()
        rotacionar()
        armarGanchos()
        rastro("app iniciou")
    }

    private static func imprimirPendente() {
        let fm = FileManager.default
        let crash = try? String(contentsOf: arquivoDoCrash, encoding: .utf8)
        let anterior = try? String(contentsOf: arquivoAnterior, encoding: .utf8)
        guard crash != nil || anterior != nil else { return }

        var texto = "\n==================== NUNA — A EXECUÇÃO ANTERIOR ====================\n"
        if let crash {
            texto += crash
        } else {
            // Nem exceção, nem sinal, e mesmo assim não voltou: quem fecha um
            // app sem deixar bilhete é o próprio iOS, por memória.
            texto += """
            SEM SINAL E SEM EXCEÇÃO.
            O processo terminou sem crash registrado — o padrão de quando o iOS
            mata o app por memória (ou de quando você mesmo o encerrou).
            Olhe a coluna de memória nas últimas linhas: se ela sobe a cada
            virada, é isso.\n
            """
        }
        if let anterior, !anterior.isEmpty {
            texto += "\n--- últimas ações antes do fim ---\n" + ultimasLinhas(anterior, 60)
        }
        texto += "====================================================================\n"
        print(texto)

        if crash != nil {
            try? fm.removeItem(at: arquivoDoCrashAnterior)
            try? fm.moveItem(at: arquivoDoCrash, to: arquivoDoCrashAnterior)
        }
    }

    private static func ultimasLinhas(_ texto: String, _ quantas: Int) -> String {
        let linhas = texto.split(separator: "\n", omittingEmptySubsequences: false)
        return linhas.suffix(quantas).joined(separator: "\n") + "\n"
    }

    private static func rotacionar() {
        let fm = FileManager.default
        try? fm.removeItem(at: arquivoAnterior)
        try? fm.moveItem(at: arquivoDoRastro, to: arquivoAnterior)
        fm.createFile(atPath: arquivoDoRastro.path, contents: nil)
        saida = try? FileHandle(forWritingTo: arquivoDoRastro)
        marcoZero = Date()
    }

    private static func armarGanchos() {
        NSSetUncaughtExceptionHandler { excecao in
            Diagnostico.gravarCrash(
                motivo: "EXCEÇÃO \(excecao.name.rawValue): \(excecao.reason ?? "sem motivo")",
                pilha: excecao.callStackSymbols)
        }
        #if canImport(UIKit)
        // Aviso de memória é o único bilhete que o iOS deixa antes de matar
        // o app por espaço. No rastro, ele explica um fim sem sinal nenhum.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { _ in
            Diagnostico.rastro("AVISO DE MEMÓRIA DO SISTEMA")
        }
        #endif

        for sinal in [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP] {
            signal(sinal) { codigo in
                Diagnostico.gravarCrash(motivo: "SINAL \(Diagnostico.nomeDoSinal(codigo))",
                                        pilha: Thread.callStackSymbols)
                signal(codigo, SIG_DFL)
                raise(codigo)
            }
        }
    }

    static func nomeDoSinal(_ codigo: Int32) -> String {
        switch codigo {
        case SIGABRT: return "SIGABRT (abort — exceção não tratada, assert do sistema)"
        case SIGILL:  return "SIGILL (instrução ilegal)"
        case SIGSEGV: return "SIGSEGV (endereço inválido — objeto já liberado)"
        case SIGFPE:  return "SIGFPE (aritmética)"
        case SIGBUS:  return "SIGBUS (acesso desalinhado)"
        case SIGTRAP: return "SIGTRAP (trap do Swift — índice fora da faixa, nil forçado, overflow)"
        default:      return "sinal \(codigo)"
        }
    }

    // MARK: Rastro

    /// Uma linha do rastro: relógio, memória e o que aconteceu.
    ///
    /// `@autoclosure` para o texto só ser montado se o rastro estiver ligado.
    static func rastro(_ texto: @autoclosure () -> String) {
        let linha = String(format: "%7.2fs  %4d MB  %@",
                           Date().timeIntervalSince(marcoZero), memoriaMB, texto())
        trava.lock()
        rastros.append(linha)
        if rastros.count > maximo { rastros.removeFirst(rastros.count - maximo) }
        // Direto no descritor: escrita com buffer se perde quando o iOS mata
        // o processo, que é justamente o caso que se quer enxergar.
        if let saida, let dados = (linha + "\n").data(using: .utf8) {
            try? saida.write(contentsOf: dados)
        }
        trava.unlock()
        #if DEBUG
        print("[nuna] \(linha)")
        #endif
    }

    /// Memória que o app ocupa, em MB. É o número que o iOS usa para decidir
    /// quem morre quando o aparelho aperta.
    static var memoriaMB: Int {
        var info = task_vm_info_data_t()
        var contagem = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let resultado = withUnsafeMutablePointer(to: &info) { ponteiro in
            ponteiro.withMemoryRebound(to: integer_t.self, capacity: Int(contagem)) { bruto in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), bruto, &contagem)
            }
        }
        guard resultado == KERN_SUCCESS else { return -1 }
        return Int(info.phys_footprint) / (1024 * 1024)
    }

    // MARK: Crash

    private static func gravarCrash(motivo: String, pilha: [String]) {
        trava.lock()
        let ultimas = rastros.suffix(60).joined(separator: "\n")
        trava.unlock()

        let texto = """
        MOTIVO: \(motivo)
        memória no fim: \(memoriaMB) MB

        --- últimas ações ---
        \(ultimas)

        --- pilha ---
        \(pilha.prefix(40).joined(separator: "\n"))

        """
        try? texto.write(to: arquivoDoCrash, atomically: true, encoding: .utf8)
        // Se o console ainda estiver escutando, sai na hora também.
        print("\n==================== NUNA CAIU ====================\n\(texto)")
    }
}
