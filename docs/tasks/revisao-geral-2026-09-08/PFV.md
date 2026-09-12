# Prove-Fix-Verify — acompanhamento (2026-09-09)

Base: REVIEW.md (6 críticos, 26 altos, 52 médios, 33 baixos). Baseline: rules:validate 95 | rules:test 225/0 | rspec 27/0 | web build ✓.

| Onda | Lote | Achados | Status |
|---|---|---|---|
| 1 | Críticos API | C1 | ✅ confirmado, corrigido (403 + users_spec.rb, 1 falha sem correção) |
| 1 | Críticos seeds | C2 C3 C4 | ✅ corrigido (seed_rows!/seed_rule! recusam publicado fora de dev; SEED_ADMIN_PASSWORD; clientes reais só em dev) + spec/db/seeds_spec.rb passa. Poder do teste a reconfirmar |
| 1 | Crítico primitiva | C5 | ✅ confirmado, corrigido (cfop_mirror em params da regra; primitiva exige; spec com poder). Re-seed 04 necessário em dev |
| 1 | Crítico inferência | C6 | ✅ confirmado (41% dos itens Boiron ignorados por CFOP 6108 fora da lista), corrigido via derivados do catálogo + regra publicada; inference_spec 4 falhas sem correção |
| 2r | Frontend | A25 A26 M43–M52 baixos web | ✅ confirmados e corrigidos. vitest 27/27, build ✓ |
| 2r | Motor DSL | A6 A7 A8 A9 A11 A12 M7–M12 baixos | ✅ confirmados e corrigidos. M8 refutado numericamente (0 divergências em busca exaustiva) mas corrigido por convenção. M9 confirmado sinteticamente (EFD do Dzenk não está no banco). rules:validate 95 |
| 2r | Parser/ingestão | A15 A16 A17 A18 M21 M27 M28 M29 M30 baixos | ✅ todos confirmados e corrigidos. SPED 65 INSERTs→2; 0 documentos exigem rederive hoje (todos -03:00) |
| 2r | Catálogo | A14 M13 M14 M15 M16 M17 M19 M20 M26 baixos | ✅ todos confirmados e corrigidos. Lookup 293→4 queries/100 lookups. 31 specs novos, 0 falhas. Desvio deliberado em M16: versão anterior com data anterior continua published fechada na véspera (retirar apagaria a vigência histórica) |
| 3 | API auth | A1 A2 A3 A5 M4 M5 baixos | ✅ todos confirmados e corrigidos. spec/requests 69/0. M4 resolvido com adaptador redis-client (gem redis não está no bundle) — decisão de gem pendente do usuário |
| 2r | API recursos | A4 A11 M1 M2 M3 M6 M52-backend cors baixos | ✅ todos confirmados e corrigidos. spec/requests 52/0; suíte 87/0. Bônus: callback nomeado repetido em subclasse removia o do pai (show/create/update de admin/reference_tables ficariam abertos) |
| 3 | Auditoria | A10 A13 M14 M18 M22 M23 M24 M25 baixos | ✅ confirmados e corrigidos. A10: partição temporal por vigência; confronto com legado 735→735 findings idênticos. M18 corrigido com ressalva: índice único (version_id,key,effective_from) — a sugestão do review quebraria a vigência por linha. M25: decisão de NÃO desnormalizar, registrada em ARQUITETURA §12 |
| 3 | Regras/seeds | A19–A24 M31–M36 baixos | ✅ confirmados e corrigidos; M36 REFUTADO com base legal (RJ é 20% desde 2024, Lei 10.253/2023) e A21 parcialmente refutado. rules:test 251/0, 0 regras sem par. Revert em bloco: 14 falhas |
| 4 | Docs + baixos SPED | M37–M42 | ✅ docs sincronizadas com o código; CanonicalSchema limpo de 4 caminhos nunca derivados; warnings de constante zerados |
| 4 | Orquestrador | M18, pins do Gemfile, gatilho publish→Rederive, diff do painel, fcp_uf_dest no schema | ✅ feitos (M18 e pins dentro dos lotes de auditoria e auth) |


