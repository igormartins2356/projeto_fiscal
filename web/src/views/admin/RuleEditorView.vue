<script>
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import Tag from 'primevue/tag'
import Message from 'primevue/message'
import Dialog from 'primevue/dialog'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Tabs from 'primevue/tabs'
import TabList from 'primevue/tablist'
import Tab from 'primevue/tab'
import TabPanels from 'primevue/tabpanels'
import TabPanel from 'primevue/tabpanel'
import JsonEditor from '../../components/JsonEditor.vue'
import TagsInput from '../../components/TagsInput.vue'
import PageHeader from '../../components/PageHeader.vue'
import { adminRules, errorMessage } from '../../api/client'
import { STATE_SEVERITY } from './RulesView.vue'

const TRANSITION_LABEL = { testing: 'Enviar para teste', draft: 'Voltar a rascunho', shadow: 'Ativar em sombra', published: 'Publicar', retired: 'Aposentar' }
const EMPTY_CASE = { name: '', reference_date: new Date().toISOString().slice(0, 10), scenario: {}, input: { kind: 'xml', fixture: 'spec/fixtures/nfe/sale_return_csosn_102.xml' }, catalog: {}, expect: { findings: [] } }

export default {
  name: 'AdminRuleEditorView',
  components: { PageHeader, Button, InputText, Select, Tag, Message, Dialog, DataTable, Column, Tabs, TabList, Tab, TabPanels, TabPanel, JsonEditor, TagsInput },
  props: { id: { type: String, required: true } },
  data() {
    return { rule: null, form: null, body: {}, bodyError: null, validation: null, results: {}, stats: null, busy: false, sev: STATE_SEVERITY, tlabel: TRANSITION_LABEL,
             scopes: ['item', 'document', 'cross_document', 'period', 'scenario'], severities: ['error', 'warning', 'info'],
             caseDialog: { visible: false, id: null, data: null }, caseError: null }
  },
  computed: {
    editable() { return ['draft', 'testing'].includes(this.rule?.state) },
    dirty() { return this.rule && JSON.stringify({ ...this.form, body: this.body }) !== JSON.stringify({ title: this.rule.title, scope: this.rule.scope, severity: this.rule.severity, effective_from: this.rule.effective_from, effective_until: this.rule.effective_until, tags: this.rule.tags, body: this.rule.body }) },
  },
  created() { this.load() },
  watch: { id() { this.load() } },
  methods: {
    toast(severity, summary, detail) { this.$toast.add({ severity, summary, detail, life: 5000 }) },
    async load() {
      this.rule = await adminRules.get(this.id)
      this.form = { title: this.rule.title, scope: this.rule.scope, severity: this.rule.severity, effective_from: this.rule.effective_from, effective_until: this.rule.effective_until, tags: [...this.rule.tags] }
      this.body = JSON.parse(JSON.stringify(this.rule.body))
      this.validation = null
      this.stats = await adminRules.stats(this.id)
    },
    async save() {
      if (this.bodyError) return this.toast('warn', 'JSON inválido', this.bodyError)
      this.busy = true
      try { this.rule = await adminRules.update(this.id, { ...this.form, effective_until: this.form.effective_until || null, body: this.body }); this.toast('success', 'Regra salva'); await this.validate() }
      catch (e) { this.toast('error', 'Falha ao salvar', errorMessage(e)) } finally { this.busy = false }
    },
    async validate() { this.validation = await adminRules.validate(this.id) },
    async transition(to) {
      this.busy = true
      try { this.rule = await adminRules.transition(this.id, to); this.toast('success', `Regra → ${to}`) ; await this.load() }
      catch (e) { const d = e?.response?.data; this.toast('error', d?.error ?? errorMessage(e), [...(d?.errors ?? []), ...(d?.failures ?? []).map(f => `${f.name}: ${f.details.join('; ')}`)].join('\n')) }
      finally { this.busy = false }
    },
    openCase(c = null) { this.caseDialog = { visible: true, id: c?.id ?? null, data: c ? JSON.parse(JSON.stringify({ name: c.name, reference_date: c.reference_date, scenario: c.scenario, input: c.input, catalog: c.catalog, expect: c.expect })) : JSON.parse(JSON.stringify(EMPTY_CASE)) } },
    async saveCase() {
      if (this.caseError) return
      const d = this.caseDialog.data
      try { this.caseDialog.id ? await adminRules.updateCase(this.id, this.caseDialog.id, d) : await adminRules.createCase(this.id, d); this.caseDialog.visible = false; await this.load() }
      catch (e) { this.toast('error', 'Falha', errorMessage(e)) }
    },
    async deleteCase(c) { this.$confirm.require({ header: 'Excluir caso', message: `Excluir "${c.name}"?`, acceptLabel: 'Excluir', rejectLabel: 'Cancelar', accept: async () => { await adminRules.deleteCase(this.id, c.id); await this.load() } }) },
    async runCase(c) { const r = await adminRules.runCase(this.id, c.id); this.results = { ...this.results, [c.id]: r }; await this.load() },
    async runAll() { const rs = await adminRules.runAll(this.id); this.results = Object.fromEntries(rs.map(r => [r.test_case_id, r])); await this.load() },
  },
}
</script>

