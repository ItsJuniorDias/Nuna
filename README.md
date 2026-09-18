# Nuna

App iOS de livro ilustrado (picture-book) para crianças de 3–6 anos, feito para
o iPhone Duo. SwiftUI, iOS 27.1.

Pasta irmã de geração de conteúdo: `scripts-picturebook/`.

## Estado

Onboarding, Home, Biblioteca e leitor montados, com o design system aplicado e
o primeiro livro carregando. Ainda não há ilustração: `BandPlaceholder`
desenha as faixas horizontais com as cores de cada spread, então todo o
layout já é verificável sem arte.

## Estrutura

```
Nuna/
  DesignSystem/
    Palette.swift      13 cores travadas + tokens de UI (que NÃO usam a paleta)
    Typography.swift   New York (leitura) e SF Rounded (UI), piso de 24pt
    Layout.swift       espaçamento 4pt, safe zone, constantes da dobra
  Models/
    Book.swift         Book, Spread, LocalizedText com fallback de idioma
  Services/
    BookLoader.swift   lê o JSON do bundle
    Store.swift        StoreKit 2: planos, compra, restauração, isPremium
  Views/
    RootView.swift           TabView de Liquid Glass + apresentação do leitor e do paywall
    Paywall/                 portão parental + paywall próprio
    PageView.swift           ilustração + faixa de texto reservada
    SpreadView.swift         compact = 1 página, regular = spread inteiro
    ReaderView.swift         estado que sobrevive à dobra
    Onboarding/              3 telas, texto dentro da faixa reservada da arte
    Home/HomeView.swift      hero de continuar + prateleira horizontal
    Library/LibraryView.swift  grade adaptativa por size class
    Shared/SafeZoneImage.swift  imagem cuja faixa inferior funde com o fundo
    Shared/BookCover.swift
  Resources/
    o-quintal-da-nuna.json   12 spreads, pt-BR / en / es-MX
    onboarding.json          3 páginas, pt-BR / en / es-MX
  Nuna.storekit        configuração local dos planos (só para o Xcode)
```

O target usa grupo sincronizado com o sistema de arquivos, então basta colocar
arquivos dentro de `Nuna/` — não precisa editar o `project.pbxproj`.

## O livro

"O quintal da Nuna", 12 spreads. Estrutura de espelho: página esquerda a Nuna
faz alguma coisa, página direita um bicho faz a mesma coisa melhor. Arco de um
dia inteiro, do acordar ao dormir, o que também faz a paleta progredir do
amarelo da manhã ao marrom da noite.

Texto original. Máximo 6 palavras por página nos três idiomas.

## Liquid Glass

Em iOS 26+ a tab bar padrão **já é** Liquid Glass. Não se aplica
`.glassEffect` nela — vidro à mão é só para controle custom. O que o app usa:

| Onde | API |
|---|---|
| Tab bar | `TabView` + `Tab(_:systemImage:value:)` padrão |
| Encolher ao rolar | `.tabBarMinimizeBehavior(.onScrollDown)` |
| Cartão sobre o hero | `.glassEffect(.regular, in: .rect(cornerRadius:))` |
| Botão de fechar o livro | `.glassEffect(.regular.interactive(), in: .capsule)` |
| CTA do onboarding | `.buttonStyle(.glassProminent)` |
| Borda de rolagem | `.scrollEdgeEffectStyle(.soft, for: .bottom)` |

Tudo centralizado em `DesignSystem/Glass.swift`, pra trocar em um lugar só.

**Onde NÃO há vidro:** a faixa de 20% inferior de qualquer página. É onde mora
o texto da história, e material translúcido por cima dele fica ilegível pra
quem tem três anos. Por isso o leitor esconde a tab bar inteira e roda
full-bleed, apresentado por `fullScreenCover` e não como aba.

## Assinatura (StoreKit 2)

Um grupo de assinaturas auto-renováveis, **Nuna Premium**, com dois planos.
Compartilhamento Familiar ligado nos dois.

| Plano | Product ID | Período | Preço no `.storekit` |
|---|---|---|---|
| Anual | `alexandrejunior.Nuna.premium.anual` | 1 ano, com **7 dias grátis** | R$ 119,90 |
| Mensal | `alexandrejunior.Nuna.premium.mensal` | 1 mês, sem teste | R$ 19,90 |

O teste grátis é oferta introdutória só do anual. Quem decide se a conta tem
direito é a Apple (`Store.trialEligible`): quem já assinou ou já usou teste no
grupo não ganha outro, e aí o app diz "Assinar" em vez de "Teste grátis".

**O que é grátis:** só o primeiro livro do catálogo, `o-quintal-da-nuna`
(`Store.livrosGratis`). Os outros levam cadeado até `isPremium`. Livro ainda
sem arte continua "Em breve", nunca cadeado.

**Fluxo.** A categoria Kids exige portão parental antes de qualquer tela de
compra e de qualquer link que sai do app, então nenhum toque cai direto no
paywall:

```
"Teste grátis"/"Assinar" no cabeçalho da Home
ou livro bloqueado (prateleiras, Biblioteca, história da semana)
  → RootView  → PaywallFlow: ParentalGate → PaywallView
```

