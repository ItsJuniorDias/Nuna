# iPhone Duo — o que a Apple pede e onde o Nuna está

Notas de [Preparing your app for iPhone Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo),
lidas em 17/09/2026, com o que já está feito no app e o que falta.

O Duo é um telefone dobrável: **display externo compacto** e **display interno
grande**, câmera frontal nos dois (a de dentro esconde quando não está em uso).
Abrir, fechar, dobrar pela metade e girar move o conteúdo entre displays e muda
o layout. Em pose meio dobrada, as views se ajustam à **região da dobra**.

---

## 1. Xcode 27.1 é pré-requisito

- Só com **Xcode 27.1 ou posterior** o app usa a tela inteira. Compilado com
  versão anterior, ele **não estende sob a barra de status e a câmera**.
- O simulador do Duo vem no Device Hub e **exige o 27.1**.
- **Nuna hoje:** Xcode 27.0, SDK 27.0. É o primeiro item da fila, e ele
  desbloqueia quase todo o resto desta lista.

## 2. Redimensionar é a funcionalidade principal

Quem já roda bem no iPad, no Mac ou no iPhone Mirroring está quase lá.

| Recomendação da Apple | Nuna |
|---|---|
| Preferir containers do sistema (split view, tab bar, navigation stack, **arrangement view**) | Parcial: `TabView` com `Tab` é do sistema; as duas metades são container próprio (`DuasMetades`) |
| Dimensionar pelo container, não por medidas fixas de iPhone | Feito: tudo sai de `GeometryReader` / `onGeometryChange` |
| Calcular pelo bounds da cena ou da view, nunca pela tela | Feito: `Postura` recebe o tamanho medido; nada lê `UIScreen` |
| Observar `horizontalSizeClass` / `verticalSizeClass` | Feito |
| **Não** decidir layout por `userInterfaceIdiom` nem por `UIInterfaceOrientation` | Feito no layout. `userInterfaceIdiom` aparece só no `Analytics` (rótulo de evento), o que é legítimo |

Checklist da Apple para passar no app, pose a pose (fechado, aberto, meio
dobrado, girado em cada uma):

- as views redimensionam em toda orientação e pose;
- as barras aparecem **verticais** na lateral quando o sistema decide;
- nenhuma sheet ou popover fica em posição esquisita ao dobrar;
- nada importante cai **dentro da dobra**.

## 3. Barras verticais

O sistema apresenta navigation bar, toolbar e tab bar **verticalmente na
lateral**: no display externo com o aparelho fechado, e em algumas views nas
posições leading/trailing do display interno.

- Isso só acontece com as barras dos containers de navegação. Barra própria
  feita com `UIToolbar`, `UINavigationBar` ou `UITabBar` **não ganha** o
  tratamento. Em SwiftUI: `toolbar(content:)` num `NavigationStack` ou
  `NavigationSplitView`.
- **Inspectors:** sempre horizontal.
- **Split views:** horizontal na sidebar e no content, vertical no detail.
- **Sheets:** no display externo, vertical por padrão — desligue com
  `toolbarVerticalBehavior(_:)`. No interno, horizontal para placement
  centrado ou leading, vertical para trailing; escolha com
  `presentationPlacement(_:)`.
- Para saber, numa view própria, se a barra está vertical:
  **`toolbarVerticalEdge`** (SwiftUI) ou o trait `verticalBarEdge` (UIKit).
- Imagem de fundo ou hero deve continuar **sob** a barra vertical:
  **`backgroundExtensionEffect()`** (SwiftUI) ou `UIBackgroundExtensionView`.

**Nuna hoje:** a tab bar é do sistema, então ganha o tratamento de graça. A
barra do leitor é própria (um overlay com os botões de fechar, contador e
setas) — por isso ela não vira vertical, e isso é uma escolha: o leitor é
full-bleed e esconde a tab bar. O que falta olhar é se, no display externo, a
barra do leitor briga com a barra vertical do sistema.

**Oportunidade clara:** `backgroundExtensionEffect()` no fundo de Papel — a
textura passaria por baixo da barra vertical em vez de parar nela.

## 4. Organizar os itens das barras

- Topo reservado para navegação primária (Back, Close), seguido de ações
  proeminentes (Done).
- Placements semânticos: `topBarPinnedTrailing` para o Done, `cancellationAction`
  para Back/Close próprios.
- `axisBehavior(_:)` decide se o item entra no layout vertical.
- `visibilityPriority(_:)` decide quem vai para o menu de estouro primeiro;
  `ToolbarOverflowMenu` põe itens direto lá.
