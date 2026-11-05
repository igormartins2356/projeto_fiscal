# Task analise-documentacao-sefaz — Análise exaustiva da documentação oficial da NF-e/NFC-e

> **Status:** Em execução — etapas 0, 0a, 0b, 1, 2, 2a, 3 e 4 concluídas
> **Data:** 2026-09-12 (plano), atualizado em 2026-09-12 com o resultado das etapas concluídas
> **Escopo:** Ler os 505 documentos espelhados em `api/storage/sefaz`, arquivo por arquivo e linha por linha, para catalogar todas as regras de validação e códigos de rejeição, o leiaute do XML, e produzir a documentação de referência e o caminho de uma futura API de emissão.

---

## 1. Contexto e objetivo

O espelho local da documentação oficial foi criado em 12/09/2026 (`Sefaz::DocumentSync`, ver `docs/DATA_SOURCES.md` §3.5): 505 documentos, 325 MB, com manifesto versionado em `api/db/data/sefaz/manifest.json`.

O pedido tem quatro produtos, e todos dependem de leitura integral:

1. **Catalogar todas as regras de validação e códigos de rejeição**, sem descartar nada, com prioridade de conversão em regra da DSL.
2. **Catalogar o leiaute dos esquemas XML.**
3. **Documentação de referência**: como cada coisa funciona e onde buscar cada informação.
4. **Caminho para uma API de emissão** de NF-e/NFC-e direto com a SEFAZ.

O motivo declarado da exaustividade é confiança: escrever regra a partir de leitura parcial produz falso positivo, que custa a confiança do contador, e falso negativo, que custa autuação ao cliente dele.

### Dimensionamento real do acervo (medido, não estimado)

| Seção | Documentos | Páginas | Menções a "rejeição" |
|---|---|---|---|
| Notas técnicas | 313 | 7.237 | 16.819 |
| Manuais | 12 (11 PDF + 1 ZIP) | 534 | 1.503 |
| Informes técnicos | 48 | 279 | **2** |
| Esquemas XML | 132 ZIP | — | — |

Totais: **8.050 páginas**, **331.752 linhas** de texto extraído, 25,1 milhões de caracteres, e **2.288 arquivos XSD** somando **887.149 linhas** dentro dos pacotes.

Dois números mudam o desenho do trabalho:

- Os **313 documentos de notas técnicas são 101 notas distintas**. 44 delas têm mais de uma versão publicada; a NT 2016.003 tem 21 versões. Cada versão nova é cumulativa e traz um "Histórico de Alterações" dizendo o que mudou.
- Os **48 informes técnicos têm 2 menções a rejeição em 279 páginas**. Não são fonte de regra; são comunicados operacionais (prazos, disponibilidade, avisos de ambiente).

---

## 2. Validação: já fazemos isso hoje?

**Regras: parcialmente.** Há 94 regras ativas e 259 casos de teste (`docs/RULES.md`), concentradas em ICMS, CFOP, PIS/COFINS, IBS/CBS, devolução, NFC-e, CEST/NCM, IPI, DIFAL, cenário e SPED. Elas nasceram de conhecimento tributário e de revisão jurídica (`docs/RULES_REVIEW.md`), **não** da tabela de regras de validação da SEFAZ. A convergência é real mas acidental: a NT 2026.009 traz a regra I08-140 sobre CFOP de devolução, e o projeto tem `CFOP.RETURN.PURPOSE` cobrindo o mesmo assunto, corrigida em 12/09/2026 por outro caminho.

**Códigos de rejeição: só como texto livre, em seis regras.** Não existe tabela de rejeições, nem arquivo de dados, nem campo no modelo (`api/db/structure.sql:697-716` e `api/app/models/rules/rule.rb` não têm coluna para isso; `findings` também não). O que existe são menções em `legal_references`/`explanation`:

| Rejeição | Regra | Onde |
|---|---|---|
| 321 | `DOC.RETURN.REFERENCE` | `api/db/seeds/03_rules.rb:48` |
| 508/509 | `CFOP.KNOWN` | `api/db/seeds/03_rules.rb:41` |
| "5xx" (NT 2015.003) | `DOC.TOTALS.ITEMS_SUM`, `ICMS.AMOUNT.CALC` | `api/db/seeds/03_rules.rb:54,60` |
| 322 | `DOC.COMPLEMENTARY.REFERENCE` | `api/db/seeds/05_rules_complete.rb:45` |
| 938 | `ICMS.ST.WITHHELD_FIELDS` | `api/db/seeds/05_rules_complete.rb:179` |
| 856 | `NFCE.RECIPIENT.NON_TAXPAYER` | `api/db/seeds/04_rules_extra.rb:74` |

