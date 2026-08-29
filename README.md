# Validador Fiscal

Monorepo: `api/` (Rails 8 API + Sidekiq), `web/` (Vue 3 + Vite + Tailwind + PrimeVue unstyled + Pinia + Vue Query), `docs/` (arquitetura e especificações).

## Padrões do frontend

- JavaScript puro (sem TypeScript) e **Options API sempre** (`export default { data(), computed, methods }`); nada de `<script setup>`.
- Pinia via `mapStores`/`mapState`/`mapActions`. Vue Query isolado num `setup()` mínimo (só `useQuery`/`useMutation`) exposto ao resto do componente.
- **PrimeVue fixado na série 4.x (MIT).** A 5.x passou para a PrimeUI License (comercial US$ 599/dev, ou community gratuita para < 5 devs / < 10 funcionários / < US$ 1M receita) e exibe o banner "Invalid PrimeUI License" sem chave. Migrar para 5 só com decisão de licença (https://primeui.dev/licenses/community).
- PrimeVue em modo **unstyled** com preset Tailwind próprio em `web/src/primevue/preset.js` (pass-through global). Preferir componentes PrimeVue (Dialog, Toast, Select, DataTable…).
- DataTable lazy com paginação server-side, filtros por coluna, row expansion e export CSV/XLSX (`web/src/utils/export.js`).
- Formulários com vee-validate + zod; schemas em `web/src/schemas/` com mensagens em pt-BR.
- Estilo com classes Tailwind no template; `<style>` só quando o Tailwind não resolver.

## Desenvolvimento

```bash
cp .env.example .env
docker compose build
docker compose run --rm api bin/rails db:prepare
docker compose up
```

- API: http://localhost:3000
- Web: http://localhost:5174
- Postgres: localhost:5434 (fiscal/fiscal)

Testes da API: `docker compose run --rm api bundle exec rspec`

## Documentação

Leia nesta ordem: `docs/ARQUITETURA.md`, `docs/CANONICO.md`, `docs/DSL_RULES.md`, `docs/DATA_SOURCES.md`.

## Estado atual (29/08/2026)

Fluxo ponta a ponta funcionando: upload de XML/ZIP → parse para o canônico → auditoria com regras versionadas → findings no painel.

- Sem autenticação ainda: a API identifica o cliente pelo header `X-Client-Id` (ver `Api::V1::BaseController`). **Não expor publicamente** antes de implementar JWT.
- Seeds (`bin/rails db:seed`) criam escritório, usuário `admin@fiscal.local`/`password`, cliente `12345678000190`, tabelas mínimas do Catalog e 13 regras.
- Sidekiq Web em http://localhost:3000/sidekiq (apenas development).
- Fixture de teste: `api/spec/fixtures/nfe/sale_return_csosn_102.xml` (devolução de venda com CSOSN 102 → dispara `ICMS.CSOSN.SALE_RETURN`).