Interrupção por limite de sessão em 2026-09-09 ~19h: 6 agentes perderam o trabalho em curso. Retomados com o estado preservado no working tree.

- Ajuste aplicado pelo orquestrador: api/spec/requests/admin_spec.rb:60 (`changed` 0→1, pois o diff agora compara vigência e base legal). admin_spec 4/0.
- Orquestrador: `files_skipped` exposto no serializer de uploads (+spec); gatilho `Ingestion::RederiveJob` ao publicar versão de tabela, com teste de poder (sem a linha: "expected to enqueue exactly 1 jobs, but enqueued 0").
- Orquestrador: pendência do [A8] aplicada em `return_references_original.rb` (Array()/dec) com 2 testes novos de robustez; um deles falhava antes.
- Orquestrador: `uploads_spec` usava `efd_icms_ipi` (valor inexistente no código) → `sped_icms_ipi`; diff do painel colapsava linhas de mesma chave com vigências diferentes → indexado por (key, effective_from), com teste de poder.

## Decisões que ficaram para o usuário (não aplicadas)
1. **Cenário do Boiron (cliente 54) no banco de dev**: a versão publicada (id 8) tem `st.applies = false` e nenhuma IE-ST; a seed foi corrigida para `applies: true` com as 10 inscrições de substituto tributário (BA, ES, MA, MG, MT, PB, PE, PR, RJ, RS). Cenário publicado é imutável, então refletir isso exige **publicar uma nova versão do cenário**, o que muda o resultado das auditorias desse cliente. É afirmação sobre a realidade tributária de um cliente real (a própria seed trazia "CONFIRMAR com o contador"), então não apliquei. Enquanto não for publicada, `SCENARIO.ST.DISAGREEMENT` não avalia o Boiron.
2. **`gem "redis"` para o cache de produção**: o achado M4 pedia `redis_cache_store`, mas a gem `redis` não está no bundle (só `redis-client`, via Sidekiq) e usá-la derrubaria o boot. O contador do Rack::Attack foi movido para o Redis com um adaptador mínimo; `Rails.cache` em produção segue `FileStore`. Adicionar a gem é decisão sua.
3. **Ambiente já semeado**: as versões de `cfop` e `cst_pis_cofins` mudaram de conteúdo e vigência. O banco de dev já foi atualizado; outro ambiente precisa de `db:reset` (a seed não edita linha de versão publicada, por desenho).
4. **Fonte Poppins via Google Fonts** e **chunk de 942 kB do RunDetailView**: registrados, não alterados.

## Regressão final (2026-09-10)

| | Baseline (antes da revisão) | Agora |
|---|---|---|
| `rules:validate` | 95 regras ativas válidas | **94 regras ativas válidas** (2 retiradas por duplicidade, 1 versão nova) |
| `rules:test` | 225 casos, 0 falhas | **259 casos, 0 falhas, 0 regras sem caso** |
| `rspec` | 27 exemplos, 0 falhas | **246 exemplos, 0 falhas** |
| `npm run build` (web) | ✓ | **✓** |
| `vitest` (web) | não existia | **7 arquivos, 32 testes, 0 falhas** |
| warnings "already initialized constant" | dezenas por execução | **0** |

## Rodada 2 — revisão em sessão cega (exigida pela skill)

Três agentes revisaram o diff **sem o contexto desta sessão**, sabendo apenas o que o código se propõe a fazer e quais são os invariantes do projeto. Encontraram defeitos reais, **alguns introduzidos pelas próprias correções da rodada 1** — que é exatamente o motivo de a sessão cega existir.

