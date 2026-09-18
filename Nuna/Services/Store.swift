//
//  Store.swift
//  Nuna
//
//  Assinatura Nuna Premium: planos, compra, restauração e quem pode ler o quê.
//
//  Um lugar só decide se um livro abre. Se a regra ficasse espalhada pelas
//  telas, bastava uma esquecer o cadeado pra dar o acervo de graça — ou pior,
//  trancar um livro que a família já pagou. Toda view pergunta aqui.
//
//  A verdade vem sempre de `Transaction.currentEntitlements`, nunca de um
//  booleano salvo em disco: quem sabe de reembolso, Compartilhamento Familiar
//  e assinatura que venceu com o app fechado é a App Store, não o app.
//

import Foundation
import Observation
import StoreKit
import os

@Observable
final class Store {
    static let shared = Store()

    enum ProductID {
        static let mensal = "monthly_nuna"
        static let anual  = "annual_nuna"
        /// Anual primeiro: é o plano que o paywall destaca.
        static let todos  = [anual, mensal]
    }

    enum Links {
        /// Termos de uso e suporte do Nuna. Paywall e área dos pais leem
        /// daqui — trocar o link é trocar esta linha.
        static let termos = URL(string: "https://marked-garage-d75.notion.site/Nuna-Terms-of-use-Support-3de2f13e5f7d804caa8fe9f2180c2ff1")!

        /// Política de privacidade e EULA. Obrigatória na categoria Kids, e a
        /// mesma URL vai no campo Privacy Policy do App Store Connect.
        static let privacidade = URL(string: "https://marked-garage-d75.notion.site/Nuna-Privacy-Policy-EULA-3de2f13e5f7d806b8b46c3926ce026b4")!
    }

    /// Livros abertos sem assinatura.
    ///
    /// Um livro inteiro, e não "três páginas de cada": criança pequena não
    /// entende história cortada no meio, entende livro que ainda está fechado.
    static let livrosGratis: Set<String> = ["o-quintal-da-nuna"]

    /// Catálogo carregado no lançamento. A `Store` precisa dele para saber
    /// quais são as histórias da semana, que abrem sempre, com ou sem
    /// assinatura.
    var catalogo: [Book] = []

    private(set) var mensal: Product?
    private(set) var anual: Product?
    private(set) var isPremium = false

    /// Só vira `true` quando a App Store confirma. Prometer teste grátis a
    /// quem já usou o dele é o tipo de coisa que a revisão pega e o responsável
    /// não perdoa na fatura.
    private(set) var trialEligible = false

    /// Começa `true`: até a primeira busca terminar não há plano pra mostrar,
    /// e o paywall precisa exibir espera, não uma tela vazia.
    private(set) var carregandoProdutos = true
    private(set) var erroProdutos: String?

    enum ResultadoCompra { case sucesso, pendente, cancelado }

    /// Por que a assinatura foi conferida. Valores do catálogo de eventos
    /// (`subscription_status_changed.trigger`).
    enum MotivoDaConferencia: String {
        case launch
        case transactionUpdate = "transaction_update"
        case purchase
        case restore
        case foreground
        case paywallOpen = "paywall_open"
    }

    /// Quem pediu a busca dos planos (`fetch_context` no catálogo).
    enum ContextoDaBusca: String {
        case launch
        case paywallOpen = "paywall_open"
        case paywallRetry = "paywall_retry"
    }

    /// Erro de compra com texto pronto pro alerta do paywall.
    enum ErroCompra: LocalizedError {
        case naoVerificada

        var errorDescription: String? {
            switch self {
            case .naoVerificada:
                return "We couldn't confirm the purchase with the App Store. Try again or tap Restore Purchases."
            }
        }
    }

    @ObservationIgnored private var iniciado = false
    @ObservationIgnored private var buscandoProdutos = false
    @ObservationIgnored private var escutaTransacoes: Task<Void, Never>?
    /// A primeira conferência do processo já terminou. Ela é a linha de base
    /// do analytics, não uma mudança: todo assinante sai de "não premium"
    /// para "premium" a cada lançamento.
    @ObservationIgnored private var conferido = false
    /// Último plano ativo visto neste processo, para dizer qual assinatura
    /// venceu quando o acesso cai.
    @ObservationIgnored private var ultimoPlano: PlanoDaAssinatura?

    private static let log = Logger(subsystem: "alexandrejunior.Nuna", category: "Store")

    private init() {}

    // MARK: Início