Seis de 94. A consequência prática é que hoje não sabemos dizer ao contador "isso a SEFAZ rejeitaria com o código 327", nem distinguir com segurança a regra redundante-SEFAZ da que só nós fazemos — distinção que o checklist de review já exige, que `docs/RULES_REVIEW.md` já usa como veredito, e que hoje depende de julgamento caso a caso.

Isso liga direto à dor declarada do produto em `PROJECT_SCOPE.md:74`: "o validador oficial rejeita sem explicar a causa". Ter o código de rejeição como dado, ligado à regra e à explicação em linguagem de contador, é o que ataca essa dor.

**Um valor fiscal ainda está em código:** o mapeamento de `cStat` do protocolo (`api/app/services/ingestion/nfe/derivations.rb:206-213`) decide `authorized`/`denied`/`rejected` com uma lista literal de códigos em Ruby. É a tabela de status da SEFAZ embutida no motor, e o invariante do projeto manda que seja dado.

**Leiaute do XML: não como dado.** O parser (`api/app/services/ingestion/nfe/parser.rb`) mapeia tag por tag de forma imperativa, com os enums como constantes no topo do arquivo (linhas 7-18). Não existe declaração de tag, pai, tipo, ocorrência, tamanho ou obrigatoriedade. `nfe_layout` é só intenção em `docs/DATA_SOURCES.md:126-130`; não há tabela nem arquivo (`grep nfe_layout` em `api/` não retorna nada). E **os 132 pacotes de esquema espelhados não têm nenhum consumidor no código**: nenhuma validação contra XSD acontece hoje.

O SPED é o precedente, mas com uma ressalva que muda o desenho: `sped_layout` guarda apenas os nomes dos campos por posição, mais `required`, `level` e as marcas de documento (`api/db/seeds/08_sped_layout.rb:10-11`). **Não guarda tipo nem tamanho**, ao contrário do que `docs/DATA_SOURCES.md:111` afirma — divergência entre doc e código que esta análise deve corrigir. Ou seja: para a NF-e não existe nada, e o modelo a imitar é mais pobre do que a documentação promete. O leiaute da NF-e precisa ser mais rico que o do SPED, porque o Anexo I traz tipo, ocorrência, tamanho e obrigatoriedade condicional por CST.

**Emissão: não existe nada.** Nenhuma assinatura digital, certificado A1/A3, webservice, envio de lote ou consulta de recibo, e nenhuma gem para isso no `Gemfile` (sem savon, xmldsig ou pkcs12). O único certificado decidido é um e-CNPJ A1 para **ler** a API de tabelas da SVRS (`docs/DATA_SOURCES.md:241`), não para assinar documento fiscal. O adjacente que existe é leitura passiva: o parser lê `protNFe/infProt` (`parser.rb:135-138`), a inutilização e os eventos, e o escopo declarado é validar XML já autorizado.

### Onde a análise vai render mais: os vazios de regra

Levantamento por prefixo mostra força em aritmética tributária (ICMS 19 regras, DOC 18, IBS/CBS 11, cenário 8, CFOP 7, PIS/COFINS 7, SPED 7, IPI 5, DIFAL 4, CEST 3, NCM 3, NFC-e 2) e **nenhuma regra** nestes assuntos, todos cobertos pela documentação da SEFAZ:

- **Leiaute e schema**: tipo, tamanho, ocorrência e obrigatoriedade condicional. Só o SPED tem equivalente (`SPED.STRUCTURE`).
- **Chave de acesso**: dígito verificador e composição (UF, ano-mês, CNPJ, modelo, série, número, tipo de emissão, código numérico).
- **Cadastro e identificação**: formato e dígito de CNPJ e CPF, inscrição estadual por UF, código de município do IBGE, CEP, país, coerência do indicador de inscrição do destinatário.
- **Transporte, cobrança e pagamento**: o grupo de fatura e duplicatas (`cobr`) nem é extraído pelo canônico, e o total dos pagamentos não é confrontado com o total da nota.
- **Datas e prazos**: emissão contra saída, emissão futura ou retroativa, contingência e sua justificativa.
- **Imposto Seletivo**: zero regras, embora o canônico já reserve o campo.
- **Eventos**: só uma regra de consistência; carta de correção e manifestação não se projetam no status (campos pendentes no canônico).
- **Entradas e crédito**: previsto em `ARQUITETURA.md:288`, sem nenhuma regra.