| Revisor | Achados | Status |
|---|---|---|
| Motor e ingestão | 0 crítico, 2 altos, 4 médios, 4 baixos | ✅ 8 confirmados e corrigidos, 1 refutado com medição (diferença de tempo via BigDecimal é exata; `to_i` pioraria o arredondamento). Pico de memória do extrator: 8 de 8 entradas → 1 |
| API e segurança | 0 crítico, 2 altos, 10 médios, 4 baixos | em tratamento |
| Seeds, frontend e docs | 0 crítico, 3 altos, 5 médios, 5 baixos | em tratamento |

Altos introduzidos pela rodada 1, agora em correção:
- `dedupe_key` não distingue regra em sombra da publicada, então o finding da sombra é descartado e o painel que decide a promoção fica cego (o Resolver passou a devolver as duas na rodada 1).
- Escopos de período/cross-document são avaliados só na resolução do último dia: regra de período que perde vigência no meio do mês não é avaliada nem gera erro.
- O gatilho de rederivação que liguei ao publicar tabela enfileira um job por cliente de todas as firmas, dentro do request, e reprocessa o histórico inteiro ignorando o período de vigência.
- Reset de senha por administrador revoga refresh token mas o access token segue válido por até 15 minutos; `password_changed_at` é gravado e nunca lido.
- A mitigação de enumeração de contas é contornável: pedir login sem a senha devolve 400 para conta existente e 401 para inexistente.

Altos encontrados na sessão cega sobre regra fiscal (nenhum existia no relatório da rodada 1):
- CFOPs 5402/6402 marcados como substituto tributário, mas são a hipótese em que a substituição **não** é retida (operação entre contribuintes substitutos do mesmo produto) — falso positivo em severidade de erro.
- CFOPs 5409/6409 (transferência de mercadoria sujeita a substituição) ficaram sem papel de substituição, então a regra que proíbe CST de substituição em CFOP comum dispara na nota correta.
- Doze regras publicadas tiveram severidade, e duas o próprio critério, alterados **na mesma versão** — o invariante do projeto manda criar versão nova. É o defeito mais estrutural das duas rodadas: as correções de conteúdo foram certas, o caminho foi o errado.

Total da sessão cega: 30 pontos, sendo 7 altos.

| API e segurança (cega) | 0 crítico, 2+1 altos, 10 médios, 4 baixos | ✅ todos confirmados e corrigidos; os dois "a confirmar" (unicidade de evento e migration abortando em base legada) confirmaram-se e foram corrigidos |

Follow-ups aplicados pelo orquestrador depois desse lote:
- O importer traduzia a violação do índice novo de eventos em falha crua do Postgres no lote do contador; agora devolve duplicata, com teste que falha sem a correção.
- A troca da própria senha passou a devolver uma sessão nova, porque a marca de senha invalida todo token anterior, inclusive o de quem trocou. Frontend adota o par novo.
- **Defeito novo, encontrado por esse teste**: o controle de papel do controller de usuários valia para todas as ações, então nenhum usuário comum conseguia trocar a própria senha (403). Corrigido e coberto.

| Regras fiscais (cega) | 0 crítico, 3 altos, 5 médios, 5 baixos | ✅ 11 corrigidos, 2 parciais (registrados), 1 decidido com evidência |

## INCIDENTE — perda de dado no banco de desenvolvimento

Durante a rodada 2, um agente recarregou uma seed com uma versão do ajudante que ainda escolhia a última versão da tabela em vez da que a própria seed criou. Resultado: **as linhas da versão 2 da tabela de alíquota interna de ICMS foram substituídas pelas 4 do seed**.

Verifiquei em primeira mão:

- A versão 2 foi criada em 31/08/2026 pelo import manual do painel e foi alterada em 09/09/2026 às 21:59.
- Hoje ela tem 4 linhas (São Paulo, Minas Gerais, Rio de Janeiro, Espírito Santo) no lugar das 27 unidades federativas.
- Esse dado **não existe no repositório** (a documentação já registrava que essa versão só vivia no banco onde foi importada) e não há log de importação nem backup. Procurei arquivo de origem em todo o projeto: não há.

