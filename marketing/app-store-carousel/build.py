#!/usr/bin/env python3
"""
Carrossel da App Store do Nuna — cinco imagens que se continuam.

Uma tira única é desenhada e cortada em cinco. Quem passa o dedo na loja vê a
próxima imagem "espiar" na borda, e a emenda entre duas imagens é o VINCO de
um livro aberto: a página da Nuna termina numa imagem e a página do bicho
começa na seguinte. É a regra do spread do sistema de design aplicada ao
próprio carrossel.

Regras do DS que moldam tudo aqui:
  - Papel e Tinta, e um acento só (o rosa da UI) no rótulo acima do título.
  - Texto só sobre Papel; título com no máximo oito palavras.
  - Faixas horizontais, profundidade só por sobreposição, sem sombra.
  - Os 6% centrais de cada spread (o vinco) caem exatamente na emenda.
  - Grão de guache como camada de pós, igual na tira inteira.

Uso:
    python3 build.py            # iPhone 6,5"  → 1242 × 2688
    python3 build.py ipad       # iPad 13"     → 2064 × 2752

Cada perfil tem a sua pasta de prints e a sua de saída:
    iphone  screens/       → export/
    ipad    screens-ipad/  → export-ipad/

Nomes dos prints (png, jpg ou jpeg), do app rodando NO aparelho do perfil —
a Apple recusa iPad com print de iPhone dentro:
    01-home  02-reader  03-library  04-parents  05-paywall
Arquivo que faltar vira um placeholder rotulado.

A pasta de saída tem só as cinco imagens finais (PNG RGB, sem alfa, como a
App Store exige) e pode ir inteira para o App Store Connect. A prévia da tira
inteira fica em build/preview-<perfil>.png.
"""

import math
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

AQUI = Path(__file__).resolve().parent
ASSETS = AQUI.parents[1] / "Nuna" / "Assets.xcassets"
BUILD = AQUI / "build"
ARTE = BUILD / "art"

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
NEW_YORK = "/System/Library/Fonts/NewYork.ttf"
SF_ROUNDED = "/System/Library/Fonts/SFNSRounded.ttf"

PAINEIS = 5

# Cor do papel DAS ILUSTRAÇÕES, medida nas margens dos spreads — um tom
# acima do Papel da UI no azul. Com o fundo no mesmo tom e o mesmo grão, a
# borda da página some e a arte parece pintada direto no fundo.
PAPEL_ARTE = (246, 242, 224)
GRAO_DESVIO = 6.5

TINTA = "#1C1815"
TINTA_SECUNDARIA = "#6B5F52"
# Acento: o mesmo rosa que a UI usa desde a troca do tijolo. Vermelho no
# rótulo de uma imagem de loja lê como aviso.
ACENTO = "#C4407A"
ROSA_CLARO = "#E8A0B8"
OLIVA = "#6B7038"
MARROM = "#4A3320"

# ------------------------------------------------------------------ conteúdo

# Título: máximo de oito palavras (regra da página do DS). Ordem pensada
# para as três primeiras, que são as que aparecem na busca.
PAINEL = [
    ("01-home",    "Home",    "Three every week", "Three stories free,\nevery week."),
    ("02-reader",  "Reader",  "Read together",    "Nuna tries it.\nThe animals do it better."),
    ("03-library", "Library", "50 books",         "Nuna and her friends,\nfor little readers."),
    ("04-parents", "Parents", "For grown-ups",    "A calm corner\njust for parents."),
    ("05-paywall", "Premium", "Nuna Premium",     "Unlock every story\nfor the whole family."),
]

# Um spread por emenda. Escolhidos com margem de Papel (sem fundo chapado de
# borda a borda) e com a Nuna e o bicho perto do vinco: as bordas do spread
# ficam atrás dos aparelhos, então personagem colado na borda some.
# Agora saem dos livros com os amigos: a emenda é o argumento de venda que a
# loja não escreve. Escolhidos com as crianças e o bicho perto do vinco (as
# bordas do spread ficam atrás dos aparelhos) e um clima diferente em cada um.
EMENDAS = [
    "spread_a-turma-da-nuna_12",     # a turma se abraça · os macacos-da-neve
    "spread_a-neve-da-nuna_03",      # Nuna e Maya de trenó · o ursinho-polar
    "spread_o-tesouro-da-nuna_08",   # Nuna e Theo dividem · os bonobos
    "spread_a-corrida-da-nuna_04",   # Nuna e Theo no saco · o canguru
]

# ------------------------------------------------------------------ perfis