O canônico tem **27 marcas `[P]`** (cerca de 31 campos e grupos), entre eles grupos inteiros que a validação de leiaute exigiria: fatura e duplicatas, imposto de importação, rastreabilidade de lote, declarações de importação, detalhe de exportação, retenção de ICMS no transporte, veículo, intermediador, retirada e entrega.

---

## 3. Mapa dos pontos

| # | Arquivo | Linhas | Camada | Estado atual | Precisa mudar? |
|---|---|---|---|---|---|
| 1 | `api/db/data/sefaz/manifest.json` | — | dado | 505 documentos com procedência | Não; é a entrada da análise |
| 2 | `api/app/services/ingestion/nfe/parser.rb` | 270 | parser | Mapeamento imperativo do XML | Só na etapa de leiaute, e só se decidirmos declarar o leiaute como dado |
| 3 | `docs/CANONICO.md` | 504 | doc | Dicionário do canônico, com pendências marcadas `[P]` | Sim: a análise diz o que falta extrair e o que é obrigatório por CST |
| 4 | `api/db/seeds/0{3,4,5}_rules*.rb` | 569 | dado | 88 regras de NF-e | Sim, em lotes, conforme o backlog priorizado |
| 5 | `api/db/seeds/06_rule_test_cases.rb` | ~150 | dado | 259 casos | Sim: cada regra nova exige par dispara/não dispara |
| 6 | `api/db/seeds/02_catalog.rb`, `02b_catalog_extra.rb` | 135 | dado | 15 tabelas do catálogo | Sim: tabela de rejeições e matriz por CST entram aqui |
| 7 | `api/db/data/sped_layout_020.json` + `08_sped_layout.rb` | 26 | dado | Leiaute do SPED **como dado** | Não muda; é o modelo a imitar para a NF-e |
| 8 | `docs/DSL_RULES.md` | 417 | doc | Referência da linguagem | Sim, se a análise revelar operador ou primitiva faltante |
| 9 | `docs/DATA_SOURCES.md` §3.5 | 32 | doc | Espelho documentado | Sim: apontar os catálogos derivados da análise |
| 10 | `docs/RULES_REVIEW.md` | 90+ | doc | Vereditos com base legal | Sim: cada regra nova vinda de NT entra com a NT como fonte |
| 11 | `api/app/services/ingestion/nfe/derivations.rb` | 206-213 | derivação | Tabela de `cStat` literal em Ruby | Sim, se o ponto 6 da seção 5 for aceito |
| 12 | `api/app/services/rules/canonical_schema.rb` | 69 | motor | Dicionário de caminhos válidos; campo `[P]` fica fora de propósito | Sim: cada campo que o parser passar a extrair entra aqui |
| 13 | `api/db/structure.sql` (tabela `rules`) | 697-716 | schema | Sem campo para código de rejeição | Sim, se o ponto 4 da seção 5 for aceito (migration) |

---

## 4. Estratégia

### 4.0 Princípio: ler tudo, mas ler cada coisa uma vez

O pedido é ler todas as linhas. O desperdício a evitar é ler a **mesma** linha 21 vezes. Duas reduções, sem perda:

**Notas técnicas.** Para cada uma das 101 notas, a versão mais recente é a fonte de conteúdo (é cumulativa). As versões anteriores entram pelo "Histórico de Alterações", que é onde a própria SEFAZ declara o que mudou e desde quando. Isso preserva a informação de **vigência** — essencial, porque regra publicada tem `effective_from` e documento antigo precisa ser julgado pela regra da época. Resultado: ~2.500 páginas de conteúdo inédito e ~4.700 páginas lidas como diff dirigido, em vez de 7.237 páginas lidas como se fossem todas novas.

**Esquemas XML.** Dos 131 pacotes com XSD, o vigente é `PL_010f_v1.04` (5 arquivos, 10.269 linhas) mais os pacotes de evento (`Eventos_RTC`, 18 arquivos). Os 126 pacotes históricos servem para responder "desde quando este campo existe", e serão lidos por diff entre versões consecutivas, não integralmente.

**Informes técnicos.** Lidos por último e de forma dirigida: 279 páginas, 2 menções a rejeição. Se a leitura confirmar que não contêm regra, ficam registrados como fonte de contexto operacional.

### 4.1 Os seis produtos da análise