Impacto: a regra de alíquota interna, hoje em severidade de aviso, deixa de avaliar unidades federativas fora dessas quatro. Os dois clientes de teste são de São Paulo, então os resultados de auditoria em desenvolvimento não mudam.

Como recuperar: reimportar a versão pelo painel, a partir do arquivo original. O ajudante foi endurecido para só reescrever a versão que a própria seed criou, e o caso virou teste de regressão.

## Encerramento

Duas rodadas: a primeira sobre os 117 achados do relatório de revisão, a segunda sobre os 30 achados que três agentes encontraram revisando o resultado **sem o contexto da sessão**. Sete dos achados da segunda rodada eram defeitos criados pelas correções da primeira.

Regressão final: `rules:validate` 94 regras | `rules:test` 259 casos, 0 falhas | `rspec` 246 exemplos, 0 falhas | `npm run build` ✓ | `vitest` 32 testes, 0 falhas.

Total: 123 arquivos alterados, 48 arquivos novos, 4 migrations, 3663 linhas somadas e 1011 removidas. Nada foi commitado.

## Limpeza da base e reimportação (2026-09-10, a pedido do usuário)

Backup antes de apagar: dump do banco (12 MB) e dos arquivos (8 MB) no scratchpad da sessão.

Apagados do banco de desenvolvimento: 3 clientes (o de exemplo e os dois reais de teste), 579 documentos, 802 itens, 5811 apontamentos, 12 execuções de auditoria, 5 lotes de envio, 3 cenários e 123 MB de XML em disco. Preservados: firma, usuário administrador, 98 regras, 15 tabelas do catálogo com 17 versões e 32.741 linhas, e os 259 casos de teste de regra.

As seeds dos dois clientes reais passaram a exigir `SEED_TEST_CLIENTS=1`, para que um `db:seed` não os recrie junto com o catálogo. Coberto por teste que falha sem a guarda.

A tabela de alíquota interna virou arquivo versionado em `api/db/data/icms_internal_rate.yml`, com a rake `catalog:icms_internal_rate` que cria a versão em rascunho e `catalog:publish[codigo,versao]`. O dado deixa de existir só no banco, que foi a causa da perda anterior.

A versão 3 foi publicada com **20 unidades federativas conferidas em fonte primária** (lei estadual e regulamento), cada linha com a base legal e a data em que a alíquota passou a valer. Sete ficaram de fora por não terem sido fechadas na norma: Amapá, Ceará, Distrito Federal, Goiás, Roraima, Sergipe e Tocantins. Tabela esparsa não gera apontamento; alíquota errada gera.

A conferência derrubou parte do meu rascunho inicial, o que justifica não ter publicado de primeira:

- **Sergipe** estava com 20%; a alíquota é 19%.
- **Rio Grande do Norte** só passou a 20% em 20/03/2025, não em 2024. Documento de 2024 agora não acha linha, em vez de ser cobrado por uma alíquota que ainda não valia.
- **Alagoas** passou a 20,5% em 01/04/2026, não 20% em 2024.
- Datas corrigidas em Acre, Maranhão, Paraná, Piauí, Rondônia, Roraima e Rio Grande do Sul.

Duas armadilhas de cálculo ficaram registradas na base legal de cada linha: em Pernambuco os 20,5% já são a alíquota fora do fundo de pobreza, então somar o adicional produz valor errado; no Rio Grande do Sul o adicional vai em informações complementares com guia própria, fora do campo `pFCP`, então esperar esse campo preenchido gera falso positivo. O único adicional geral destacado no campo é o do Rio de Janeiro.

Histórico preservado: a versão de 2024 continua publicada e fechada em 31/12/2025.

Regressão após a limpeza: 94 regras | 259 casos, 0 falhas | 247 exemplos, 0 falhas | build ✓ | 32 testes de frontend, 0 falhas.
