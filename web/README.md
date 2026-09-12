# web — Validador Fiscal (Vue 3 + Vite)

Interface do validador fiscal. Padrões de UI/UX, tokens e componentes: **`../docs/DESIGN.md`** (leia antes de criar tela).

## Convenções

- **Vue 3 Options API sempre** (`export default { props, data(), computed, methods, watch }`). Não use `<script setup>` nem Composition API fora de `setup()`, e **não use TypeScript**.
- **PrimeVue 4** estilizado (tema em `src/theme/preset.js`, base Lara/Apollo) + **Tailwind 4** nas classes do template. Prefira `DataTable`, `Dialog`, `ConfirmDialog`, `Toast`, `Select`, `Tag`, `Tabs` a soluções manuais.
- **Estado:** Pinia (`src/stores/`) via `mapState`/`mapActions`. **Dados do servidor:** TanStack Vue Query só dentro de `setup()`, com `reactive(useQuery(...))` / `reactive(useMutation(...))` devolvido ao resto do componente.
- **HTTP:** `src/api/client.js` (refresh de token e `X-Client-Id` automáticos). Novas chamadas entram lá, não com `axios` solto na view.
- **Formulários:** vee-validate `Form`/`Field`/`FieldArray` + zod (`src/schemas/`), rótulo e erro pelo `FormField`. Mensagens em pt-BR.
- **Datas:** `src/utils/date.js` (`todayIso`, `toIso`, `fmtDate`, `fmtDateTime`) — nunca `new Date().toISOString().slice(0, 10)`, que troca o dia no fuso do escritório.
- Textos em pt-BR com acentos; identificadores fiscais com a classe `.mono`.

## Rodando

```bash
docker compose up -d          # na raiz do monorepo: API 3000, web 5174, Postgres 5434
npm install && npm run dev    # ou local, apontando VITE_API_URL para a API
npm run build                 # obrigatório antes de dizer "pronto"
npx vitest run                # testes de utilitários, schemas e componentes
```

Estrutura: `src/views/` (telas, `admin/` para plataforma), `src/layout/` (shell e menu), `src/components/` (blocos reutilizáveis), `src/schemas/` (zod), `src/constants/`, `src/utils/`, `src/router/`.