    /// Chamado uma vez no lançamento. Chamar de novo não faz nada.
    func start() async {
        guard !iniciado else { return }
        iniciado = true

        // A escuta vem antes de tudo: renovação, reembolso e o "sim" do
        // responsável no Pedir Compra chegam por aqui a qualquer momento —
        // inclusive enquanto o resto ainda carrega. Uma escuta só, pra vida
        // inteira do app.
        escutaTransacoes = Task { [weak self] in
            for await resultado in Transaction.updates {
                await self?.atualizarAssinatura(motivo: .transactionUpdate)
                await self?.finalizar(resultado)
            }
        }

        // Compra que terminou com o app fechado, ou que caiu no meio, fica
        // pendurada até alguém chamar `finish()`. Sem isso a App Store
        // reentrega a mesma transação a cada abertura.
        for await resultado in Transaction.unfinished {
            await finalizar(resultado)
        }

        // Assinatura antes dos produtos: o direito de leitura sai do cache
        // local na hora, mesmo offline. Esperar a rede pra destrancar livro
        // já pago seria castigar justamente quem pagou.
        await atualizarAssinatura(motivo: .launch)
        await carregarProdutos(contexto: .launch)
    }

    // MARK: Produtos

    func carregarProdutos(contexto: ContextoDaBusca) async {
        // Lançamento e paywall podem pedir ao mesmo tempo; uma busca basta.
        // Quem pegou carona na busca em andamento não registra evento.
        guard !buscandoProdutos else { return }
        buscandoProdutos = true
        carregandoProdutos = true
        erroProdutos = nil
        let inicio = Date()
        var falha: Error?

        do {
            let produtos = try await Product.products(for: ProductID.todos)
            mensal = produtos.first { $0.id == ProductID.mensal }
            anual  = produtos.first { $0.id == ProductID.anual }
            if mensal == nil || anual == nil {
                Self.log.error("App Store devolveu \(produtos.count) de \(ProductID.todos.count) planos")
            }
        } catch {
            // Falha de rede numa nova tentativa não apaga planos que já vieram.
            falha = error
            Self.log.error("Falha ao carregar planos: \(error.localizedDescription, privacy: .public)")
        }

        // Os dois ou nenhum: o paywall pré-seleciona o anual e compara com o
        // mensal. Com um plano só, a tela mentiria sobre a escolha.
        if mensal == nil || anual == nil {
            erroProdutos = "Couldn't load the plans right now. Check your internet connection and try again."
        }

        // Elegibilidade antes de soltar o carregamento, pra o botão não
        // piscar de "Assinar" para "Começar 7 dias grátis" na frente do pai.
        await atualizarElegibilidade()

        // Mede o que o pai vê: com os dois planos na mão (mesmo de uma busca
        // anterior), o paywall vende, e isso conta como carregado.
        if erroProdutos == nil {
            Analytics.shared.track(.storeProductsLoaded(
                contexto: contexto, duracao: Date.now.timeIntervalSince(inicio),
                trialEligible: trialEligible))
        } else {
            Analytics.shared.track(.storeProductsLoadFailed(
                contexto: contexto,
                falha: falha == nil ? .incompleteResponse : .requestError,
                planosRecebidos: [mensal, anual].compactMap { $0 }.count,
                erro: falha.map(Self.categoriaDoErro)))
        }

        carregandoProdutos = false
        buscandoProdutos = false
    }

    // MARK: Assinatura

    func atualizarAssinatura(motivo: MotivoDaConferencia) async {
        var premium = false
        // Retrato da primeira assinatura válida, só para o analytics. Nunca
        // id de transação, `originalID` ou `appAccountToken`.
        var plano: PlanoDaAssinatura?
        var familia = false
        var emTeste = false
        for await resultado in Transaction.currentEntitlements {
            switch resultado {
            case .verified(let transacao):
                // Reembolsada ou vencida não vale, mesmo que ainda apareça
                // na lista. Membro da família conta como assinante.
                guard ProductID.todos.contains(transacao.productID),
                      transacao.revocationDate == nil,
                      (transacao.expirationDate ?? .distantFuture) > .now
                else { continue }
                premium = true
                if plano == nil {
                    plano = transacao.productID == ProductID.anual ? .annual : .monthly
                    familia = transacao.ownershipType == .familyShared
                    emTeste = transacao.offer?.type == .introductory
                        && transacao.offer?.paymentMode == .freeTrial
                }
            case .unverified(let transacao, let erro):
                Self.log.error("Direito não verificado \(transacao.productID, privacy: .public): \(erro.localizedDescription, privacy: .public)")
            }
        }

        // Só escreve quando muda: `@Observable` redesenha a cada escrita,
        // e isto roda toda vez que o app volta ao primeiro plano.
        let mudou = isPremium != premium
        if mudou { isPremium = premium }

        Analytics.shared.estadoDaAssinatura = premium ? .premium : .free
        // MainActor: a escuta de transações e o `start()` não disputam o
        // `conferido`.
        if conferido && mudou {
            Analytics.shared.track(.subscriptionStatusChanged(
                premium: premium, motivo: motivo,
                // Sem acesso: o último plano visto neste processo, se houver.
                plano: premium ? plano : ultimoPlano,
                familia: premium ? familia : nil,
                emTeste: premium ? emTeste : nil))
        }
        if premium { ultimoPlano = plano }
        conferido = true

        await atualizarElegibilidade()
    }