@dataclass(frozen=True)
class Perfil:
    nome: str
    largura: int
    altura: int
    telas: Path
    export: Path
    # print de referência (proporção da tela e tamanho do placeholder)
    print_l: int
    print_a: int
    # aparelho
    tela_l: int
    bisel: int
    raio_tela_fracao: float
    ilha: bool
    # composição
    chao_y: int
    faixa_marrom: int
    spread_l: int
    titulo_topo: int
    rotulo_px: int
    titulo_px: int
    titulo_espaco: int
    previa_divisor: int

    @property
    def tira(self): return self.largura * PAINEIS
    @property
    def tela_a(self): return round(self.tela_l * self.print_a / self.print_l)
    @property
    def aparelho_l(self): return self.tela_l + self.bisel * 2
    @property
    def aparelho_a(self): return self.tela_a + self.bisel * 2
    @property
    def aparelho_y(self): return self.chao_y - self.aparelho_a
    @property
    def raio_tela(self): return round(self.tela_l * self.raio_tela_fracao)
    @property
    def raio_aparelho(self): return self.raio_tela + self.bisel
    @property
    def spread_a(self): return round(self.spread_l * 832 / 1248)


PERFIS = {
    # iPhone 6,5": prints de iPhone 6,9" (1320 × 2868) com Dynamic Island.
    "iphone": Perfil(
        nome="iphone", largura=1242, altura=2688,
        telas=AQUI / "screens", export=AQUI / "export",
        print_l=1320, print_a=2868,
        tela_l=720, bisel=20, raio_tela_fracao=0.141, ilha=True,
        chao_y=2500, faixa_marrom=96, spread_l=1040,
        titulo_topo=300, rotulo_px=42, titulo_px=104, titulo_espaco=28,
        previa_divisor=4,
    ),
    # iPad 13" em pé: prints de 2064 × 2752 (3:4). Tela quase quadrada e
    # cantos bem mais fechados que os do iPhone; sem ilha — a câmera do iPad
    # fica no bisel, fora da tela.
    "ipad": Perfil(
        nome="ipad", largura=2064, altura=2752,
        telas=AQUI / "screens-ipad", export=AQUI / "export-ipad",
        print_l=2064, print_a=2752,
        tela_l=1226, bisel=28, raio_tela_fracao=0.03, ilha=False,
        chao_y=2590, faixa_marrom=112, spread_l=1500,
        titulo_topo=300, rotulo_px=56, titulo_px=150, titulo_espaco=36,
        previa_divisor=6,
    ),
}

# ------------------------------------------------------------------ insumos


def conferir_fontes():
    for f in (NEW_YORK, SF_ROUNDED):
        if not Path(f).exists():
            sys.exit(f"Fonte do sistema não encontrada: {f}")


def preparar_arte():
    ARTE.mkdir(parents=True, exist_ok=True)
    for nome in EMENDAS:
        origem = ASSETS / f"{nome}.imageset" / f"{nome}.png"
        if not origem.exists():
            sys.exit(f"Spread não encontrado: {origem}")
        shutil.copy(origem, ARTE / f"{nome}.png")


def tela(p: Perfil, slug, rotulo):
    """Print do app; na falta dele, um placeholder do tamanho do print."""
    p.telas.mkdir(exist_ok=True)
    for ext in ("png", "jpg", "jpeg"):
        arquivo = p.telas / f"{slug}.{ext}"
        if arquivo.exists():
            return arquivo, True

    arquivo = BUILD / f"placeholder-{p.nome}-{slug}.png"
    im = Image.new("RGB", (p.print_l, p.print_a), "#FFFCF5")
    d = ImageDraw.Draw(im)
    escala = p.print_l / 1320
    cx, cy = p.print_l // 2, p.print_a // 2
    d.text((cx, cy - round(70 * escala)), rotulo, fill=TINTA,
           font=ImageFont.truetype(SF_ROUNDED, round(96 * escala)), anchor="mm")
    d.text((cx, cy + round(70 * escala)), f"{p.telas.name}/{slug}.png", fill=TINTA_SECUNDARIA,
           font=ImageFont.truetype(SF_ROUNDED, round(52 * escala)), anchor="mm")
    im.save(arquivo)
    return arquivo, False


# ------------------------------------------------------------------ html


def chao_svg(p: Perfil):
    """Faixa de Oliva com borda de cima ondulada e Marrom embaixo, contínua
    de ponta a ponta — é ela que costura as cinco imagens no chão."""
    pontos = []
    for x in range(0, p.tira + 1, 20):
        y = p.chao_y + 10 * math.sin(x / 520 * math.pi) + 6 * math.sin(x / 190 * math.pi + 1.3)
        pontos.append(f"{x},{y:.1f}")
    oliva = f"M0,{p.altura} L" + " L".join(pontos) + f" L{p.tira},{p.altura} Z"
    marrom_y = p.chao_y + p.faixa_marrom
    return f"""
    <svg class="chao" width="{p.tira}" height="{p.altura}" viewBox="0 0 {p.tira} {p.altura}">
      <path d="{oliva}" fill="{OLIVA}"/>
      <rect x="0" y="{marrom_y}" width="{p.tira}" height="{p.altura - marrom_y}" fill="{MARROM}"/>
    </svg>"""


