# Design system — padrões de UI/UX

> Referência visual: template **Apollo** (PrimeTek). Reproduzimos o *padrão* — tokens, layout, densidade, componentes — em código próprio (`web/src/theme/preset.js`, `web/src/style.css`, `web/src/layout/`). O template em si é licenciado e não é copiado para o repositório.

---

## 1. Tokens

| Token | Valor | Uso |
|---|---|---|
| Fonte | **Poppins** (400/500/600/700), fallback system-ui | tudo; `html { font-size: 14px }` → `1rem = 14px` |
| Primária | `#6366f1` (indigo) — escala 50 `#f7f7fe` … 900 `#282960` | botões, links, ícones do menu, rótulos de grupo |
| Texto | `#1e293b` / secundário `#64748b` | corpo / legendas, subtítulos, metadados |
| Fundo da página | `#eff3f8` (`--surface-ground`) | `body` |
| Superfície | `#ffffff` (card, overlay, seção) | cards, diálogos, menus |
| Borda | `#dfe7ef` (`--surface-border`); tabelas `#e2e8f0` | cards, divisores, células |
| Hover | `#f6f9fc` | linhas de tabela, itens de menu |
| Raio | `6px` componentes; `12px` cards | botões, inputs, tags, diálogos / cards |
| Sombra do card | `0 4px 30px rgba(221,224,255,.54)` | cards |
| Sombra da sidebar | `0 4px 50px #d9ddfc` | sidebar |
| Foco | `0 0 0 .2rem #c7d2fe` | inputs/botões focados |
| Semânticas | verde `#22c55e`, laranja `#f97316`, vermelho `#ff3d32`, azul `#3b82f6`, amarelo `#eab308` | sucesso / alerta / erro / info |
| Severidade de finding | `error` vermelho, `warning` laranja, `info` azul | `SeverityTag`, cartões de resumo |

Todos os tokens vivem em `web/src/theme/preset.js` (tema do PrimeVue, base **Lara**) e como variáveis CSS em `web/src/style.css` (`--surface-*`, `--text-color*`, `--primary-*`, `--card-*`, `--sidebar-*`).

## 2. Layout (shell)

```
┌ sidebar 18rem ─┬──────────────────────────────────────────────────┐
│ logo           │ topbar: [☰ mobile] breadcrumb ............ cliente ▾ ○ │
│ GRUPO (upper)  │ ─────────────────────────────────────────────── │
│  ▸ item        │ conteúdo (padding 2rem, cards)                    │
│  ▸ item        │                                                   │
│ GRUPO          │                                                   │
│  ▸ item        │ footer                                            │
└────────────────┴──────────────────────────────────────────────────┘
```

- **Sidebar** fixa (`18rem`, branca, sombra azulada), logo centralizado no topo (`padding 2.5rem 0 2rem`), menu em **grupos** com rótulo `uppercase .857rem bold` na cor primária; itens `padding .75rem 2rem`, ícone `primeicons` na cor primária, hover `--surface-hover`, ativo em **negrito**. Grupos/itens filtrados por papel (`web/src/layout/menu.js`).
- **Topbar** transparente (sem fundo), `margin-bottom 2rem`: breadcrumb à esquerda (grupo › página › detalhe, `600`, secundário; último em cor de texto), à direita o **seletor de cliente** (com filtro) e o avatar com menu (Segurança, Sair).
- **Conteúdo** `padding 0 2rem 2rem`; **footer** discreto com borda superior.
- **Responsivo**: < 992px a sidebar vira overlay (botão ☰ na topbar, máscara escura), paddings reduzidos.

## 3. Página

1. `<PageHeader title subtitle>` com `#actions` à direita (botão primário da página + secundários `outlined`). Um único botão primário por página.
2. Conteúdo em **cards** (`.card`: branco, raio 12px, padding 2rem, sombra). Tabelas ficam dentro de um card; formulários longos usam um card por seção com `.card-title`.
3. **Cartões de indicador** (`.stat-card` dentro de `.card`): rótulo secundário, valor `2rem bold`, ícone quadrado colorido à direita (`.stat-icon` com fundo 100 + texto 500 da cor semântica).
4. **Estado vazio** (`.empty-state`): ícone grande na primária clara + frase com a próxima ação.
5. Carregando: `loading` do DataTable; para páginas inteiras, card com "Carregando…".