    /// Teste grátis do anual. Depende do produto carregado e da conta Apple:
    /// quem já assinou qualquer plano do grupo perde o direito.
    private func atualizarElegibilidade() async {
        var elegivel = false
        if let assinatura = anual?.subscription,
           assinatura.introductoryOffer?.paymentMode == .freeTrial {
            elegivel = await assinatura.isEligibleForIntroOffer
        }
        if trialEligible != elegivel { trialEligible = elegivel }
    }

    // MARK: Compra

    func comprar(_ product: Product) async throws -> ResultadoCompra {
        let resultado: Product.PurchaseResult
        do {
            resultado = try await product.purchase()
        } catch StoreKitError.userCancelled {
            return .cancelado
        } catch {
            Self.log.error("Compra de \(product.id, privacy: .public) falhou: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        switch resultado {
        case .success(.verified(let transacao)):
            // Direito primeiro, `finish()` depois: se o app cair entre os
            // dois, a transação volta em `unfinished` e nada se perde.
            await atualizarAssinatura(motivo: .purchase)
            await transacao.finish()
            return .sucesso

        case .success(.unverified(let transacao, let erro)):
            // Transação que falhou na verificação não libera nada e não é
            // finalizada: a App Store reentrega, e o Restaurar resolve se
            // a compra era legítima.
            Self.log.error("Compra \(transacao.id) de \(transacao.productID, privacy: .public) não verificada: \(erro.localizedDescription, privacy: .public)")
            throw ErroCompra.naoVerificada

        case .pending:
            // Pedir Compra ou confirmação do banco. A aprovação chega depois
            // pela escuta de `Transaction.updates`.
            return .pendente

        case .userCancelled:
            return .cancelado

        @unknown default:
            Self.log.error("Resultado de compra desconhecido para \(product.id, privacy: .public)")
            return .cancelado
        }
    }

    /// `false` quando o adulto desistiu do login da Apple. Não é erro pra
    /// mostrar, mas também não é "sem assinatura": quem chama precisa saber
    /// a diferença.
    @discardableResult
    func restaurar() async throws -> Bool {
        var concluiu = true
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            concluiu = false
        } catch {
            Self.log.error("Restaurar falhou: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        await atualizarAssinatura(motivo: .restore)
        return concluiu
    }

    /// Categoria do erro para o analytics, na mesma ordem de
    /// `PaywallView.mensagem(de:)`. A mensagem do erro não sai do aparelho.
    static func categoriaDoErro(_ error: Error) -> CategoriaDoErro {
        switch error {
        case StoreKitError.networkError:                 return .network
        case StoreKitError.notAvailableInStorefront:     return .notAvailableInStorefront
        case Product.PurchaseError.purchaseNotAllowed:   return .purchaseNotAllowed
        case ErroCompra.naoVerificada:                   return .unverified
        case is StoreKitError:                           return .storekitOther
        case is Product.PurchaseError:                   return .purchaseErrorOther
        default:                                         return .unknown
        }
    }

    // MARK: Leitura

    func podeLer(_ book: Book) -> Bool {
        isPremium
            || Store.livrosGratis.contains(book.id)
            || ehHistoriaDaSemana(book)
    }

    /// Mesma conta da Home (`Featured.storiesOfTheWeek`): nenhum dos três
    /// cartões da semana pode mostrar cadeado.
    func ehHistoriaDaSemana(_ book: Book) -> Bool {
        Featured.storiesOfTheWeek(from: catalogo).contains { $0.id == book.id }
    }

    /// Placeholder "Em breve" não é bloqueado: ninguém pode ler ainda, e um
    /// cadeado ali venderia um livro que não existe.
    func estaBloqueado(_ book: Book) -> Bool {
        book.isAvailable && !podeLer(book)
    }

    // MARK: Transações

    private func finalizar(_ resultado: VerificationResult<Transaction>) async {
        switch resultado {
        case .verified(let transacao):
            await transacao.finish()
        case .unverified(let transacao, let erro):
            Self.log.error("Transação \(transacao.id) de \(transacao.productID, privacy: .public) não verificada: \(erro.localizedDescription, privacy: .public)")
        }
    }
}