def html(p: Perfil, telas):
    blocos = []

    # spreads nas emendas (camada de trás)
    for i, nome in enumerate(EMENDAS):
        emenda = p.largura * (i + 1)
        blocos.append(
            f'<img class="spread" src="file://{ARTE / (nome + ".png")}" '
            f'style="left:{emenda - p.spread_l // 2}px; top:{p.chao_y - p.spread_a}px">'
        )

    # títulos e aparelhos
    ilha = '<div class="ilha"></div>' if p.ilha else ""
    for i, (slug, _rotulo, rotulo_acima, titulo) in enumerate(PAINEL):
        x0 = p.largura * i
        titulo_html = titulo.replace("\n", "<br>")
        blocos.append(f"""
        <div class="texto" style="left:{x0}px">
          <div class="rotulo">{rotulo_acima}</div>
          <div class="titulo">{titulo_html}</div>
        </div>
        <div class="aparelho" style="left:{x0 + (p.largura - p.aparelho_l) // 2}px; top:{p.aparelho_y}px">
          <div class="tela"><img src="file://{telas[i]}"></div>
          {ilha}
        </div>""")

    ilha_l = round(p.tela_l * 0.286)
    return f"""<!doctype html>
<html><head><meta charset="utf-8">
<style>
  @font-face {{ font-family: "NY";  src: url("file://{NEW_YORK}");   font-weight: 100 1000; }}
  @font-face {{ font-family: "SFR"; src: url("file://{SF_ROUNDED}"); font-weight: 100 1000; }}
  html, body {{ margin: 0; padding: 0; }}
  body {{
    width: {p.tira}px; height: {p.altura}px; overflow: hidden; position: relative;
    background: rgb{PAPEL_ARTE};
    -webkit-font-smoothing: antialiased;
  }}
  .chao {{ position: absolute; left: 0; top: 0; }}

  /* Borda esfumada só para a página assentar no fundo: o papel da arte e
     o do fundo já são o mesmo tom. */
  .spread {{
    position: absolute; width: {p.spread_l}px; height: {p.spread_a}px;
    -webkit-mask-image:
      linear-gradient(to right, transparent 0, #000 7%, #000 93%, transparent 100%),
      linear-gradient(to bottom, transparent 0, #000 9%, #000 100%);
    -webkit-mask-composite: source-in;
  }}

  .texto {{
    position: absolute; top: {p.titulo_topo}px; width: {p.largura}px;
    text-align: center;
  }}
  .rotulo {{
    font-family: "SFR"; font-weight: 650; font-size: {p.rotulo_px}px;
    letter-spacing: 0.12em; text-transform: uppercase;
    color: {ACENTO};
  }}
  .titulo {{
    margin-top: {p.titulo_espaco}px;
    font-family: "NY"; font-weight: 500; font-size: {p.titulo_px}px; line-height: 1.1;
    letter-spacing: -0.01em;
    color: {TINTA};
  }}

  /* Sem sombra: profundidade só por sobreposição. */
  .aparelho {{
    position: absolute; width: {p.aparelho_l}px; height: {p.aparelho_a}px;
    background: {TINTA}; border-radius: {p.raio_aparelho}px;
  }}
  .tela {{
    position: absolute; left: {p.bisel}px; top: {p.bisel}px;
    width: {p.tela_l}px; height: {p.tela_a}px;
    border-radius: {p.raio_tela}px; overflow: hidden; background: #F7F3E9;
  }}
  .tela img {{ width: 100%; height: 100%; object-fit: cover; object-position: top; display: block; }}
  .ilha {{
    position: absolute; left: {p.bisel + (p.tela_l - ilha_l) // 2}px;
    top: {p.bisel + round(p.tela_a * 0.0115)}px;
    width: {ilha_l}px; height: {round(p.tela_a * 0.0387)}px;
    background: #000; border-radius: 999px;
  }}
</style></head>
<body>
{chao_svg(p)}
{''.join(blocos)}
</body></html>"""


# ------------------------------------------------------------------ render


def renderizar(p: Perfil, pagina: Path, saida: Path):
    if not Path(CHROME).exists():
        sys.exit("Google Chrome não encontrado em /Applications.")
    cmd = [
        CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
        "--force-device-scale-factor=1", "--allow-file-access-from-files",
        "--default-background-color=00000000",
        f"--window-size={p.tira},{p.altura}",
        f"--screenshot={saida}", f"file://{pagina}",
    ]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    im = Image.open(saida)
    if im.size != (p.tira, p.altura):
        sys.exit(f"Chrome devolveu {im.size}, esperado {(p.tira, p.altura)}.")


