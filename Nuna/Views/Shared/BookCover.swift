//
//  BookCover.swift
//  Nuna
//
//  Capa de livro com o título DENTRO da arte. Todo cartão de livro do app
//  passa por aqui: a história da semana (`.destaque`) e as capas das
//  prateleiras e da Biblioteca (`.grade`).
//
//  O título é Papel sobre um degradê de Tinta que sobe do pé da capa. Texto
//  escuro sobre vidro sobre ilustração some; texto claro sobre arte
//  escurecida lê em qualquer capa. A metade de cima fica limpa — é onde moram
//  os selos de vidro.
//

import SwiftUI

struct BookCover<SobreArte: View>: View {
    let book: Book
    var estilo: Estilo = .grade

    /// Largura ÷ altura do cartão. As capas são 2:3; um cartão mais baixo
    /// recorta a arte em volta de `foco`.
    var proporcao: CGFloat = 2.0 / 3.0

    /// Altura, em fração da arte, em que a janela recortada fica centrada.
    /// 0,40 mantém o rosto da Nuna à vista nas 25 capas quando o cartão é
    /// mais baixo que a capa.
    var foco: CGFloat = 0.40

    /// Camada entre a arte e o degradê. É por onde entra o vídeo da capa: ali
    /// ele cobre a ilustração e continua POR BAIXO do degradê e do título, que
    /// é o que mantém o título legível.
    @ViewBuilder var sobreArte: () -> SobreArte

    @Environment(\.displayScale) private var escalaDaTela
    /// A capa reduzida desta grade, quando ficou pronta depois do primeiro
    /// quadro (ver `Miniaturas`).
    @State private var miniatura: UIImage?

    enum Estilo {
        /// Cartão grande da história da semana.
        case destaque
        /// Capa das prateleiras da Home e da grade da Biblioteca.
        case grade

        var raio: CGFloat { self == .destaque ? 24 : 16 }
        var fonte: Font { self == .destaque ? TypeScale.titulo : TypeScale.tituloCartao }
        var respiro: CGFloat { self == .destaque ? Space.lg : Space.sm }
        var sombraRaio: CGFloat { self == .destaque ? 20 : 8 }
        var sombraY: CGFloat { self == .destaque ? 10 : 4 }
        var sombraOpacidade: Double { self == .destaque ? 0.18 : 0.12 }
    }

    var body: some View {
        Color.clear
            .aspectRatio(proporcao, contentMode: .fit)
            .overlay { arte }
            .overlay { sobreArte() }
            .overlay { degrade }
            .overlay(alignment: .bottomLeading) { titulo }
            .clipShape(RoundedRectangle(cornerRadius: estilo.raio, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: estilo.raio, style: .continuous)
                    .strokeBorder(UITokens.ink.opacity(0.10), lineWidth: 0.5)
            }
            // A sombra é de uma FORMA atrás do cartão, não do cartão inteiro.
            // Sombra sobre imagem + degradê + título exige renderizar tudo fora
            // da tela para achar o contorno — cartão por cartão, a cada quadro
            // de rolagem. A forma já é o contorno; o cartão, opaco, a cobre.
            .background {
                RoundedRectangle(cornerRadius: estilo.raio, style: .continuous)
                    .fill(UITokens.surface)
                    .shadow(color: UITokens.ink.opacity(estilo.sombraOpacidade),
                            radius: estilo.sombraRaio, x: 0, y: estilo.sombraY)
            }
    }

    // MARK: Título

    private var titulo: some View {
        Text(book.title.resolved())
            .font(estilo.fonte)
            .foregroundStyle(UITokens.inkOnArt)
            .multilineTextAlignment(.leading)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(estilo.respiro)
    }

    /// Transparente até 42% da altura, denso onde o título assenta. As
    /// paradas intermediárias evitam a "linha" de um degradê de dois pontos.
    private var degrade: some View {
        LinearGradient(
            stops: [
                .init(color: UITokens.ink.opacity(0.00), location: 0.42),
                .init(color: UITokens.ink.opacity(0.32), location: 0.60),
                .init(color: UITokens.ink.opacity(0.72), location: 0.78),
                .init(color: UITokens.ink.opacity(0.90), location: 1.00),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    // MARK: Arte

    @ViewBuilder
    private var arte: some View {
        if let imagem = UIImage(named: book.coverImageName) {
            // Na grade, a capa reduzida; no destaque (cartão da semana,
            // página do livro), a inteira — ali ela aparece grande.
            if estilo == .grade {
                capaReduzida
            } else {
                recorte(imagem)
            }
        } else if let s = book.spreads.first {
            BandPlaceholder(colors: s.colors, bands: s.bands)
        } else {
            capaVazia
        }
    }

    /// Preenche o cartão e centra a janela visível em `foco`, sem deixar a
    /// janela sair da imagem. Com cartão 2:3 e capa 2:3 não há recorte.
    private func recorte(_ imagem: UIImage) -> some View {
        GeometryReader { geo in enquadrada(imagem, em: geo.size) }
    }

    private func enquadrada(_ imagem: UIImage, em tamanho: CGSize) -> some View {
        let escala = max(tamanho.width / imagem.size.width,
                         tamanho.height / imagem.size.height)
        let largura = imagem.size.width * escala
        let altura = imagem.size.height * escala
        let topo = min(max(foco * altura - tamanho.height / 2, 0),
                       altura - tamanho.height)

        return Image(uiImage: imagem)
            .resizable()
            .frame(width: largura, height: altura)
            .offset(x: (tamanho.width - largura) / 2, y: -topo)
    }

    /// A capa no tamanho em pixels em que aparece, pronta fora da main. Se
    /// ainda não estiver pronta (a Home prepara todas quando aparece), o
    /// Papel segura o lugar por um instante — nunca uma decodificação no
    /// meio da rolagem.
    private var capaReduzida: some View {
        GeometryReader { geo in
            let largura = Miniaturas.faixa(geo.size.width * escalaDaTela)
            Group {
                if let imagem = miniatura
                    ?? Miniaturas.shared.pronta(book.coverImageName, largura: largura) {
                    enquadrada(imagem, em: geo.size)
                } else {
                    Palette.papel
                }
            }
            .task(id: largura) {
                guard Miniaturas.shared.pronta(book.coverImageName, largura: largura) == nil
                else { return }
                miniatura = await Miniaturas.shared.preparar(book.coverImageName,
                                                             largura: largura)
            }
        }
    }

    /// Livro do catálogo ainda sem arte: campo Papel. O título vem do overlay.
    private var capaVazia: some View {
        ZStack {
            Palette.papel
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(UITokens.inkSecondary.opacity(0.6))
        }
    }
}

/// Chamada de sempre, sem camada extra: `BookCover(book:)`.
extension BookCover where SobreArte == EmptyView {
    init(book: Book, estilo: Estilo = .grade,
         proporcao: CGFloat = 2.0 / 3.0, foco: CGFloat = 0.40) {
        self.init(book: book, estilo: estilo, proporcao: proporcao,
                  foco: foco) { EmptyView() }
    }
}
