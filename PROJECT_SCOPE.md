# Validador Fiscal para Contadores — Esqueleto do Projeto

## 1. Visão e posicionamento

SaaS de **auditoria fiscal baseada em XML** para escritórios de contabilidade. O sistema **nunca emite** documentos fiscais — ele consome XMLs (NF-e/NFC-e) e arquivos SPED/SINTEGRA já gerados pelos ERPs dos clientes do contador, e responde três perguntas:

1. **"O que foi emitido está certo?"** → Auditor de XML
2. **"O que vou entregar ao fisco bate com o que foi emitido?"** → Cross-check SPED/SINTEGRA
3. **"O que muda para o meu cliente com a reforma?"** → Simulador IBS/CBS

**Cliente pagante:** o contador (escritório). **Unidade de cobrança:** CNPJ monitorado.

**Fronteira de escopo (inegociável):** entrada = XML/arquivo pronto; saída = diagnóstico, relatório e simulação. Zero geração de documento fiscal, zero comunicação com SEFAZ para emissão. Isso mantém o produto fora do escopo de qualquer ERP emissor.

---

## 2. Princípio arquitetural central: motor de regras dinâmico

**Problema:** a legislação tributária brasileira muda constantemente — alíquotas por UF, tabelas NCM/TIPI, convênios ICMS, regras de CST/CSOSN, e agora a transição IBS/CBS que muda a cada ano até 2033. Codificar regra fiscal em `if/else` no código significa deploy a cada mudança de lei e manutenção infinita.

**Decisão:** nenhuma regra fiscal vive no código. O código é um **motor genérico de avaliação**; as regras são **dados versionados no banco**.

### 2.1 Regras como dados

Cada regra é um registro com:

- **Condição de aplicação** (a quais documentos/itens a regra se aplica): regime tributário, UF origem/destino, CFOP, NCM, tipo de operação, tipo de cliente
- **Validação/cálculo** (o que verificar ou computar): expressão declarativa avaliada pelo motor — ex.: `cst_esperado`, `aliquota_esperada`, fórmula de base de cálculo
- **Severidade e mensagem**: erro / alerta / informativo, com explicação em linguagem de contador e referência legal
- **Vigência temporal**: `vigente_de` / `vigente_ate`

### 2.2 Vigência temporal é obrigatória

Uma nota de março deve ser validada com a regra **vigente em março**, mesmo que a lei tenha mudado em abril. Toda regra, alíquota e tabela carrega período de vigência; o motor seleciona a versão pela data de emissão do documento. Isso também dá auditabilidade: "essa nota foi apontada como erro segundo a regra X, versão Y, vigente no período Z".

### 2.3 Tabelas de referência importáveis

NCM/TIPI, CFOP, CST/CSOSN, alíquotas internas e interestaduais por UF, cronograma de transição IBS/CBS: tudo em tabelas próprias, com rotina de importação/atualização (admin sobe nova versão da tabela, sistema versiona). Nada disso vai em constante ou enum no código.

### 2.4 Formato das regras (sugestão)

- Armazenamento em **JSONB no PostgreSQL** (condições e expressões como estrutura declarativa)
- Motor de avaliação em Ruby: recebe documento normalizado + conjunto de regras vigentes → devolve lista de apontamentos
- Painel administrativo interno para criar/editar/versionar regras **sem deploy**
- Regras testáveis: cada regra pode ter casos de teste (XML de exemplo → resultado esperado) rodados automaticamente antes de ativar

### 2.5 O que É código e o que É dado

| Código (estável) | Dado (volátil) |
|---|---|
| Parser de XML NF-e/NFC-e | Alíquotas, CSTs esperados por cenário |
| Parser de SPED/SINTEGRA | Tabelas NCM, CFOP, TIPI |
| Motor de avaliação de regras | Regras de validação e mensagens |
| Modelagem de cenário tributário | Cronograma e percentuais IBS/CBS |
| Geração de relatórios | Referências legais |

---

## 3. Funcionalidade 1 — Auditor de XML

**Dor:** o ERP emite conforme a configuração feita pelo cliente, que frequentemente está errada. O contador só descobre no fechamento — ou na multa.

**Fluxo:**

