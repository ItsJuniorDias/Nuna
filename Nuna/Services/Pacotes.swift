//
//  Pacotes.swift
//  Nuna
//
//  On-Demand Resources: o que o app baixa depois de instalado.
//
//  O download inicial leva só as 50 capas, a arte do onboarding, o ícone e os
//  textos — 11 MB. A arte de cada livro e os vídeos ficam em pacotes que o
//  iOS busca quando alguém abre, e apaga sozinho quando o aparelho apertar.
//
//    livro-<slug>            os 36 imagesets dos spreads. ~5 MB. Sem isso não
//                            dá para ler: é o que o leitor espera antes de subir.
//    motion-<slug>           a capa animada. ~6 MB, para o cartão em foco.
//    motion-spreads-<slug>   as páginas em movimento. ~35 MB, e só alguns
//                            livros têm. Enfeite, carregado só quando vai
//                            tocar de verdade (ver `MotionArte`).
//
//  Quem já foi lido ganha prioridade de preservação alta: numa faxina de
//  espaço, o iOS apaga primeiro o que a criança nunca abriu.
//
//  Tudo aqui falha para o lado seguro. Sem rede e sem pacote, a capa continua
//  na estante e o leitor avisa em vez de abrir uma página em branco.
//

import Foundation

@MainActor
@Observable
final class Pacotes {
    static let shared = Pacotes()

    enum Estado: Equatable {
        case ausente
        case baixando(Double)
        case pronto
        case semRede
    }

    /// Pedidos vivos, por tag. Enquanto existe um, o pacote fica no aparelho.
    private var pedidos: [String: NSBundleResourceRequest] = [:]
    private(set) var estados: [String: Estado] = [:]
    /// Por que o último pacote não veio. Só para diagnóstico: o alerta da
    /// criança continua em uma frase, e este texto aparece embaixo dele em
    /// build de desenvolvimento.
    private(set) var ultimaFalha: String?
    /// Tags que este build não tem. Nem todo livro tem páginas em movimento,
    /// e tag ausente não aparece depois: descobre uma vez e pronto. Sem isto,
    /// cada página de cada livro sem motion refazia o pedido do zero.
    private var inexistentes: Set<String> = []

    private init() {}

    func estado(_ tag: String) -> Estado { estados[tag] ?? .ausente }

    /// Download em andamento, por tag. Quem pede um pacote que já está a
    /// caminho espera ESTE, em vez de começar outro.
    private var emCurso: [String: Task<Bool, Never>] = [:]
    /// Soltos com o download ainda em curso: soltam quando chegarem.
    private var soltarAoChegar: Set<String> = []

    /// Garante o pacote. Devolve false quando não deu — sem rede, sem espaço,
    /// pacote inexistente, download cancelado.
    ///
    /// A regra que manda aqui: cada `NSBundleResourceRequest` começa UMA vez
    /// na vida. Chamar `conditionallyBegin`/`begin` de novo no mesmo objeto é
    /// exceção do Foundation, e exceção não tratada fecha o app. Era o que
    /// acontecia: um segundo pedido da mesma tag chegava com o primeiro ainda
    /// baixando — página virada no meio do download, "Read" tocado antes de o
    /// pacote antecipado chegar — e reaproveitava o objeto. Oito quedas entre
    /// 17 e 18/09, todas com esta assinatura nos relatórios do aparelho.
    ///
    /// Agora pedidos simultâneos da mesma tag se juntam no download que já
    /// existe, e cada tentativa nova usa um objeto novo.
    @discardableResult
    func garantir(_ tag: String, urgente: Bool = true) async -> Bool {
        if inexistentes.contains(tag) { return false }
        if pedidos[tag] != nil, estado(tag) == .pronto { return true }

        if let jaIndo = emCurso[tag] {
            // Alguém quer de novo: o "soltar quando chegar" perde o sentido.
            soltarAoChegar.remove(tag)
            // Subir a prioridade de um pedido já começado é permitido: quem
            // tocou no livro não espera o ritmo da antecipação.
            if urgente {
                pedidos[tag]?.loadingPriority = NSBundleResourceRequestLoadingPriorityUrgent
            }
            return await jaIndo.value
        }

        // Quem pediu já foi embora (a página saiu, o livro fechou): juntar-se
        // a um download que existe tudo bem, COMEÇAR um de 70 MB não.
        guard !Task.isCancelled else { return false }

        let tarefa = Task { () -> Bool in
            defer { emCurso[tag] = nil }
            let chegou = await buscar(tag, urgente: urgente)
            if soltarAoChegar.remove(tag) != nil, chegou {
                pedidos.removeValue(forKey: tag)?.endAccessingResources()
                estados[tag] = nil
                Diagnostico.rastro("pacote \(tag): chegou com o livro já fechado — solto")
            }
            return chegou
        }
        emCurso[tag] = tarefa
        return await tarefa.value
    }

