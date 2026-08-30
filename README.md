# Validador Fiscal

Monorepo: `api/` (Rails 8 API + Sidekiq), `web/` (Vue 3 + Vite + Tailwind + PrimeVue (tema Aura) + Pinia + Vue Query), `docs/` (arquitetura e especificações).

## Padrões do frontend

- JavaScript puro (sem TypeScript) e **Options API sempre** (`export default { data(), computed, methods }`); nada de `<script setup>`.
- Pinia via `mapStores`/`mapState`/`mapActions`. Vue Query isolado num `setup()` mínimo (só `useQuery`/`useMutation`) exposto ao resto do componente.
- **PrimeVue fixado na série 4.x (MIT).** A 5.x passou para a PrimeUI License (comercial US$ 599/dev, ou community gratuita para < 5 devs / < 10 funcionários / < US$ 1M receita) e exibe o banner "Invalid PrimeUI License" sem chave. Migrar para 5 só com decisão de licença (https://primeui.dev/licenses/community).
- PrimeVue em modo **estilizado** com tema próprio baseado em Lara reproduzindo o visual do template Apollo (`web/src/theme/preset.js`, `web/src/style.css`, shell em `web/src/layout/`), locale pt-BR em `web/src/locale/pt-BR.js`; Tailwind para layout. Padrões completos em `docs/DESIGN.md`. Preferir componentes PrimeVue (Dialog, Toast, Select, DataTable…).
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

Leia nesta ordem: `docs/ARQUITETURA.md`, `docs/CANONICO.md`, `docs/DSL_RULES.md`, `docs/DATA_SOURCES.md`, `docs/DESIGN.md` (padrões de UI/UX).

## Estado atual (29/08/2026)

Fluxo ponta a ponta funcionando: upload de XML/ZIP → parse para o canônico → auditoria com regras versionadas → findings no painel.

- Autenticação: JWT (Bearer) + refresh token com rotação; 2FA TOTP opcional; papéis `platform_admin | firm_admin | accountant`. O header `X-Client-Id` seleciona o cliente (sempre validado contra a firma do usuário).
- Seeds (`bin/rails db:seed`) criam escritório, usuário `admin@fiscal.local` / `password123` (platform_admin), cliente `12345678000190`, 7 tabelas do Catalog e 30 regras.
- Telas: Auditorias, Enviar XMLs, Clientes → Cenário tributário (com inferência a partir das notas), Usuários, Sobreposições (firma), Segurança (2FA/senha); para `platform_admin`: Regras (editor, casos de teste, ciclo de vida) e Tabelas (versões, import CSV/JSON, diff, publicação, sincronização NCM/cClassTrib).
- Variáveis de produção: `JWT_SECRET`, `AR_ENCRYPTION_PRIMARY_KEY`, `AR_ENCRYPTION_DETERMINISTIC_KEY`, `AR_ENCRYPTION_KEY_DERIVATION_SALT`, `SVRS_CERT_P12`/`SVRS_CERT_PASSWORD` (opcional), `CORS_ORIGINS`.
- Sidekiq Web em http://localhost:3000/sidekiq (apenas development).
- Fixture de teste: `api/spec/fixtures/nfe/sale_return_csosn_102.xml` (devolução de venda com CSOSN 102 → dispara `ICMS.CSOSN.SALE_RETURN`).