| Produto | Onde mora | Versionado? |
|---|---|---|
| **A. Catálogo de rejeições** — código, mensagem oficial, regra de validação em texto, campo/ID, modelo (55/65), NT de origem, vigência, e se já temos regra equivalente | `api/db/data/sefaz/rejeicoes.json` → tabela de catálogo `sefaz_rejeicao` (decisão 8) | sim |
| **B. Catálogo de leiaute da NF-e** — ID, tag, pai, tipo, ocorrência, tamanho, observação | `api/db/data/nfe_layout_400.json` → tabela `nfe_layout` (mais rica que `sped_layout`, que só tem nome por posição) | sim |
| **C. Matriz de obrigatoriedade por CST/CSOSN** — por campo, se é exigido, proibido ou condicional em cada situação tributária | linhas da tabela `nfe_layout` ou tabela própria | sim |
| **D. Backlog priorizado de regras** — cada rejeição classificada: vira regra nossa, é redundante-SEFAZ, é de infraestrutura, ou não se aplica | `docs/tasks/analise-documentacao-sefaz/BACKLOG.md` | sim |
| **E. Documentação de referência** — o que cada documento cobre e onde buscar cada informação | `docs/SEFAZ_REFERENCIA.md` | sim |
| **F. Caminho da emissão** — webservices, certificado, assinatura, contingência, QR Code | `docs/EMISSAO_NFE.md` | sim |

O produto **A** é o que destrava o resto: com o código de rejeição ligado à regra, passa a ser possível dizer ao contador "a SEFAZ rejeitaria com 327" e classificar honestamente o que é redundante.

### 4.2 A estrutura que a extração vai encontrar

Já verificada em amostra. Nas notas técnicas e no Anexo I, as regras vêm em tabela com colunas fixas:

```
Campo      Modelo  Regra de Validação                         Aplic.  Msg  Descrição Erro
I08-140    55      Para NF-e com as finalidades abaixo,       Obrig.  327  Rejeição: CFOP inválido para
                   somente serão aceitos CFOPs de devolução                Nota Fiscal de devolução
                   - Devolução de mercadoria (tag: finNFe = 4);
                   Observação 1: Vide tabela CFOP, indDevol=1
                   Exceção 1: Aceitar os CFOP 1.949 e 2.949 (NT 2015.002)
```

Sete elementos por regra: identificador ligado ao ID do leiaute, modelo aplicável, lógica em texto com as tags entre parênteses, obrigatoriedade, **código de rejeição**, mensagem oficial, e observações e exceções com referência cruzada a outras notas.

O Anexo I ainda traz **matrizes de obrigatoriedade por CST**: para cada campo do grupo, se ele é exigido (S), proibido (N) ou condicional (?) em cada situação tributária. Uma única matriz dessas gera dezenas de regras.

**Consequência importante:** o layout das colunas varia ao longo dos documentos, e um extrator ingênuo captura pouco. Medição real: um padrão simples pegou 54 de 476 códigos de rejeição do Anexo I. Portanto a extração é **assistida, não automática**: o parser produz candidatos, e a leitura humana/assistida confirma cada linha. É por isso que este plano é de análise, e não de um script de importação.

### 4.3 Estrutura do documento mestre

O `Anexo I - Leiaute e Regra de Validação` (154 páginas, 1.160 menções a rejeição) é o documento central, e sua estrutura define a divisão do trabalho:

| Seção | Páginas | Conteúdo | Serve para |
|---|---|---|---|
| 2. Leiaute da NF-e | 8–66 | Tabela de campos: ID, tag, pai, tipo, ocorrência, tamanho | Produto **B** |
| 3.1–3.2 Orientações | 67–69 | Abreviações e regras de preenchimento | Produtos **B** e **E** |
| 3.3 URL do QR Code | 70 | Montagem do QR Code da NFC-e | Produto **F** |
| 4.1 Grupos A, B, D, E, F | 71–74 | Certificado TLS, mensagem no webservice, área de dados, certificado de assinatura, assinatura digital | Produto **F** (emissão) |
| 4.2 Regras de negócio | 74–140 | **O ouro**: regras por campo, com código de rejeição | Produtos **A** e **D** |
| 4.3 Consumo indevido | 140–142 | Limites de consulta (NT 2018.002) | Produto **F** |
| 4.4.2 Tabela de rejeições | 143 | Lista dos códigos | Produto **A** |

A separação é limpa e vale registrar: o que o **validador** precisa está na seção 2 e na 4.2; o que a **emissão** vai precisar está na 3.3, 4.1 e 4.3.

### 4.4 Lotes e etapas

Cada lote termina com entrega verificável e não depende dos seguintes. A ordem é por densidade de regra por página, com o documento mestre primeiro porque ele dá o vocabulário (os identificadores de campo) que todos os outros usam.