## 4. Componentes (PrimeVue, tema estilizado)

| Situação | Use |
|---|---|
| Listas | `DataTable` (cabeçalho `#f8fafc`, células `padding .85rem 1rem`), `size="small"` para tabelas secundárias; lazy + paginação server-side quando > 100 linhas; filtros por coluna (`filterDisplay="row"`); expansão de linha para detalhes; export CSV/XLSX nas ações da página |
| Ações | `Button`: primário sólido; secundário `severity="secondary" outlined`; destrutivo `severity="danger"`; ícone-só com `aria-label`; `text` para ações terciárias em linhas |
| Estado/etiquetas | `Tag` (`success` publicado/ativo, `warn` sombra/alerta, `danger` erro/aposentado, `info`, `secondary` rascunho/inativo) |
| Formulários | vee-validate `Form/Field/FieldArray` + zod; layout `.field` (rótulo 500 acima, erro `.field-error` vermelho, dica `.field-hint`); grades `grid-cols-2/3`; datas com `InputText type="date"` (trocar por `DatePicker` quando precisar de calendário) |
| Seleção | `Select` (com `filter` quando > 8 opções), `Checkbox`, `MultiSelect` se necessário |
| Confirmação | `ConfirmDialog` via `$confirm` para ações destrutivas ou irreversíveis (publicar, remover, desativar) — sempre com `acceptLabel`/`rejectLabel` em pt-BR |
| Feedback | `Toast` (`$toast`): `success` curto (2,5 s), `error` com detalhe (4–5 s); nunca `alert()` |
| Sobreposições | `Dialog` modal (raio 6px, cabeçalho 1.5rem) para criar/editar; largura via `class="w-[720px]"` |
| Navegação interna | `Tabs` para seções de um mesmo objeto (Definição / Casos de teste / Disparos) |
| Código/identificadores | classe `.mono` (chave de acesso, códigos de regra, CFOP, NCM) |

## 5. Escrita (pt-BR)

- Títulos em frase (só a primeira maiúscula): "Cenário tributário", não "Cenário Tributário".
- Botões no infinitivo curto: "Salvar", "Publicar", "Nova auditoria". Verbo + objeto quando houver ambiguidade.
- Mensagens ao contador em linguagem de contador, sempre com o **que** está errado, o **valor encontrado** e o **esperado** (as regras já seguem isso).
- Termos legais permanecem como na legislação (CST, CSOSN, CFOP, NCM, CEST, DIFAL, IBS/CBS); ver `code-in-english-fiscal-terms-portuguese`.
- Datas `dd/mm/aaaa` na UI (`toLocaleString('pt-BR')`), valores com vírgula decimal quando exibidos ao usuário final (relatórios); nos dados técnicos (evidência) mantém-se o canônico.

## 6. Acessibilidade e densidade

- Contraste mínimo AA: texto secundário `#64748b` sobre branco/ground; nunca texto cinza claro sobre ground.
- Todo botão ícone-só tem `aria-label`; foco visível (anel `#c7d2fe`).
- Densidade padrão do Apollo (confortável). Tabelas secundárias podem usar `size="small"`.
- Sem animações além das transições do tema (200 ms) e da sidebar (300 ms).

## 7. Onde está cada coisa

| Arquivo | Conteúdo |
|---|---|
| `web/src/theme/preset.js` | preset do PrimeVue (Lara + tokens) e `tokens` exportados |
| `web/src/style.css` | variáveis CSS, tipografia, shell de layout, `.card`, `.page-header`, `.stat-card`, `.field`, `.empty-state` |
| `web/src/layout/AppLayout.vue`, `AppSidebar.vue`, `AppTopbar.vue`, `AppFooter.vue`, `menu.js` | shell |
| `web/src/components/PageHeader.vue`, `FormField.vue`, `SeverityTag.vue`, `TagsInput.vue`, `JsonEditor.vue` | blocos reutilizáveis |
| `web/src/locale/pt-BR.js` | textos do PrimeVue |
