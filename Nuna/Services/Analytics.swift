//
//  Analytics.swift
//  Nuna
//
//  Analytics de produto, só para uso interno: uso agregado, funis e
//  confiabilidade. Nunca perfil, anúncio ou contato com a criança.
//
//  App da categoria Kids (diretrizes 1.3 e 5.1.2) e COPPA, na exceção de
//  "operações internas". Por isso o que NÃO existe aqui é o que importa:
//    - nenhum identificador de pessoa, aparelho ou instalação. Nada de IDFA,
//      `identifierForVendor`, nome ou modelo do aparelho — só a família
//      (phone, pad, other). O único id é o da sessão: aleatório a cada
//      lançamento, trocado depois de 30 minutos em segundo plano, e nunca
//      gravado fora da fila;
//    - nada de texto digitado, título, nome ou localização. O que pode sair
//      está preso nos tipos de `AnalyticsEvent`. O país que vai junto é o da
//      conta da App Store (StoreKit), não onde o aparelho está;
//    - nenhum SDK de terceiros. Um POST para servidor próprio, sem cookie,
//      sem cache, e sem cabeçalho além do tipo e da chave do app — que é a
//      mesma em todos os aparelhos.
//
//  O responsável desliga em Parents > "Share anonymous usage data" (ligado
//  por padrão). Desligado, nada entra na fila e a fila salva é apagada.
//
//  Fila: memória primeiro, disco em Application Support (fora do backup),
//  no máximo 500 eventos e 7 dias. Envia com 20 na fila, a cada 30 s com o
//  app na frente e ao ir para segundo plano.
//

import Foundation
import StoreKit
import UIKit
import os

// MARK: - Configuração

/// ┌──────────────────────────────────────────────────────────────────────┐
/// │ FLAG DE DEV: mandar eventos rodando pelo Xcode (build Debug).        │
/// │                                                                      │
/// │   false → Debug não manda nada (padrão)                              │
/// │   true  → Debug manda para o mesmo servidor de produção              │
/// │                                                                      │
/// │ TestFlight e App Store (build Release) SEMPRE mandam, qualquer que   │
/// │ seja o valor daqui.                                                  │
/// └──────────────────────────────────────────────────────────────────────┘
///
/// Desligado por padrão porque o servidor é um só: evento de teste entraria
/// no painel misturado com o uso real. Ligue para testar, confira no painel
/// e desligue antes de commitar.
nonisolated enum AnalyticsDev {
    static let enviarEventosEmDebug = false
}