| Etapa | Lote | Volume | Entrega |
|---|---|---|---|
| **0** | Preparação: extrair texto de todos os PDFs, listar XSDs, classificar as 101 notas por módulo fiscal lendo título e sumário, e identificar a versão vigente de cada | 505 docs | Índice de trabalho com módulo, versão vigente e cadeia de versões; extrator de tabelas em modo candidato |
| **0a** | ✅ Seção "Diversos" espelhada e leitor de planilha | 95 docs | Espelho em **600 documentos**; `Sefaz::SpreadsheetReader` lê `xlsx` e `ods` sem gem nova |
| **0b** | ✅ Onda 1 importada | 4 tabelas | `cfop` v2 com **619** códigos (era 515), vigência e indicadores oficiais; `fcp_uf` v1 (27 UFs, fixo × teto); `ibs_cbs_class` v2 **com vigência por linha**; `ibs_cbs_cst` v1 (18 CSTs e os grupos que cada um admite) |
| **1** | ✅ Leiaute, **do esquema XML** e não do Anexo I (ver nota abaixo) | 23 XSD | `nfe_layout` v1 com **1.072 campos**, 152 enumerações, 631 padrões de formato. Cruzamento: parser ignora **322 das 902 folhas** (`LACUNAS_LEIAUTE.md`) |
| **2** | ✅ `Anexo I` seção 4 inteira, linha por linha | 80 pág. | `sefaz_rejeicao` v1 com **551 regras** e **478 códigos** (507 de negócio, 38 de infraestrutura, 6 de consumo indevido). Cruzamento em `REJEICOES.md`: só **22 códigos** já eram citados pelas nossas 94 regras |
| **2a** | ⏳ Parcial: a tabela existe. **Falta** o campo de rejeição no corpo da regra (migration + `DSL_RULES.md`) e mover o `cStat` de `derivations.rb:206-213` para a tabela | — | Fazer junto com a primeira conversão de rejeição em regra |
| **3** | ✅ `Anexo I` 4.1/4.3/3.3 + `MOC 7.0` + Anexos II a IV + manual do DANFE NFC-e | 11 manuais, 534 pág. | `docs/EMISSAO_NFE.md`: certificado (dois momentos, A1 × A3), assinatura (elementos proibidos), chave de acesso, os 8 webservices, síncrono × assíncrono, 4 modalidades de contingência, eventos, QR Code em 2 versões, responsável técnico, e as 38 validações de infraestrutura como checklist |
| **4** | ✅ **Absorvida pela etapa 1.** O esquema deixou de ser conferência e passou a ser a fonte | — | Ver nota abaixo |
| **5** | ✅ **Reforma tributária**: as 3 notas distintas (2025.002 v1.51 vigente com 14 versões, 2024.002, 2026.006) | 17 docs | `sefaz_rejeicao` foi a **849 linhas** e **763 códigos**: +290 da reforma. Verificado que a nota de 2024 foi absorvida pela vigente (105 dos 107 códigos) |
| **6** | Notas do módulo **Eventos** (cancelamento, carta de correção, manifestação, insucesso, averbação, conciliação) | 30 docs, 461 pág., 2.566 rej. | idem |
| **7** | Notas do módulo **NFC-e** (incluindo QR Code e CSC) | 30 docs, 819 pág., 2.493 rej. | idem, e alimenta **F** |
| **8** | Notas de **leiaute e versão** (NT 2013.005, 2016.002, 2009.006 e as demais que alteram leiaute) | ~15 docs, ~1.200 pág. | Consolidação de **B**, **C** e vigência de campo |
| **9** | Notas do módulo **GTIN / NCM / CEST / produto** | 44 docs, 430 pág., 397 rej. | **A**, **D** |
| **10** | Notas do módulo **Combustível / ANP / cana** | 21 docs, 379 pág., 459 rej. | **A**, **D** (avaliar se está no escopo do produto) |
| **11** | Notas de **ICMS-ST, partilha, DIFAL, FCP** e **Exportação / ZFM / Suframa** | 11 docs, 84 pág. | **A**, **D** |
| **12** | Notas de **contingência, EPEC, SVC, inutilização** e **intermediador/pagamento** | 15 docs, 189 pág. | **A**, **D**, e alimenta **F** |
| **13** | Notas restantes não classificadas nos módulos acima | o que sobrar do índice da etapa 0 | **A**, **D** |
| **14** | **Informes técnicos** (leitura dirigida) | 48 docs, 279 pág. | Confirmar ausência de regra; registrar em **E** |
| **14a** | Importar as tabelas das **ondas 2 e 3** (decisão 7) | 19 tabelas | Catálogo completo, com histórico e vigência |
| **15** | Consolidação: **D** priorizado e fechado, **E** e **F** finalizados; corrigir as três menções ao SINTEGRA (decisão 12) e registrar os outros documentos fiscais como fora de escopo (decisão 11) | — | Todos os produtos |

