//
//  Postura.swift
//  Nuna
//
//  Como a tela se divide no iPhone Duo — e, de brinde, no iPad e no iPhone
//  deitado. Um arquivo só decide; as telas só perguntam.
//
//  A regra da Apple para o Duo: o app redimensiona em toda pose (fechado,
//  aberto na vertical, aberto na horizontal, dobrado como livro), e o layout
//  decide pelo espaço que recebeu — nunca por modelo de aparelho, orientação
//  ou `UIScreen.main`, que num aparelho de dois displays é ambíguo.
//
//  Aberto na horizontal, a dobra corta o display interno ao meio no sentido
//  vertical. Imagem ou teclado atravessando a dobra ficam tortos quando o
//  aparelho está meio fechado. Então, com espaço largo, a tela vira DUAS
//  METADES com uma calha no meio, e nada importante pousa na calha. Conteúdo
//  que rola (listas, prateleiras) pode atravessar: a rolagem já resolve.
//
//  TODO(Xcode 27.1): trocar a heurística de geometria pela dobra real —
//  `proxy.reservedRegions(kind: .division, options: .includeInactive)` num
//  `onGeometryChange`. Com `.includeInactive` a dobra aparece mesmo com o
//  aparelho plano, e aí `duasMetades` vira "existe região de divisão
//  vertical" e a calha passa a ser o frame dela. O SDK 27.0 ainda não tem
//  a API; só este arquivo muda.
//

import SwiftUI

/// `nonisolated`: o projeto isola tudo no MainActor por padrão, e o valor
/// padrão do `@Entry` é criado fora dele.
nonisolated struct Postura: Equatable, Sendable {
    /// Espaço que a tela recebeu, já sem safe area.
    var tamanho: CGSize = .zero
    var horizontal: UserInterfaceSizeClass? = nil

    /// Duas metades lado a lado, com a dobra (ou o meio da tela) na calha.
    ///
    /// Size class regular E mais larga que alta: Duo aberto na horizontal e
    /// iPad deitado. O Duo fechado deitado é compact — ali a tela é estreita
    /// demais para duas colunas de interface. O Duo aberto na vertical é
    /// regular mas mais alto que largo: a dobra fica deitada, e conteúdo que
    /// rola atravessa sem problema.
    var duasMetades: Bool {
        horizontal == .regular
            && tamanho.width > tamanho.height
            && tamanho.width >= Self.larguraMinima
    }

    /// Abaixo disto cada metade teria menos que um iPhone pequeno.
    static let larguraMinima: CGFloat = 640

    /// Calha no meio das duas metades. Nunca menor que a margem grande do
    /// app (`Space.xxl`), e cresce com a tela para cobrir a curva da dobra —
    /// a mesma proporção que a arte dos livros deixa livre no vinco
    /// (`SafeZone.vinco`). Repetidos aqui porque aqueles são do MainActor.
    var calha: CGFloat {
        max(Self.calhaMinima, tamanho.width * Self.proporcaoCalha)
    }

    private static let calhaMinima: CGFloat = 48
    private static let proporcaoCalha: CGFloat = 0.06
}

extension EnvironmentValues {
    @Entry var postura = Postura()
}

// MARK: - Medição

private struct MedirPostura: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontal
    @State private var tamanho: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .environment(\.postura, Postura(tamanho: tamanho, horizontal: horizontal))
            // Abrir, fechar, girar ou dobrar o Duo muda o tamanho da cena e
            // chega aqui; o estado das telas sobrevive porque só o layout
            // troca — nenhuma view de estado é recriada.
            .onGeometryChange(for: CGSize.self) { $0.size } action: { tamanho = $0 }
    }
}

extension View {
    /// Mede o espaço desta tela e publica a `Postura` para o que está dentro.
    /// Vai na raiz de cada tela cheia — cada `fullScreenCover` mede a sua.
    func medirPostura() -> some View {
        modifier(MedirPostura())
    }
}

// MARK: - Duas metades

/// Duas metades iguais com a calha no meio quando a postura pede; uma coluna
/// (a primeira em cima) quando não.
///
/// As metades têm SEMPRE a mesma largura: é isso que põe a calha em cima da
/// dobra. Uma metade vazia continua ocupando o seu lado.
struct DuasMetades<Primeira: View, Segunda: View>: View {
    var alinhamento: VerticalAlignment
    var espacoEmColuna: CGFloat
    var primeira: Primeira
    var segunda: Segunda

    @Environment(\.postura) private var postura

    init(alinhamento: VerticalAlignment = .top,
         espacoEmColuna: CGFloat = Space.xl,
         @ViewBuilder primeira: () -> Primeira,
         @ViewBuilder segunda: () -> Segunda) {
        self.alinhamento = alinhamento
        self.espacoEmColuna = espacoEmColuna
        self.primeira = primeira()
        self.segunda = segunda()
    }

    var body: some View {
        if postura.duasMetades {
            HStack(alignment: alinhamento, spacing: postura.calha) {
                primeira.frame(maxWidth: .infinity)
                segunda.frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: espacoEmColuna) {
                primeira
                segunda
            }
        }
    }
}