O desvio mora só em `RootView.open(_:)`: as telas continuam chamando `onOpen`,
e livro que não pode ser lido abre o `fullScreenCover` do paywall em vez do
leitor. O portão é uma multiplicação escrita por extenso ("Quanto é sete vezes
oito?") com resposta digitada. O paywall fecha sozinho quando `isPremium` vira
`true`. `NunaApp` chama `Store.shared.start()` uma vez no launch, pra ouvir
renovação, reembolso e compra aprovada por Ask to Buy com o app aberto.

**Testar local.** `Nuna/Nuna.storekit` só vale se estiver escolhido no scheme:
*Product › Scheme › Edit Scheme… › Run › Options › StoreKit Configuration* →
`Nuna.storekit`. Sem isso o app pede os produtos à App Store de verdade, não
acha nenhum e o paywall fica sem planos. Com o app rodando, *Debug › StoreKit › Manage
Transactions* cancela, reembolsa e aprova Ask to Buy.

**Antes de publicar**, no App Store Connect:

1. Paid Apps Agreement assinado (contrato, banco, impostos) — sem ele nenhum
   produto carrega fora do Xcode.
2. Criar o grupo "Nuna Premium" e as duas assinaturas com **exatamente** os
   mesmos Product IDs, períodos, preços, localização pt-BR e Compartilhamento
   Familiar.
3. Oferta introdutória de 7 dias grátis só no anual.
4. Screenshot de revisão de cada assinatura, e nota pro revisor explicando o
   portão parental.
5. Trocar `Store.Links.privacidade` (hoje placeholder, marcado com `TODO:`)
   pela URL real da política de privacidade, e usar a mesma URL no campo do
   app. Termos de uso: EULA padrão da Apple (`Store.Links.termos`).
6. Mandar as assinaturas para revisão junto com um build — a primeira compra
   in-app de um app só é aprovada com uma versão nova.

## Assets esperados

Nome dos assets carrega o slug do livro para dois livros nunca colidirem no
Assets.xcassets. O `Book` injeta o `bookId` em cada `Spread` no init, e o
`Spread.imageName` monta o nome — `spread_o-quintal-da-nuna_01` — sem o resto
do app precisar saber.

Por spread, três nomes possíveis:

- `spread_<slug>_NN`      spread completo (opcional, 3:2)
- `spread_<slug>_NN_l`    página esquerda — usada no spread aberto e na pose fechada
- `spread_<slug>_NN_r`    página direita

Capa: `cover_<slug>` (2:3).

Onboarding: `onboarding_01`, `onboarding_02`, `onboarding_03`.

**Todas essas imagens precisam respeitar a safe zone**: os 20% inferiores em
campo liso `#F7F3E9`, sem nenhum elemento. O onboarding depende disso — o
título é desenhado dentro dessa faixa da própria arte, sem caixa e sem sombra,
e como o fundo do app é o mesmo Papel a emenda entre imagem e interface
desaparece. Se a arte tiver detalhe ali, o título fica ilegível.

O `pipeline/validate.py` do `scripts-picturebook` já mede isso. Proporção:
`2:3` para página e onboarding, `3:2` para spread.

Enquanto não existirem, o placeholder assume.

## Próximos passos

1. Gerar as ilustrações com `scripts-picturebook` e importar como `spread_NN_l`
   e `spread_NN_r`.
2. Narração por spread + read-along (`ReaderState` já reserva `audioPosition` e
   `highlightedWord`).
3. Portão parental na aba Pais — obrigatório na categoria Kids antes de
   compra, link externo ou ajuste. A compra já passa pelo `ParentalGate`;
   falta a aba.

<!-- As ~130 linhas que vinham depois deste ponto (versão de 16/09) se
perderam em 18/09: o arquivo foi sobrescrito por engano antes de entrar no
git. O que está acima foi recuperado do histórico; o que está abaixo é novo. -->

## Para abrir

- **Xcode 27** ou mais novo.
- **Git LFS** antes de clonar — a mídia (arte, vídeos e falas, ~740 MB) mora nele:

  ```bash
  brew install git-lfs
  git lfs install
  git clone <url-deste-repo>
  ```

- **`Nuna/Segredos.plist`** — fora do repositório, de propósito. Guarda a chave
  de envio do analytics:

  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>NunaAnalyticsKey</key>
      <string>UMA-DAS-NUNA_APP_KEYS-DO-SERVIDOR</string>
  </dict>
  </plist>
  ```

  Sem ele o app compila e roda normalmente; só o analytics fica desligado.

## Como o conteúdo chega ao app

A arte e os vídeos **não vão no download inicial** (~20 MB): cada livro é um
pacote sob demanda (On-Demand Resources) baixado na primeira vez que alguém o
abre, e depois funciona offline.

- **No TestFlight e na loja**, os pacotes vêm da Apple.
- **Em build de Debug**, quem serve os pacotes é o **Xcode, do seu Mac**: o
  iPhone precisa estar conectado e o app ter sido instalado por esse Xcode.
  Um *Clean Build Folder* apaga os pacotes, e aí os livros não abrem até o
  próximo build.

Os textos, as ilustrações, os vídeos e as falas são gerados por um pipeline à
parte (não está neste repositório), que escreve direto no `Assets.xcassets` e
no `Resources/catalog.json`.

## Onde está cada coisa

| | |
|---|---|
| `Nuna/Views/ReaderView.swift` | o leitor: virada de página, uma ou duas páginas, motion e voz |
| `Nuna/Services/Pacotes.swift` | pacotes sob demanda (arte, motion, falas) |
| `Nuna/Services/Narracao.swift` | a voz que lê cada página |
| `Nuna/Views/Shared/MotionVideo.swift` | o player único dos vídeos em laço |
| `Nuna/Services/Featured.swift` | a semana grátis e as prateleiras da Home |
| `Nuna/Services/Diagnostico.swift` | caixa-preta: rastro e relatório de crash |
| `docs/iphone-duo.md` | o que a Apple pede para o iPhone Duo e onde o app está |