### Nota: a fonte do leiaute mudou, por evidência

O plano previa extrair o leiaute do Anexo I (etapa 1) e **conferir** contra o esquema (etapa 4). Na
execução ficou claro que a ordem certa é a inversa. O Anexo I descreve o leiaute para humano, em
tabela de PDF cujas colunas mudam de posição a cada uma das 118 páginas: a extração por posição
rendeu 74 campos de 900, desalinhados. O esquema XML é a **fonte normativa**, já vem estruturado, e
rendeu os 1.072 campos com tipo, tamanho, padrão de formato, ocorrência, escala decimal e as 152
enumerações com os valores válidos — que o PDF nem traz.

O Anexo I continua necessário, mas para o que só ele tem: o **identificador do manual** (B07, I08),
que é como as regras de validação referenciam os campos, e as observações. Isso entra quando a
primeira rejeição virar regra, ligando `sefaz_rejeicao` a `nfe_layout` pelo identificador.

Etapas 5 a 13 são independentes entre si e podem ser paralelizadas. As etapas 1 a 4 são pré-requisito das demais, porque fixam o vocabulário de campos e o catálogo de rejeições.

### 4.5 Como cada regra catalogada será classificada (produto D)

Toda rejeição recebe exatamente uma classificação, e a classificação decide o que fazemos:

| Classe | Significado | Ação |
|---|---|---|
| `nossa` | Regra de negócio que a SEFAZ valida, mas cujo erro sobrevive no XML autorizado (ex.: alíquota certa no campo errado, CST coerente com CFOP mas incoerente com o regime do cliente) | Vira regra da DSL, com prioridade alta |
| `redundante-sefaz` | A SEFAZ rejeita na autorização; o XML autorizado nunca viola | Cadastrar no catálogo com a classe, e se virar regra, severidade baixa e explicação dizendo isso (o checklist de review já exige) |
| `infraestrutura` | Certificado, assinatura, schema, protocolo TLS, consumo indevido | Não vira regra do validador; alimenta o produto **F** |
| `emissao` | Só se aplica a quem emite (montagem do QR Code, contingência, numeração) | Alimenta **F** |
| `fora-de-escopo` | Outro documento fiscal (NFCom, NF3e, NFAg, NFGas) ou segmento que não atendemos | Registrar e ignorar |

A prioridade dentro de `nossa` sai de três critérios, nesta ordem: valor em risco para o cliente, frequência esperada no XML real dos clientes, e se a regra é verificável com os campos que o canônico já extrai (se não for, exige derivação nova e custa mais).

### 4.6 Paridade com o que já existe

Cada regra catalogada como `nossa` deve ser cruzada com as 94 regras existentes antes de virar regra nova. Três desfechos: já existe e está correta; já existe e está incompleta (vira nova versão, porque publicado é imutável); não existe. O cruzamento é por campo do canônico e por assunto, não por nome — a regra da SEFAZ fala em tag do XML (`finNFe`, `CFOP`), a nossa fala no canônico (`doc.operation.purpose`, `item.product.cfop`), e o mapeamento entre os dois é o produto **B**.

---

## 5. Definições (todas resolvidas em 12/09/2026)

### Decisões de análise

1. **A extração é assistida, não automática.** Medição própria: padrão simples capturou 54 de 476 códigos no Anexo I, porque o layout varia. O extrator gera candidatos; a conferência é linha por linha.
2. **Nada é descartado.** Toda rejeição entra no catálogo com sua classificação, inclusive `redundante-sefaz` e `fora-de-escopo`. O catálogo é o registro de que foi lida, que é o que dá a confiança pedida.
3. **Versão vigente é a fonte; versões antigas são a vigência.** O histórico de alterações de cada nota entra no catálogo como `effective_from` da regra.
4. **O leiaute da NF-e vira dado**, mais rico que o do SPED (que só guarda nome por posição). O parser não será reescrito nesta análise: o catálogo nasce como referência, e a conversão do parser para dirigido por dado é decisão posterior, com plano próprio.
5. **Informes técnicos ficam por último**, pela medição de 2 rejeições em 279 páginas.
6. **A emissão é documentação, não implementação.**

### Decisões do usuário