1. Contador cadastra o cliente com seu **cenário tributário**: regime (Simples/Presumido/Real), CNAE/atividade, UF, benefícios fiscais, ST aplicável
2. Sobe os XMLs do período (upload em lote/ZIP; integração com SEFAZ via certificado fica para fase futura)
3. Motor valida cada item de cada nota contra o cenário: CST/CSOSN esperado vs usado, alíquota, base de cálculo, NCM × tributação, CFOP × operação, destaque de ST
4. Saída: painel de apontamentos agrupados por tipo — *"14 notas usaram CSOSN 102, mas o cenário deste cliente exige 900 em devolução de venda"* — com severidade, explicação e referência legal

**Diferencial:** validadores existentes verificam **estrutura** (schema XSD); este valida **coerência tributária com o cenário do cliente**.

## 4. Funcionalidade 2 — Cross-check SPED/SINTEGRA × XMLs

**Dor:** o validador oficial rejeita ou aponta divergência sem explicar a causa; achar a nota de origem do erro é trabalho manual em arquivo de milhares de linhas.

**Fluxo:**

1. Contador sobe o arquivo SPED (EFD) ou SINTEGRA do período + os XMLs do mesmo período
2. Sistema cruza registro a registro: toda nota do XML está no arquivo? Valores, bases e CSTs batem? Há registros no arquivo sem XML correspondente?
3. Detecta padrões conhecidos: nota reemitida com mesmo número e chave diferente omitida do arquivo, divergência de base entre Reg 50/54, fallback indevido de valor zerado
4. Saída: lista de divergências **com a nota de origem apontada** e a explicação da causa provável

**Diferencial:** transforma "erro no registro 54" em "erro no registro 54 causado pela NF-e 12.345, item 3 — base de ICMS divergente porque o desconto não foi rateado".

## 5. Funcionalidade 3 — Simulador IBS/CBS

**Dor:** a transição 2026–2033 muda alíquota e sistemática a cada ano. Contadores precisam responder "quanto meu cliente vai pagar?" e planilhas genéricas não refletem o mix real de produtos e operações.

**Fluxo:**

1. Usa os **XMLs reais** já carregados (mesma base do Auditor — reuso total)
2. Aplica o cronograma de transição (que é dado versionado, não código) sobre o mix real: por NCM, tipo de operação, regime do cliente
3. Saída: carga tributária atual vs projetada ano a ano; **impacto de caixa** considerando split payment ("hoje seu cliente gira X em caixa; com split, passa a girar Y"); comparativo por produto/operação para decisões de preço

**Diferencial:** simulação sobre dados reais do cliente = relatório que o contador **revende como consultoria**. O produto vira gerador de receita para o escritório, não custo.

---

## 6. Modelagem de dados (núcleo)

- `escritorios` → `usuarios`
- `clientes` (CNPJs monitorados) → `cenarios_tributarios` (versionados, com vigência)
- `documentos` (XMLs normalizados) → `itens_documento`
- `arquivos_fiscais` (SPED/SINTEGRA) → `registros_arquivo`
- `regras` (JSONB, versionadas, com vigência) → `casos_teste_regra`
- `tabelas_referencia` (NCM, CFOP, alíquotas, cronograma IBS/CBS — versionadas)
- `apontamentos` (resultado de auditoria: documento/item, regra, versão da regra, severidade)
- `simulacoes` (parâmetros + resultado congelado)

## 7. Stack sugerida

- **Backend:** Rails 7 API-only + Sidekiq (processamento de lotes de XML em background) + PostgreSQL (JSONB para regras e documentos normalizados)
- **Frontend:** Vue 3 + Tailwind
- **Infra inicial:** VPS único ou Fly.io + Postgres gerenciado; S3-compatível para armazenar XMLs/arquivos
- Tudo dentro do que você já domina — zero curva de aprendizado de stack

## 8. Fases

**Fase 1 (MVP):** cenário tributário + upload de XML + motor de regras com ~20 validações de maior impacto (CST/CSOSN, alíquota, CFOP×operação) + painel de apontamentos. Validar com 2–3 contadores reais.

**Fase 2:** cross-check SPED/SINTEGRA (reusa parser e motor).

**Fase 3:** simulador IBS/CBS (reusa documentos carregados) + relatório em PDF com marca do escritório.

**Fase 4:** download automático de XMLs via SEFAZ (certificado A1 do cliente), alertas contínuos em vez de auditoria mensal.

## 9. Pendências não-técnicas

- LGPD: XMLs contêm dados de terceiros; definir retenção, criptografia em repouso e termos de uso desde o MVP