# CLAUDE.md — Validador Fiscal

Monorepo: `api/` (Rails 8 API + Sidekiq, motor de regras fiscais **como dado**), `web/` (Vue 3 Options API + PrimeVue), `docs/` (fonte de verdade da arquitetura). Leia `README.md` e, antes de mexer em regra/canônico/tabela, `docs/ARQUITETURA.md`, `docs/CANONICO.md`, `docs/DSL_RULES.md`, `docs/DATA_SOURCES.md`; para UI, `docs/DESIGN.md`.

## Agentes e skills — roteamento

| Quando | Use |
|---|---|
| Localizar onde algo vive (regra, derivação, tabela, tela) | agente `explorer` |
| Task nova não trivial | skill `task-planner` → `task-resolver` → `task-reviewer` |
| Implementar Rails / Vue a partir de um plano | agentes `backend-dev` / `frontend-dev` |
| Revisar um diff (contexto isolado, só reporta) | agente `code-reviewer` (usa a skill `code-reviewer`) |
| Tratar achados de review, falso positivo de regra, divergência de cálculo | skill `prove-fix-verify` |

Mudança pequena pode ser feita direto, mas termina com `code-reviewer`. Não há Jira nem Sentry: planos ficam em `docs/tasks/<slug>/PLANO.md`; evidências são XML/EFD/prints do usuário.

## Regras obrigatórias

- **Git:** nunca `commit`/`push`/`add` sem o usuário pedir. Ele commita.
- **Regra fiscal é dado:** CST/alíquota/data/percentual só em seeds (`api/db/seeds`) e catálogo, com `effective_from`; publicado é imutável (nova versão). Regra tem par de casos de teste (dispara / não dispara).
- **BigDecimal**, ausência ≠ zero, tudo escopado por firma/cliente, código em inglês com siglas fiscais em português, prosa em pt-BR.
- **Agentes de implementação:** o prompt inclui *"NÃO rode linter/autocorrect. NÃO reformate código existente. Altere APENAS as linhas necessárias."*; conferir `git diff --stat` ao voltar.
- **Review só reporta**; correção só com instrução do usuário (e com prova, via `prove-fix-verify`, quando o achado for discutível).
- **Regressão antes de dizer "pronto":** `docker compose run --rm -T api sh -c "bin/rails rules:validate && bin/rails rules:test && bundle exec rspec"` e `npm run build` no `web/` — reportar números, nunca inferir.

## Ambiente

Docker Compose na raiz (`docker compose up -d`; Postgres 5434, API 3000, web 5174). Login dev: `admin@fiscal.local` / `password123`. Clientes de teste do banco local (ids valem só nesta máquina; identifique pelo CNPJ): Boiron (id 54, XMLs jul–ago/2026), Victor Dzenk (id 55, CNPJ 66412974000190, cross-check SPED).