<template>
  <div v-if="rule && form">
    <PageHeader :title="`${rule.code}  v${rule.version}`" :subtitle="rule.title">
      <template #actions>
        <Tag :severity="sev[rule.state]" :value="rule.state" />
        <Button v-for="to in rule.allowed_transitions" :key="to" :label="tlabel[to]" :severity="to === 'published' ? 'primary' : 'secondary'" :outlined="to !== 'published'" size="small" :loading="busy" @click="transition(to)" />
      </template>
    </PageHeader>
    <Message v-if="!editable" severity="info">Versão {{ rule.state }} não é editável. Para alterar, crie uma nova versão do código (lista de regras → Nova regra com o mesmo código).</Message>
    <div class="flex gap-2 text-xs items-center"><span class="text-slate-500">Versões:</span>
      <RouterLink v-for="v in rule.versions" :key="v.id" :to="`/admin/rules/${v.id}`" class="rounded px-2 py-0.5 border" :class="v.id === rule.id ? 'border-blue-600 text-blue-700' : 'border-slate-200 text-slate-600'">v{{ v.version }} · {{ v.state }} · {{ v.effective_from }}→{{ v.effective_until ?? '…' }}</RouterLink>
    </div>

    <div class="card">
    <Tabs value="def">
      <TabList><Tab value="def">Definição</Tab><Tab value="tests">Casos de teste ({{ rule.test_cases.length }})</Tab><Tab value="stats">Disparos recentes</Tab></TabList>
      <TabPanels>
        <TabPanel value="def">
          <div class="grid grid-cols-[1fr_360px] gap-6">
            <div class="space-y-2">
              <h3 class="text-sm font-medium">Corpo (DSL_RULES.md §1: let, applies_when, assert | primitive, message, params, group_by…)</h3>
              <JsonEditor v-model="body" :rows="26" @error="e => bodyError = e" />
            </div>
            <div class="space-y-3 text-sm">
              <label class="block">Título<InputText v-model="form.title" class="w-full mt-1" :disabled="!editable" /></label>
              <div class="grid grid-cols-2 gap-2">
                <label class="block">Escopo<Select v-model="form.scope" :options="scopes" class="w-full mt-1" :disabled="!editable" /></label>
                <label class="block">Severidade<Select v-model="form.severity" :options="severities" class="w-full mt-1" :disabled="!editable" /></label>
                <label class="block">Vigente de<InputText v-model="form.effective_from" type="date" class="w-full mt-1" :disabled="!editable" /></label>
                <label class="block">Vigente até<InputText v-model="form.effective_until" type="date" class="w-full mt-1" :disabled="!editable" /></label>
              </div>
              <label class="block">Tags<TagsInput v-model="form.tags" class="mt-1" /></label>
              <div class="flex gap-2"><Button label="Salvar" :disabled="!editable || !dirty" :loading="busy" @click="save" /><Button label="Validar" severity="secondary" @click="validate" /></div>
              <div v-if="validation" class="space-y-1">
                <Message :severity="validation.valid ? 'success' : 'error'">{{ validation.valid ? 'Regra válida' : `${validation.errors.length} erro(s)` }}</Message>
                <ul class="list-disc pl-5 text-xs text-red-700"><li v-for="e in validation.errors" :key="e">{{ e }}</li></ul>
                <ul class="list-disc pl-5 text-xs text-amber-700"><li v-for="w in validation.warnings" :key="w">{{ w }}</li></ul>
              </div>
            </div>
          </div>
        </TabPanel>
        <TabPanel value="tests">
          <div class="space-y-3">
            <div class="flex gap-2"><Button label="Novo caso" size="small" @click="openCase()" /><Button label="Rodar todos" size="small" severity="secondary" :disabled="!rule.test_cases.length" @click="runAll" /></div>
            <DataTable :value="rule.test_cases" dataKey="id">
              <Column field="name" header="Nome" />
              <Column field="reference_date" header="Data de ref." class="w-32" />
              <Column header="Espera" class="w-32"><template #body="{ data }">{{ data.expect?.findings?.length ? `${data.expect.findings.length} finding(s)` : 'nenhum finding' }}</template></Column>
              <Column header="Último resultado" class="w-40"><template #body="{ data }"><Tag v-if="data.last_result" :severity="data.last_result === 'passed' ? 'success' : 'danger'" :value="data.last_result === 'passed' ? 'passou' : 'falhou'" /><span v-else class="text-slate-400 text-xs">nunca rodou</span></template></Column>
              <Column class="w-56"><template #body="{ data }"><div class="flex gap-1"><Button label="Rodar" size="small" @click="runCase(data)" /><Button label="Editar" size="small" severity="secondary" @click="openCase(data)" /><Button label="Excluir" size="small" severity="danger" text @click="deleteCase(data)" /></div></template></Column>
            </DataTable>
            <div v-for="(r, cid) in results" :key="cid" class="rounded-md border border-surface p-3 text-xs space-y-1">
              <div class="flex items-center gap-2"><Tag :severity="r.passed ? 'success' : 'danger'" :value="r.passed ? 'passou' : 'falhou'" /><span class="font-medium">{{ r.name }}</span></div>
              <ul v-if="r.details.length" class="list-disc pl-5 text-red-700"><li v-for="d in r.details" :key="d">{{ d }}</li></ul>
              <div v-if="r.errors.length" class="text-red-700">Erros de avaliação: {{ r.errors.map(e => e.error).join('; ') }}</div>
              <details v-if="r.findings.length"><summary class="cursor-pointer">{{ r.findings.length }} finding(s) gerado(s)</summary><pre class="bg-slate-50 p-2 rounded overflow-auto">{{ JSON.stringify(r.findings, null, 2) }}</pre></details>
            </div>
          </div>
        </TabPanel>
        <TabPanel value="stats">
          <div v-if="stats" class="space-y-3 text-sm">
            <p>{{ stats.findings }} finding(s) nos últimos {{ stats.runs }} runs · por estado: {{ JSON.stringify(stats.by_state) }}</p>
            <DataTable :value="stats.by_group" size="small"><Column field="group_key" header="Agrupamento" /><Column field="count" header="Qtd" class="w-24" /></DataTable>
            <div v-for="(s, i) in stats.samples" :key="i" class="rounded-md border border-surface p-2 text-xs"><div>{{ s.message }}</div><div class="text-slate-500 font-mono">{{ JSON.stringify(s.evidence) }}</div></div>
          </div>
        </TabPanel>
      </TabPanels>
    </Tabs>
    </div>

    <Dialog v-model:visible="caseDialog.visible" modal :header="caseDialog.id ? 'Editar caso de teste' : 'Novo caso de teste'" class="w-[900px]">
      <div v-if="caseDialog.data" class="space-y-3 text-sm">
        <div class="grid grid-cols-2 gap-3">
          <label class="block">Nome<InputText v-model="caseDialog.data.name" class="w-full mt-1" /></label>
          <label class="block">Data de referência<InputText v-model="caseDialog.data.reference_date" type="date" class="w-full mt-1" /></label>
        </div>
        <p class="text-xs text-slate-500">Formato: DSL_RULES.md §10 — <span class="font-mono">input</span> (xml com fixture/xml ou canonical com document), <span class="font-mono">scenario</span> parcial, <span class="font-mono">catalog</span> stub, <span class="font-mono">expect.findings</span>.</p>
        <JsonEditor :modelValue="{ scenario: caseDialog.data.scenario, input: caseDialog.data.input, catalog: caseDialog.data.catalog, expect: caseDialog.data.expect }" :rows="16" @update:modelValue="v => Object.assign(caseDialog.data, v)" @error="e => caseError = e" />
      </div>
      <template #footer><Button label="Cancelar" severity="secondary" @click="caseDialog.visible = false" /><Button label="Salvar" :disabled="!!caseError" @click="saveCase" /></template>
    </Dialog>
  </div>
</template>