7. **Tabelas de apoio entram, e são importadas.** A seção "Diversos" do portal tem 95 documentos, que são **22 tabelas distintas** com suas versões. O sincronizador será estendido para ela, e as tabelas serão importadas para o catálogo **em três ondas por valor**:

   | Onda | Tabelas | Por quê primeiro |
   |---|---|---|
   | 1 | CFOP completa, Alíquotas de FCP por UF, Classificação Tributária do IBS/CBS | Resolvem problema já identificado: o recorte de CFOP gerou falso positivo em 12/09/2026, e a dúvida de FCP por UF ficou aberta na reconstrução da alíquota interna |
   | 2 | Municípios, Países, Unidades de medida, Meios de pagamento, cBenef × CST, Lista de Serviços | Destravam vazios de regra que hoje não têm nenhuma cobertura (cadastro, pagamento, benefício fiscal) |
   | 3 | Produtos ANP, Combustíveis monofásicos, Índice de biocombustível, Crédito presumido IBS/CBS, Tipo e espécie de veículo, Bandeiras de cartão, Prefixo GS1, Indicadores de CST do IBS/CBS, CNPJ alfa | Segmento específico ou uso pontual |

   As versões históricas de cada tabela **entram**, com sua vigência. Importar só a versão vigente faria auditoria de período antigo ser julgada com tabela de hoje, que é exatamente o defeito corrigido na revisão geral.

   Formato: as tabelas são planilhas. `xlsx` e `ods` são ZIP com XML e podem ser lidos com `rubyzip` e `nokogiri`, que já estão no projeto — **nenhuma gem nova**. Apenas a Tabela de Unidades de Medida Comercial está em `xls` binário de 2016, e será tratada como caso à parte (conversão manual pontual, ou versão mais recente se houver).

   A seção "Diversos" também traz as **cadeias de certificado** do portal, que interessam ao produto **F** (emissão), e um documento de consumo indevido.

8. **A rejeição passa a ser dado, em três frentes.** Tabela `sefaz_rejeicao` no Catalog, com vigência e versão como as outras; **campo opcional no corpo da regra** para o código de rejeição, o que exige migration e atualização de `docs/DSL_RULES.md`; e o mapeamento de `cStat` sai de `derivations.rb:206-213` para essa mesma tabela, porque `cStat` e código de rejeição vêm da mesma fonte oficial. É o que permite dizer ao contador qual seria a rejeição, atacando a dor declarada em `PROJECT_SCOPE.md:74`.

9. **Validação contra XSD não entra agora.** O XML que o contador apresenta já foi autorizado, logo já passou pelo schema da SEFAZ: revalidar pegaria quase nada. O XSD vigente **é lido** na etapa 4, como fonte de tipo, tamanho e ocorrência para o catálogo de leiaute, e a validação em tempo de execução fica registrada no produto **F**, onde tem valor real (validar antes de enviar).

10. **Combustível e ANP: catalogar sem converter.** As rejeições dos 21 documentos entram no catálogo, mas a conversão em regra aguarda haver cliente do segmento.

11. **Outros documentos fiscais fora de escopo.** NF3e, NFCom, NFAg, NFGas e NF-e ABI têm seções próprias no portal e não entram, pela mesma razão que NFS-e, CT-e e MDF-e já estão fora (`ARQUITETURA.md:292`). Fica registrado no produto **E**.

12. **SINTEGRA: corrigir a documentação.** O leiaute é citado em `ARQUITETURA.md:167`, `CANONICO.md:454` e `DATA_SOURCES.md:120`, mas não existe no código nem nas seeds. As três menções passam a dizer que está previsto e não implementado. Implementar, se for o caso, é task própria.

## 6. Arquivos impactados

**A criar:** `api/db/data/sefaz/rejeicoes.json`, `api/db/data/nfe_layout_400.json`, `docs/SEFAZ_REFERENCIA.md`, `docs/EMISSAO_NFE.md`, `docs/tasks/analise-documentacao-sefaz/BACKLOG.md`, um extrator de tabelas de PDF, um leitor de planilha (`xlsx`/`ods` sobre `rubyzip` e `nokogiri`), os importadores das 22 tabelas de apoio, e a migration do campo de rejeição na regra.

**A alterar:** `api/db/seeds/02_catalog.rb` (tabelas novas), `api/db/seeds/0{3,4,5}_rules*.rb` e `06_rule_test_cases.rb` (regras novas, em lotes), `docs/CANONICO.md` (campos e obrigatoriedade por CST), `docs/DATA_SOURCES.md` (apontar os catálogos novos), `docs/RULES_REVIEW.md` (fonte de cada regra nova), `docs/DSL_RULES.md` (se houver campo ou operador novo).

