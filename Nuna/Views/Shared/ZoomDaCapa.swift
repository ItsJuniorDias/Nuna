//
//  ZoomDaCapa.swift
//  Nuna
//
//  O livro abre crescendo a partir da capa tocada e, ao fechar, encolhe de
//  volta para ela. A criança vê de onde o livro veio e para onde ele volta.
//
//  O `RootView` é dono do namespace e publica no ambiente; cada capa tocável
//  se marca como origem com um id que diz ONDE ela está ("semana-…",
//  "chegaram-…", "biblioteca-…"; ver `OrigemDaLeitura.idDoZoom`). O mesmo
//  livro aparece em várias prateleiras ao mesmo tempo, então o id do livro
//  sozinho não basta.
//
//  Sem sombra na origem (regra do DS) e recorte no mesmo raio da capa, para
//  a forma não "pular" no começo do zoom.
//

import SwiftUI

extension EnvironmentValues {
    /// Namespace do zoom capa → leitor. `nil` fora do `RootView` (prévias).
    @Entry var zoomDasCapas: Namespace.ID? = nil

    /// Tem tela cheia por cima da Home: o leitor ou a página de um livro.
    ///
    /// As duas são `fullScreenCover`, e a Home NÃO sai da hierarquia atrás
    /// delas. Sem isto, o vídeo da capa em foco continua montado e disputando
    /// o player com quem está na frente — e cada virada de página, que salva o
    /// progresso, ainda redesenha a Home invisível.
    @Entry var homeCoberta: Bool = false
}

extension View {
    /// Marca esta capa como origem do zoom que abre o leitor.
    func origemDoZoom(_ id: String, raio: CGFloat) -> some View {
        modifier(OrigemDoZoom(id: id, raio: raio))
    }
}

private struct OrigemDoZoom: ViewModifier {
    let id: String
    let raio: CGFloat

    @Environment(\.zoomDasCapas) private var namespace

    @ViewBuilder
    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace) { origem in
                origem
                    .clipShape(RoundedRectangle(cornerRadius: raio, style: .continuous))
                    .background(UITokens.surface)
            }
        } else {
            content
        }
    }
}