def grao(p: Perfil, im: Image.Image) -> Image.Image:
    """Grão de guache por cima da tira inteira, mesma escala e opacidade —
    o DS manda textura como camada de pós, nunca por imagem. Semente fixa:
    rodar de novo dá exatamente o mesmo grão."""
    gerador = np.random.default_rng(7)
    # grão gerado em meia resolução e ampliado: pinta de guache, não pixel
    ruido = gerador.normal(0, GRAO_DESVIO, (p.altura // 2, p.tira // 2)).astype(np.float32)
    ruido = np.asarray(Image.fromarray(ruido).resize((p.tira, p.altura), Image.BICUBIC))

    # Nada de grão dentro dos aparelhos: o print do app tem que ler nítido,
    # e textura por cima da interface mentiria sobre como o app é.
    mascara = Image.new("L", (p.tira, p.altura), 255)
    d = ImageDraw.Draw(mascara)
    for i in range(PAINEIS):
        x = p.largura * i + (p.largura - p.aparelho_l) // 2
        d.rounded_rectangle(
            (x, p.aparelho_y, x + p.aparelho_l - 1, p.aparelho_y + p.aparelho_a - 1),
            radius=p.raio_aparelho, fill=0,
        )
    ruido = ruido * (np.asarray(mascara, dtype=np.float32) / 255)

    base = np.asarray(im.convert("RGB"), dtype=np.float32)
    saida = np.clip(base + ruido[..., None], 0, 255).astype(np.uint8)
    return Image.fromarray(saida)


def medir(p: Perfil):
    """Confere o que vai subir: a App Store recusa por detalhe de arquivo.

    Tamanho exato do perfil, PNG sem canal alfa (com alfa ela rejeita), e o
    peso de cada imagem — o limite por arquivo e 500 MB, mas acima de uns 10
    MB o upload fica lento sem motivo.
    """
    print(f"\n  {'arquivo':16} {'tamanho':>12}  {'modo':5} {'peso':>9}  ok")
    tudo_ok = True
    for slug, *_ in PAINEL:
        arq = p.export / f"{slug}.png"
        if not arq.exists():
            print(f"  {slug:16} {'faltando':>12}")
            tudo_ok = False
            continue
        with Image.open(arq) as im:
            larg, alt, modo = im.width, im.height, im.mode
        mb = arq.stat().st_size / 1024 / 1024
        ok = (larg, alt) == (p.largura, p.altura) and modo == "RGB"
        tudo_ok = tudo_ok and ok
        print(f"  {slug:16} {larg}×{alt:<6} {modo:5} {mb:7.1f} MB  {'sim' if ok else 'NAO'}")
    if not tudo_ok:
        print("\n  Alguma imagem esta fora do padrao do perfil — nao suba assim.")


def main():
    nome = sys.argv[1] if len(sys.argv) > 1 else "iphone"
    if nome not in PERFIS:
        sys.exit(f"Perfil desconhecido: {nome}. Use: {', '.join(PERFIS)}")
    p = PERFIS[nome]

    conferir_fontes()
    BUILD.mkdir(exist_ok=True)
    p.export.mkdir(exist_ok=True)
    preparar_arte()

    telas, faltando = [], []
    for slug, rotulo, *_ in PAINEL:
        caminho, real = tela(p, slug, rotulo)
        telas.append(caminho)
        if not real:
            faltando.append(slug)

    pagina = BUILD / f"carousel-{p.nome}.html"
    pagina.write_text(html(p, telas), encoding="utf-8")

    bruta = BUILD / f"tira-{p.nome}.png"
    renderizar(p, pagina, bruta)
    tira = grao(p, Image.open(bruta))

    for i, (slug, *_) in enumerate(PAINEL):
        painel = tira.crop((p.largura * i, 0, p.largura * (i + 1), p.altura))
        painel.save(p.export / f"{slug}.png", optimize=True)

    # prévia: as cinco lado a lado, com um fio marcando onde a loja corta
    k = p.previa_divisor
    previa = tira.resize((p.tira // k, p.altura // k), Image.LANCZOS)
    d = ImageDraw.Draw(previa)
    for i in range(1, PAINEIS):
        x = p.largura * i // k
        d.line([(x, 0), (x, 14)], fill=ROSA_CLARO, width=2)
    previa.save(BUILD / f"preview-{p.nome}.png")

    print(f"Pronto: {PAINEIS} imagens {p.largura}×{p.altura} em {p.export}")
    if faltando:
        print(f"Placeholders (faltam prints em {p.telas.name}/):",
              ", ".join(f"{s}.png" for s in faltando))
    medir(p)


if __name__ == "__main__":
    main()