**Fora do escopo, a validar:** `api/app/services/ingestion/nfe/parser.rb` — só muda se decidirmos, depois, tornar o parser dirigido por dado.

**A alterar também, pelas decisões:** `api/app/services/sefaz/document_sync.rb` (seção "Diversos"), `api/app/services/ingestion/nfe/derivations.rb:206-213` (`cStat` vira consulta ao catálogo), `api/db/structure.sql` (campo de rejeição na regra), `docs/ARQUITETURA.md:167`, `docs/CANONICO.md:454` e `docs/DATA_SOURCES.md:120` (menções ao SINTEGRA).

---

## 7. Plano de testes

A análise em si não é testável por RSpec; o que ela produz é.

- **Extrator:** spec com trecho real de cada formato de tabela encontrado (Anexo I, nota técnica recente, nota antiga), afirmando que os sete elementos da regra são extraídos. Fixtures pequenas, sem PDF no repositório.
- **Catálogo de rejeições e de leiaute:** semeados como tabela do Catalog, com o mesmo fluxo de versão e vigência das outras 15 tabelas, e portanto cobertos pelos specs de catálogo que já existem.
- **Cada regra nova:** par de casos obrigatório em `06_rule_test_cases.rb`, um que dispara e um que não dispara, incluindo o caso "quase". Exigência do ciclo `shadow → published`.
- **Cruzamento com XML real:** rodar auditoria nos clientes que o usuário cadastrar e comparar apontamentos por regra antes e depois de cada lote, como foi feito na revisão geral (735 → 735 apontamentos comprovou que a partição temporal não mudou volume).
- **Regressão por lote:** `bin/rails rules:validate && bin/rails rules:test && bundle exec rspec` e `npm run build`. Baseline atual: 94 regras válidas, 259 casos, 256 exemplos, 32 testes de frontend.

---

## 8. Ordem de execução sugerida

1. ✅ **Etapas 0, 0a e 0b** concluídas. A onda 1 já devolveu valor: a tabela oficial de CFOP confirmou a
   classificação de anulação que havíamos deduzido, e a de FCP corrigiu duas linhas da alíquota interna
   (Sergipe tem o adicional; o Rio de Janeiro tem teto de 4%, não 2% fixo).
2. ✅ Nenhuma decisão pendente: os doze pontos da seção 5 estão resolvidos.
3. ✅ **Etapas 1, 2, 3 e 4** concluídas; **2a parcial** (a tabela existe, falta o campo na regra e o `cStat`).
4. **Etapas 5 a 13** em paralelo, um lote por módulo, cada um fechando com: rejeições catalogadas, classificação feita, backlog atualizado e regressão verde.
5. **Etapa 14** (informes) e **15** (consolidação).
6. Só então abrir plano próprio para (a) converter o backlog priorizado em regras, em lotes, e (b) decidir sobre parser dirigido por dado e sobre emissor.

O trabalho de escrever as regras **não** faz parte desta task: aqui se produz o catálogo, a classificação e a prioridade. Misturar as duas coisas é o que levaria a escrever regra a partir de leitura parcial, que é exatamente o que o pedido quer evitar.

---

## Produtos entregues até aqui

| Produto | Onde | Estado |
|---|---|---|
| **A. Catálogo de rejeições** | tabela `sefaz_rejeicao` (849 linhas, 763 códigos) + `REJEICOES.md` | ✅ Anexo I (564) + reforma tributária (290); as outras notas ampliam nas etapas 6 a 13 |
| **B. Catálogo de leiaute** | tabela `nfe_layout` (1.072 campos) + `LACUNAS_LEIAUTE.md` | ✅ do esquema vigente; identificador do manual pendente |
| **C. Matriz por situação tributária** | tabela `ibs_cbs_cst` (18 CSTs) | ⏳ feita para IBS/CBS; a do ICMS está no Anexo I e entra na etapa 8 |
| **D. Backlog priorizado** | `REJEICOES.md` (por assunto e por grupo) | ⏳ primeira classificação; prioridade fecha na etapa 15 |
| **E. Documentação de referência** | `DATA_SOURCES.md` §3.5 e as seções novas | ⏳ cresce a cada etapa |
| **F. Caminho da emissão** | `docs/EMISSAO_NFE.md` | ✅ primeira versão completa |

Regressão ao fim da etapa 5: 94 regras válidas, 259 casos, 300 exemplos, todos sem falha. Catálogo em
20 tabelas.
