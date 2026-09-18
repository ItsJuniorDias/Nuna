//
//  Faixa.swift
//  Nuna
//
//  Faixas de tempo e de contagem para o analytics. Duração exata e número
//  exato não saem do aparelho: combinados, viram impressão digital de uma
//  família. A faixa responde o que o produto precisa ("leu por 2 a 5
//  minutos") sem descrever ninguém.
//
//  Limite de cima exclusivo em todas: 5 s cai em "5_15s", não em "lt_5s".
//  Os textos são os valores do catálogo (events.json) — mudar um aqui sem
//  mudar lá faz o servidor recusar o evento.
//
//  Tempo medido com `Date`, nunca `systemUptime`/`mach_absolute_time`: esses
//  entram na lista de APIs com motivo declarado no manifesto de privacidade.
//

import Foundation

enum Faixa {
    /// Onboarding, paywall e portão parental.
    static func curta(_ s: TimeInterval) -> String {
        switch s {
        case ..<5:   return "lt_5s"
        case ..<15:  return "5_15s"
        case ..<30:  return "15_30s"
        case ..<60:  return "30_60s"
        case ..<180: return "1_3m"
        default:     return "gte_3m"
        }
    }

    /// Tempo com o livro aberto.
    static func leitura(_ s: TimeInterval) -> String {
        switch s {
        case ..<10:   return "lt_10s"
        case ..<30:   return "10_30s"
        case ..<60:   return "30_60s"
        case ..<120:  return "1_2m"
        case ..<300:  return "2_5m"
        case ..<600:  return "5_10m"
        case ..<1200: return "10_20m"
        default:      return "gte_20m"
        }
    }

    /// Tempo numa página antes de virar.
    static func permanencia(_ s: TimeInterval) -> String {
        switch s {
        case ..<2:  return "lt_2s"
        case ..<5:  return "2_5s"
        case ..<15: return "5_15s"
        case ..<60: return "15_60s"
        default:    return "gte_60s"
        }
    }

    static func segundoPlano(_ s: TimeInterval) -> String {
        switch s {
        case ..<60:   return "lt_1m"
        case ..<300:  return "1_5m"
        case ..<1800: return "5_30m"
        default:      return "gte_30m"
        }
    }

    static func primeiroPlano(_ s: TimeInterval) -> String {
        switch s {
        case ..<60:   return "lt_1m"
        case ..<300:  return "1_5m"
        case ..<900:  return "5_15m"
        case ..<1800: return "15_30m"
        case ..<3600: return "30_60m"
        default:      return "gte_60m"
        }
    }

    static func cargaDoCatalogo(_ s: TimeInterval) -> String {
        switch s {
        case ..<0.05: return "lt_50ms"
        case ..<0.2:  return "50_200ms"
        case ..<1:    return "200_1000ms"
        default:      return "gte_1s"
        }
    }

    static func buscaDeProdutos(_ s: TimeInterval) -> String {
        switch s {
        case ..<1:  return "lt_1s"
        case ..<3:  return "1_3s"
        case ..<10: return "3_10s"
        default:    return "gte_10s"
        }
    }

    /// Só o tamanho da busca, nunca o texto: o que a criança digita não sai
    /// do aparelho.
    static func tamanhoDaBusca(_ n: Int) -> String {
        switch n {
        case ...2:  return "1_2"
        case ...5:  return "3_5"
        case ...10: return "6_10"
        default:    return "gte_11"
        }
    }

    static func livrosEmAndamento(_ n: Int) -> String {
        switch n {
        case ...1: return "1"
        case ...5: return "2_5"
        default:   return "6_plus"
        }
    }
}

/// Cronômetro que só anda com o app na frente: livro esquecido aberto com o
/// aparelho no bolso não pode contar como vinte minutos de leitura.
struct RelogioAtivo {
    private(set) var acumulado: TimeInterval = 0
    private(set) var desde: Date?

    mutating func retomar() {
        if desde == nil { desde = .now }
    }

    mutating func pausar() {
        guard let inicio = desde else { return }
        acumulado += Date.now.timeIntervalSince(inicio)
        desde = nil
    }

    var total: TimeInterval {
        acumulado + (desde.map { Date.now.timeIntervalSince($0) } ?? 0)
    }
}