- **Todo item precisa de ícone E título:**
  - vertical → usa o ícone;
  - horizontal → prefere o ícone;
  - menu de estouro → usa os dois;
  - **título sem ícone não aparece na vertical**;
  - **view própria no lugar de título/ícone não aparece na vertical**.

**Nuna hoje:** as três abas têm ícone e título. Os botões do leitor são views
próprias — se um dia virarem toolbar de sistema, precisam de ícone + título.

## 5. Arrangement view — o container para as poses

`ArrangementView` (SwiftUI) e `UIArrangementViewController` (UIKit): um
container para uma view **primária** e uma **secundária**, com dois estilos.

- **split:** lado a lado quando o container é mais largo que alto; primária em
  cima e secundária embaixo quando é mais alto que largo. **Ajusta sozinho às
  regiões reservadas, inclusive a dobra.** É o caso de quem usaria `HStack` ou
  `VStack`.
- **overlay:** primária sobre a secundária quando não há divisão ativa (Duo
  fechado ou totalmente aberto); com o aparelho meio aberto, primária no lado
  trailing/inferior e secundária no leading/superior. É o caso de quem usaria
  `ZStack`.
- Dá para limitar o eixo do arranjo.
- **Não** colocar arrangement view dentro de navigation split view, list,
  scroll view ou outro container que possa esconder parte da view.

**Nuna hoje:** `DuasMetades` faz o papel do split à mão, com heurística de
geometria. Trocar por `ArrangementView` é o segundo item da fila — ganhamos o
ajuste automático à dobra. Atenção ao aviso: a Home é um `ScrollView`, e hoje
o `DuasMetades` mora dentro dele. Ou o arranjo sobe para fora da rolagem, ou
aquela seção continua com o container próprio.

## 6. Regiões reservadas

O iOS descreve dobra e câmera como **reserved regions**:

- **division:** a dobra partindo a view em duas;
- **occlusion:** hardware cobrindo conteúdo. A câmera frontal interna oculta
  quando está ativa; **a externa oculta sempre**.
- Uma região pode estar **ativa ou inativa** — a dobra é inativa com o aparelho
  plano. `options: .includeInactive` traz as duas.

API: `GeometryProxy.reservedRegions(kind:options:layoutDirectionBehavior:)` em
SwiftUI, `reservedRegions(kind:options:)` em UIKit. Inspecione os frames e
ajuste a view.

**Nuna hoje:** `Postura.duasMetades` é heurística (size class regular + mais
largo que alto + largura mínima), e a calha é uma proporção da largura. Com a
API real, `duasMetades` vira "existe região de divisão vertical" e a calha vira
o frame dela. O TODO já está anotado em `DesignSystem/Postura.swift` — muda um
arquivo só.

Isso importa duas vezes no Nuna:

1. **O vinco do livro.** A arte reserva 6% no centro (`SafeZone.vinco`) e o
   spread é centralizado na tela inteira para a dobra cair ali. Com a região
   real, o alinhamento deixa de ser suposição.
2. **A câmera.** Hoje usamos a maior das duas safe areas laterais para nada
   ficar sob a câmera. Com `occlusion` dá para recuar só onde precisa.

## 7. Câmera

Captura pela câmera externa, interna e traseira; abrir, fechar e girar pode
trocar o display do app e inverter a direção da câmera. Há guia próprio para
registrar acessório de captura com o Duo aberto.

**Nuna hoje:** o app não usa câmera. Nada a fazer.

---

## Quando fazer

**Decidido em 17/09/2026: nada disto entra agora.** O app compilado com o
Xcode 27.0 roda no Duo — só não estende sob a barra de status e a câmera, que
e um detalhe visual, nao um bloqueio. A adocao fica para o lancamento do
aparelho, quando der para testar em hardware ou no simulador do Device Hub.

Ate la, a regra que ja seguimos protege o futuro: layout pelo espaco recebido,
nunca por modelo, orientacao ou `UIScreen`. Isso significa que a lista abaixo e
troca de implementacao, nao reescrita de tela.

## Fila de trabalho (no lancamento)

1. **Subir para o Xcode 27.1** — sem isso o app não usa a tela toda e não há
   simulador do Duo.
2. **`reservedRegions`** no lugar da heurística (`Postura.swift`), para o vinco
   do livro cair na dobra de verdade.
3. **`ArrangementView`** no lugar do `DuasMetades`, onde não houver rolagem em
   volta.
4. **`backgroundExtensionEffect()`** no fundo de Papel, para a textura passar
   sob a barra vertical.
5. **Passar o app inteiro pelo checklist da seção 2**, pose a pose, com atenção
   a sheets e popovers (paywall e portão dos pais são full screen cover, o que
   já evita boa parte do problema).