/// Endereço e chave do servidor. Por padrão, o de produção no Render; o
/// Info.plist pode trocar (`NunaAnalyticsURL`, `NunaAnalyticsKey`), por
/// exemplo para apontar um build para um servidor local.
nonisolated struct AnalyticsConfig: Sendable {
    let baseURL: URL
    let appKey: String

    static let urlPadrao = URL(string: "https://analytics-nuna.onrender.com")!

    /// Uma das `NUNA_APP_KEYS` do serviço no Render, lida do `Segredos.plist`
    /// — arquivo local, fora do repositório (ver README).
    ///
    /// Não é segredo no sentido forte: ela viaja dentro do app e só permite
    /// mandar eventos do catálogo. Mas o repositório é público, e escrita no
    /// código ela virava convite para encher o banco de eventos falsos. Sem o
    /// arquivo (um clone novo), a chave sai vazia e o analytics fica
    /// desligado. Trocou a chave no Render? Mantenha a antiga junto (separadas
    /// por vírgula) até os apps com ela saírem de uso.
    static var chaveLocal: String {
        guard let url = Bundle.main.url(forResource: "Segredos", withExtension: "plist"),
              let dados = try? Data(contentsOf: url),
              let lista = try? PropertyListSerialization.propertyList(
                  from: dados, format: nil) as? [String: Any]
        else { return "" }
        return (lista["NunaAnalyticsKey"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static let atual: AnalyticsConfig = {
        let info = Bundle.main.infoDictionary
        // Build setting não definido chega vazio no Info.plist gerado.
        let texto = (info?["NunaAnalyticsURL"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let chave = (info?["NunaAnalyticsKey"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return AnalyticsConfig(
            baseURL: URL(string: texto).flatMap { $0.host() == nil ? nil : $0 } ?? urlPadrao,
            appKey: chave.isEmpty ? chaveLocal : chave
        )
    }()

    /// Se o analytics funciona neste build: Release sempre; Debug só com a
    /// flag de DEV ligada. Desligado, nada entra na fila e nada sai.
    var configurado: Bool {
        #if DEBUG
        guard AnalyticsDev.enviarEventosEmDebug else { return false }
        #endif
        // Sem chave o servidor recusaria tudo: melhor nem enfileirar.
        guard !appKey.isEmpty, let host = baseURL.host() else { return false }
        return !host.isEmpty
    }

    var endpoint: URL { baseURL.appending(path: "v1/events") }
}

// MARK: - Fila

/// Campos que valem para o lote inteiro no envio. Um lote só leva eventos
/// com o mesmo contexto: a fila atravessa lançamentos, atualização do app e
/// troca de sessão.
nonisolated struct ContextoDoLote: Codable, Hashable, Sendable {
    let sessionId: String
    let appVersion: String
    let build: String
    let osVersion: String
    let deviceFamily: String
    /// País da conta da App Store, ISO 3166-1 alfa-3 ("BRA"). `nil` enquanto
    /// o StoreKit não responde ou sem conta Apple: sai do JSON, nunca `null`.
    /// Fila gravada antes deste campo lê como `nil`.
    let storefront: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case appVersion = "app_version"
        case build
        case osVersion = "os_version"
        case deviceFamily = "device_family"
        case storefront
    }
}

nonisolated struct EventoNaFila: Codable, Sendable {
    let eventId: String
    let nome: String
    /// ISO 8601 em UTC com milissegundos.
    let timestamp: String
    /// Segundos desde 1970, só para descartar evento vencido sem reler a data.
    let criadoEm: TimeInterval
    let propriedades: [String: ValorAnalitico]
    /// Muda no meio da sessão (dobrar o Duo), então vai por evento.
    let layout: String?
    /// Muda no meio da sessão (compra), então vai por evento.
    let estadoDaAssinatura: String
    let contexto: ContextoDoLote
}

/// Corpo do POST, no formato combinado com o servidor.
private nonisolated struct CorpoDoEnvio: Encodable {
    let context: ContextoDoLote
    let events: [EventoDoEnvio]
}

private nonisolated struct EventoDoEnvio: Encodable {
    let eventId: String
    let name: String
    let timestamp: String
    let properties: [String: ValorAnalitico]
    let layout: String?
    let subscriptionState: String

    init(_ evento: EventoNaFila) {
        eventId = evento.eventId
        name = evento.nome
        timestamp = evento.timestamp
        properties = evento.propriedades
        layout = evento.layout
        subscriptionState = evento.estadoDaAssinatura
    }

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case name, timestamp, properties, layout
        case subscriptionState = "subscription_state"
    }
}

private nonisolated enum ResultadoDoEnvio: Sendable {
    /// 2xx: o servidor ficou com o lote (aceitos, duplicados e recusados).
    case entregue
    /// 4xx definitivo: lote com defeito de esquema. Repetir não conserta, e
    /// um lote envenenado travaria a fila inteira.
    case descartado
    /// Sem rede, 5xx, 429, chave recusada: fica para depois.
    case tentarDepois
}

/// Disco fora do MainActor. Cada gravação leva a versão da fila de quando
/// foi pedida, e versão velha que chega atrasada não sobrescreve a nova —
/// nem ressuscita uma fila que o responsável mandou apagar.
private actor DiscoDaFila {
    private var versaoGravada = -1
    private let arquivo: URL? = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appending(path: "Analytics", directoryHint: .isDirectory)
        .appending(path: "fila.json", directoryHint: .notDirectory)

    func ler() -> [EventoNaFila] {
        guard let arquivo, let dados = try? Data(contentsOf: arquivo) else { return [] }
        // Fila ilegível (formato antigo, arquivo cortado) vale menos que o
        // app abrir: descarta e segue.
        return (try? JSONDecoder().decode([EventoNaFila].self, from: dados)) ?? []
    }

    func gravar(_ eventos: [EventoNaFila], versao: Int) {
        guard versao > versaoGravada, let arquivo else { return }
        versaoGravada = versao
        guard !eventos.isEmpty else {
            try? FileManager.default.removeItem(at: arquivo)
            return
        }
        do {
            var pasta = arquivo.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
            // Application Support entra no backup do iCloud; a fila não tem
            // o que fazer num backup.
            var valores = URLResourceValues()
            valores.isExcludedFromBackup = true
            try? pasta.setResourceValues(valores)
            try JSONEncoder().encode(eventos).write(to: arquivo, options: .atomic)
        } catch {
            // Perder a fila é aceitável; derrubar o app por ela, não.
        }
    }

    func apagar(versao: Int) {
        versaoGravada = max(versaoGravada, versao)
        guard let arquivo else { return }
        try? FileManager.default.removeItem(at: arquivo)
    }
}

// MARK: - Analytics

@MainActor
final class Analytics {
    static let shared = Analytics()

    /// Chave do interruptor da área dos pais. Ausente vale ligado.
    nonisolated static let chaveCompartilhar = "analyticsEnabled"

    private(set) var compartilhar = true

    /// Layout do leitor aberto; `nil` fora do leitor. Vai em cada evento.
    var layoutDoLeitor: LayoutDoLeitor?

    /// Preenchido pela `Store` depois da primeira conferência da assinatura.
    var estadoDaAssinatura: EstadoDaAssinatura = .unknown

    /// País da conta da App Store (ver `observarLoja`).
    private var storefront: String?
    private var escutaDaLoja: Task<Void, Never>?

    private let config = AnalyticsConfig.atual
    private let disco = DiscoDaFila()
    private let sessao: URLSession
    private let formatoDaHora: ISO8601DateFormatter

    private let appVersion: String
    private let build: String
    private let osVersion: String
    private let deviceFamily: String

    private var iniciado = false
    /// `app_opened` já saiu neste processo.
    private var sessaoAberta = false
    private var sessionId = Analytics.novoUUID()
    private var inicioDoPrimeiroPlano = Date()
    private var entrouEmSegundoPlano: Date?
    private var ativo = false
    /// Chaves já registradas nesta sessão (`track(_:umaVezPorSessao:)`).
    private var chavesDaSessao: Set<String> = []

    private var fila: [EventoNaFila] = []
    /// Até a fila do disco chegar, nada grava nem envia: gravar antes
    /// sobrescreveria os eventos salvos com a fila nova, quase vazia.
    private var carregouDisco = false
    private var versaoDaFila = 0
    private var gravacao: Task<Void, Never>?

    private var enviando: Task<Void, Never>?
    /// Sobe ao desligar: resposta de um envio cancelado não mexe na fila.
    private var geracaoDoEnvio = 0
    private var falhasSeguidas = 0
    private var proximaTentativa: Date?
    private var temporizador: Task<Void, Never>?
    private var tarefaDeFundo: UIBackgroundTaskIdentifier = .invalid

    #if DEBUG
    private var avisouSemConfig = false
    #endif

    private static let limiteDaFila = 500
    private static let loteMaximo = 100
    private static let enviarCom = 20
    private static let intervaloDeEnvio: Duration = .seconds(30)
    private static let atrasoDaGravacao: Duration = .seconds(2)
    private static let validade: TimeInterval = 7 * 24 * 60 * 60
    private static let rotacaoDaSessao: TimeInterval = 30 * 60
    private static let esperaMinima: TimeInterval = 30
    private static let esperaMaxima: TimeInterval = 30 * 60

    nonisolated private static let log = Logger(subsystem: "alexandrejunior.Nuna", category: "Analytics")

    private init() {
        // Efêmera e sem cookie nem cache: nada do envio fica no aparelho, e
        // nada de uma resposta volta no envio seguinte.
        let configuracao = URLSessionConfiguration.ephemeral
        configuracao.httpCookieAcceptPolicy = .never
        configuracao.httpShouldSetCookies = false
        configuracao.httpCookieStorage = nil
        configuracao.urlCache = nil
        configuracao.timeoutIntervalForRequest = 20
        sessao = URLSession(configuration: configuracao)

        let formato = ISO8601DateFormatter()
        formato.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatoDaHora = formato

        let info = Bundle.main.infoDictionary
        appVersion = Self.numeroDeVersao(info?["CFBundleShortVersionString"] as? String,
                                         padrao: "^[0-9]{1,4}(\\.[0-9]{1,4}){0,2}$")
        build = Self.numeroDeVersao(info?["CFBundleVersion"] as? String,
                                    padrao: "^[0-9]{1,8}(\\.[0-9]{1,4}){0,2}$")
        let so = ProcessInfo.processInfo.operatingSystemVersion
        osVersion = so.patchVersion > 0
            ? "\(so.majorVersion).\(so.minorVersion).\(so.patchVersion)"
            : "\(so.majorVersion).\(so.minorVersion)"
        // Só a família. O Duo responde phone; modelo e nome ficam de fora.
        switch UIDevice.current.userInterfaceIdiom {
        case .phone: deviceFamily = "phone"
        case .pad:   deviceFamily = "pad"
        default:     deviceFamily = "other"
        }
    }

    /// UUID v4 em minúsculas, o formato que o catálogo aceita.
    nonisolated static func novoUUID() -> String { UUID().uuidString.lowercased() }

    // MARK: Ciclo de vida

    /// Chamado no `init` do app. Não registra evento: o sistema pode
    /// pré-aquecer o processo sem o app nunca aparecer.
    func start() {
        guard !iniciado else { return }
        iniciado = true
        compartilhar = UserDefaults.standard.object(forKey: Self.chaveCompartilhar) as? Bool ?? true

        guard compartilhar, config.configurado else {
            versaoDaFila += 1
            let versao = versaoDaFila
            Task { await disco.apagar(versao: versao) }
            return
        }
        observarLoja()
        carregarDisco()
    }

    /// País da conta da App Store, para o painel quebrar vendas e uso por
    /// país. É a loja da conta Apple, não a posição do aparelho: não usa
    /// localização nem pede permissão. Troca rara (conta ou país da conta
    /// mudou); a escuta pega a troca com o app aberto. Eventos de antes da
    /// primeira resposta saem sem país.
    ///
    /// Build Debug não manda país: rodando pelo Xcode, o StoreKit responde com
    /// a loja do `Nuna.storekit` (hoje `USA`), não a da conta Apple — o painel
    /// mostraria Estados Unidos para quem está no Brasil. TestFlight e App
    /// Store usam a loja real da conta.
    private func observarLoja() {
        #if DEBUG
        return
        #else
        guard escutaDaLoja == nil else { return }
        escutaDaLoja = Task { [weak self] in
            let atual = await Storefront.current
            self?.storefront = Analytics.codigoDaLoja(atual?.countryCode)
            for await loja in Storefront.updates {
                self?.storefront = Analytics.codigoDaLoja(loja.countryCode)
            }
        }
        #endif
    }

    /// Só três letras maiúsculas, o padrão do catálogo; qualquer outra coisa
    /// faria o servidor recusar o lote inteiro.
    nonisolated private static func codigoDaLoja(_ codigo: String?) -> String? {
        guard let codigo, codigo.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else {
            return nil
        }
        return codigo
    }

    /// Fase agregada do app ficou `.active`.
    func cenaAtiva() {
        ativo = true
        if temporizador == nil { ligarTemporizador() }

        if !sessaoAberta {
            sessaoAberta = true
            inicioDoPrimeiroPlano = .now
            track(.appOpened(onboardingConcluido: UserDefaults.standard.bool(forKey: "onboardingConcluido")))
            return
        }

        // Sem passagem por segundo plano: folha da App Store, Face ID ou
        // Central de Controle. Não é volta ao app.
        guard let saiu = entrouEmSegundoPlano else { return }
        entrouEmSegundoPlano = nil

        let fora = Date.now.timeIntervalSince(saiu)
        let girou = fora >= Self.rotacaoDaSessao
        if girou {
            sessionId = Self.novoUUID()
            chavesDaSessao.removeAll()
        }
        inicioDoPrimeiroPlano = .now
        // Já com o id novo: a volta abre a sessão nova.
        track(.appForegrounded(foraPor: fora, sessaoGirou: girou))
    }

    /// Fase agregada do app ficou `.background`.
    func foiParaSegundoPlano() {
        ativo = false
        temporizador?.cancel()
        temporizador = nil

        guard sessaoAberta, entrouEmSegundoPlano == nil else { return }
        entrouEmSegundoPlano = .now
        track(.appBackgrounded(ativoPor: Date.now.timeIntervalSince(inicioDoPrimeiroPlano)))
        esvaziarAntesDeSuspender()
    }

    /// Interruptor da área dos pais. Nenhum evento registra a escolha.
    func definirCompartilhamento(_ ligado: Bool) {
        guard ligado != compartilhar else { return }
        compartilhar = ligado

        if ligado {
            falhasSeguidas = 0
            proximaTentativa = nil
            guard config.configurado else { return }
            observarLoja()
            if !carregouDisco { carregarDisco() }
            if ativo { ligarTemporizador() }
        } else {
            geracaoDoEnvio += 1
            enviando?.cancel()
            enviando = nil
            gravacao?.cancel()
            gravacao = nil
            temporizador?.cancel()
            temporizador = nil
            fila.removeAll()
            versaoDaFila += 1
            let versao = versaoDaFila
            Task { await disco.apagar(versao: versao) }
        }
    }

    // MARK: Registro

    func track(_ evento: AnalyticsEvent) {
        guard compartilhar else { return }
        guard config.configurado else {
            #if DEBUG
            if !avisouSemConfig {
                avisouSemConfig = true
                Self.log.debug("Analytics desligado neste build Debug: ligue AnalyticsDev.enviarEventosEmDebug para mandar eventos")
            }
            #endif
            return
        }

        let agora = Date()
        let propriedades = evento.propriedades
        fila.append(EventoNaFila(
            eventId: Self.novoUUID(),
            nome: evento.nome,
            timestamp: formatoDaHora.string(from: agora),
            criadoEm: agora.timeIntervalSince1970,
            propriedades: propriedades,
            layout: layoutDoLeitor?.rawValue,
            estadoDaAssinatura: estadoDaAssinatura.rawValue,
            contexto: ContextoDoLote(sessionId: sessionId, appVersion: appVersion, build: build,
                                     osVersion: osVersion, deviceFamily: deviceFamily,
                                     storefront: storefront)
        ))
        if fila.count > Self.limiteDaFila {
            fila.removeFirst(fila.count - Self.limiteDaFila)
        }
        versaoDaFila += 1

        #if DEBUG
        Self.log.debug("\(evento.nome, privacy: .public) \(String(describing: propriedades), privacy: .public)")
        #endif

        agendarGravacao()
        if fila.count >= Self.enviarCom { enviar() }
    }

    /// Para o que só interessa uma vez por sessão, como seção da Home vista:
    /// a Home reaparece a cada livro fechado, e a lista preguiçosa cria e
    /// descarta as seções enquanto rola. A sessão nova zera as chaves.
    func track(_ evento: AnalyticsEvent, umaVezPorSessao chave: String) {
        guard compartilhar, chavesDaSessao.insert(chave).inserted else { return }
        track(evento)
    }

    // MARK: Disco

    private func carregarDisco() {
        Task {
            let salvos = await disco.ler()
            // Desligado enquanto lia: a fila salva já foi mandada apagar.
            guard compartilhar, !carregouDisco else { return }
            let limite = Date.now.timeIntervalSince1970 - Self.validade
            let validos = salvos.filter { $0.criadoEm >= limite }
            fila = Array((validos + fila).suffix(Self.limiteDaFila))
            carregouDisco = true
            versaoDaFila += 1
            agendarGravacao()
            if fila.count >= Self.enviarCom { enviar() }
        }
    }

    /// Várias escritas seguidas (virar páginas) viram uma gravação só.
    private func agendarGravacao() {
        guard carregouDisco, gravacao == nil else { return }
        gravacao = Task {
            try? await Task.sleep(for: Self.atrasoDaGravacao)
            guard !Task.isCancelled else { return }
            gravacao = nil
            await gravar()
        }
    }

    private func gravarAgora() async {
        gravacao?.cancel()
        gravacao = nil
        await gravar()
    }

    private func gravar() async {
        guard carregouDisco, compartilhar else { return }
        await disco.gravar(fila, versao: versaoDaFila)
    }

    // MARK: Envio

    private func ligarTemporizador() {
        temporizador?.cancel()
        guard compartilhar, config.configurado else {
            temporizador = nil
            return
        }
        temporizador = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.intervaloDeEnvio)
                guard !Task.isCancelled else { return }
                enviar()
            }
        }
    }

    private func enviar() {
        guard compartilhar, config.configurado, carregouDisco, enviando == nil else { return }
        if let espera = proximaTentativa, espera > .now { return }

        let limite = Date.now.timeIntervalSince1970 - Self.validade
        if fila.contains(where: { $0.criadoEm < limite }) {
            fila.removeAll { $0.criadoEm < limite }
            versaoDaFila += 1
            agendarGravacao()
        }

        guard let primeiro = fila.first else { return }
        let lote = Array(fila.lazy.filter { $0.contexto == primeiro.contexto }.prefix(Self.loteMaximo))
        let config = config
        let sessao = sessao
        let geracao = geracaoDoEnvio

        enviando = Task {
            let resultado = await Self.postar(lote, config: config, sessao: sessao)
            concluirEnvio(lote, resultado, geracao: geracao)
        }
    }

    private func concluirEnvio(_ lote: [EventoNaFila], _ resultado: ResultadoDoEnvio, geracao: Int) {
        guard geracao == geracaoDoEnvio else { return }
        enviando = nil

        switch resultado {
        case .entregue, .descartado:
            let ids = Set(lote.map(\.eventId))
            fila.removeAll { ids.contains($0.eventId) }
            versaoDaFila += 1
            agendarGravacao()
            falhasSeguidas = 0
            proximaTentativa = nil
            // Esvazia o resto (outra sessão, ou mais de 100 na fila).
            if !fila.isEmpty { enviar() }

        case .tentarDepois:
            // 30 s, 1 min, 2 min... até 30 min. Servidor fora do ar não pode
            // virar uma requisição a cada evento em milhares de aparelhos.
            falhasSeguidas += 1
            let espera = min(Self.esperaMaxima,
                             Self.esperaMinima * pow(2, Double(min(falhasSeguidas - 1, 10))))
            proximaTentativa = .now + espera
        }
    }

    /// Com o app indo para segundo plano, o iOS dá alguns segundos: grava a
    /// fila, envia o que der e grava de novo o que sobrou.
    private func esvaziarAntesDeSuspender() {
        guard compartilhar, config.configurado, tarefaDeFundo == .invalid else { return }
        tarefaDeFundo = UIApplication.shared.beginBackgroundTask(withName: "Nuna.analytics") {
            Analytics.shared.encerrarTarefaDeFundo()
        }
        let tarefa = tarefaDeFundo
        Task {
            await gravarAgora()
            enviar()
            while let envio = enviando { await envio.value }
            await gravarAgora()
            encerrarTarefaDeFundo(tarefa)
        }
    }

    private func encerrarTarefaDeFundo(_ tarefa: UIBackgroundTaskIdentifier? = nil) {
        guard tarefaDeFundo != .invalid, tarefa == nil || tarefa == tarefaDeFundo else { return }
        UIApplication.shared.endBackgroundTask(tarefaDeFundo)
        tarefaDeFundo = .invalid
    }

    /// Fora do MainActor: montar o JSON e esperar a rede não passa pela
    /// fila da interface.
    @concurrent
    nonisolated private static func postar(_ lote: [EventoNaFila], config: AnalyticsConfig,
                                           sessao: URLSession) async -> ResultadoDoEnvio {
        guard let primeiro = lote.first else { return .entregue }
        let corpo = CorpoDoEnvio(context: primeiro.contexto, events: lote.map(EventoDoEnvio.init))
        guard let dados = try? JSONEncoder().encode(corpo) else { return .descartado }

        var pedido = URLRequest(url: config.endpoint)
        pedido.httpMethod = "POST"
        pedido.setValue("application/json", forHTTPHeaderField: "Content-Type")
        pedido.setValue(config.appKey, forHTTPHeaderField: "X-Nuna-Key")
        pedido.httpBody = dados

        do {
            let (resposta, retorno) = try await sessao.data(for: pedido)
            guard let http = retorno as? HTTPURLResponse else { return .tentarDepois }
            switch http.statusCode {
            case 200..<300:
                #if DEBUG
                if let json = try? JSONSerialization.jsonObject(with: resposta) as? [String: Any],
                   let recusados = json["rejected"] as? [Any], !recusados.isEmpty {
                    log.error("Servidor recusou \(recusados.count) evento(s): \(String(describing: recusados), privacy: .public)")
                }
                #endif
                return .entregue
            case 401, 403, 408, 429:
                return .tentarDepois
            case 400..<500:
                log.error("Lote de \(lote.count) evento(s) descartado: HTTP \(http.statusCode)")
                return .descartado
            default:
                return .tentarDepois
            }
        } catch {
            return .tentarDepois
        }
    }

    // MARK: Auxiliares

    /// Versão fora do formato do catálogo faria o servidor recusar todo
    /// evento; melhor mandar "0" e perceber no painel.
    private static func numeroDeVersao(_ texto: String?, padrao: String) -> String {
        guard let texto, texto.range(of: padrao, options: .regularExpression) != nil else { return "0" }
        return texto
    }
}