    /// Uma tentativa, com um pedido NOVO. Só `garantir` chama, e nunca duas
    /// vezes ao mesmo tempo para a mesma tag.
    private func buscar(_ tag: String, urgente: Bool) async -> Bool {
        let pedido = NSBundleResourceRequest(tags: [tag])
        pedido.loadingPriority = urgente
            ? NSBundleResourceRequestLoadingPriorityUrgent
            : 0.2
        pedidos[tag] = pedido

        // Já está no aparelho: nada de barra de progresso piscando à toa.
        if await pedido.conditionallyBeginAccessingResources() {
            estados[tag] = .pronto
            return true
        }
        Diagnostico.rastro("pacote \(tag): começou a baixar")

        estados[tag] = .baixando(0)
        let acompanhamento = acompanhar(pedido, tag: tag)
        defer { acompanhamento.cancel() }

        do {
            try await pedido.beginAccessingResources()
            estados[tag] = .pronto
            ultimaFalha = nil
            Diagnostico.rastro("pacote \(tag): pronto")
            return true
        } catch {
            let erro = error as NSError
            pedidos.removeValue(forKey: tag)

            if erro.domain == NSCocoaErrorDomain, erro.code == NSUserCancelledError {
                // Quem cancelou fomos nós (`soltar` no meio do download). Não
                // é falha, e não pode virar alerta de "sem internet".
                estados[tag] = .ausente
                Diagnostico.rastro("pacote \(tag): download cancelado")
                return false
            }

            ultimaFalha = "\(tag): \(Self.explicar(erro))"
            Diagnostico.rastro("pacote \(tag): FALHOU — \(Self.explicar(erro))")
            if erro.domain == NSCocoaErrorDomain,
               erro.code == NSBundleOnDemandResourceInvalidTagError {
                // Não é falta de rede: este build não tem essa tag. Anota e
                // some do caminho — quem pediu fica na arte parada.
                inexistentes.insert(tag)
                estados[tag] = .ausente
            } else {
                estados[tag] = .semRede
            }
            return false
        }
    }

    /// O que o erro do ODR quer dizer, em uma linha.
    ///
    /// Os códigos do `NSCocoaErrorDomain` para pacote sob demanda são
    /// específicos e dizem tudo — sem eles, tudo vira "sem internet", que é
    /// exatamente a mensagem errada quando a internet está boa.
    private static func explicar(_ erro: NSError) -> String {
        if erro.domain == NSCocoaErrorDomain {
            switch erro.code {
            case NSBundleOnDemandResourceInvalidTagError:
                return "tag não existe neste build (4994)"
            case NSBundleOnDemandResourceOutOfSpaceError:
                return "sem espaço no aparelho (4992)"
            case NSBundleOnDemandResourceExceededMaximumSizeError:
                return "passou do limite de pacotes em uso (4993)"
            default: break
            }
        }
        if erro.domain == NSURLErrorDomain {
            // Build de desenvolvimento serve os pacotes pelo Mac do Xcode,
            // não pela Apple: longe dele, isto aqui é o que aparece.
            return "rede: \(erro.localizedDescription) (\(erro.code)) — "
                + "em build do Xcode os pacotes vêm do Mac, não da App Store"
        }
        return "\(erro.domain) \(erro.code): \(erro.localizedDescription)"
    }

    /// Solta o pacote: o iOS pode apagar quando precisar de espaço.
    ///
    /// Ainda baixando, deixa terminar e solta na chegada. Cancelar parecia
    /// poupar rede, mas na prática a criança reabre o livro de que gostou —
    /// e com o download cancelado toda vez, as páginas em movimento de um
    /// pacote de 70 MB nunca chegavam a tempo. Solto, ele fica no aparelho
    /// até o iOS precisar do espaço. (E `endAccessingResources` num pedido que
    /// ainda não terminou de começar é o mesmo erro que derrubava o app.)
    func soltar(_ tag: String) {
        if emCurso[tag] != nil {
            soltarAoChegar.insert(tag)
            return
        }
        pedidos.removeValue(forKey: tag)?.endAccessingResources()
        // Solto, o pacote pode sumir a qualquer momento: `.pronto` aqui faria
        // o `RootView` abrir o livro sem pedido nenhum segurando a arte.
        estados[tag] = nil
    }

    /// Livro já lido fica na frente da fila de quem PERMANECE no aparelho.
    func preservar(_ tag: String, prioridade: Double = 0.9) {
        pedidos[tag]?.bundle.setPreservationPriority(prioridade, forTags: [tag])
    }

    /// Antecipa pacotes em segundo plano, sem pressa e sem bloquear ninguém.
    /// A Home usa para as três histórias da semana: quando a criança toca,
    /// o livro já está aqui.
    func antecipar(_ tags: [String]) {
        for tag in tags where pedidos[tag] == nil && emCurso[tag] == nil {
            Task { await garantir(tag, urgente: false) }
        }
    }

    // MARK: Progresso

    private func acompanhar(_ pedido: NSBundleResourceRequest, tag: String) -> Task<Void, Never> {
        Task { [weak pedido] in
            while !Task.isCancelled, let pedido {
                let fracao = pedido.progress.fractionCompleted
                if estados[tag] != .pronto { estados[tag] = .baixando(fracao) }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }
}

extension Book {
    /// Tag do pacote com a arte das páginas deste livro.
    var artTag: String { "livro-\(id)" }
}
