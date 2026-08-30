<script>
import PageHeader from '../components/PageHeader.vue'
import { reactive } from 'vue'
import { useQuery, useMutation, useQueryClient } from '@tanstack/vue-query'
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import Textarea from 'primevue/textarea'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Dialog from 'primevue/dialog'
import Tabs from 'primevue/tabs'
import TabList from 'primevue/tablist'
import Tab from 'primevue/tab'
import TabPanels from 'primevue/tabpanels'
import TabPanel from 'primevue/tabpanel'
import JsonEditor from '../components/JsonEditor.vue'
import TagsInput from '../components/TagsInput.vue'
import { overrides, clientsApi, errorMessage } from '../api/client'

const ACTIONS = [{ value: 'disable', label: 'Desativar regra' }, { value: 'enable', label: 'Reativar (sobre desativação da firma)' }, { value: 'adjust', label: 'Ajustar (severidade/params/assert/message)' }]

export default {
  name: 'OverridesView',
  components: { PageHeader, Button, InputText, Select, Textarea, DataTable, Column, Dialog, Tabs, TabList, Tab, TabPanels, TabPanel, JsonEditor, TagsInput },
  setup() {
    const queryClient = useQueryClient()
    const rules = reactive(useQuery({ queryKey: ['rule_overrides'], queryFn: () => overrides.rules() }))
    const rows = reactive(useQuery({ queryKey: ['row_overrides'], queryFn: () => overrides.rows() }))
    const tables = reactive(useQuery({ queryKey: ['reference_tables'], queryFn: overrides.tables }))
    const clients = reactive(useQuery({ queryKey: ['clients'], queryFn: () => clientsApi.list() }))
    const createRule = reactive(useMutation({ mutationFn: overrides.createRule, onSuccess: () => queryClient.invalidateQueries({ queryKey: ['rule_overrides'] }) }))
    const deleteRule = reactive(useMutation({ mutationFn: overrides.deleteRule, onSuccess: () => queryClient.invalidateQueries({ queryKey: ['rule_overrides'] }) }))
    const createRow = reactive(useMutation({ mutationFn: overrides.createRow, onSuccess: () => queryClient.invalidateQueries({ queryKey: ['row_overrides'] }) }))
    const deleteRow = reactive(useMutation({ mutationFn: overrides.deleteRow, onSuccess: () => queryClient.invalidateQueries({ queryKey: ['row_overrides'] }) }))
    return { rules, rows, tables, clients, createRule, deleteRule, createRow, deleteRow }
  },
  data() {
    const today = new Date().toISOString().slice(0, 10)
    return { actions: ACTIONS,
      ruleDialog: { visible: false, form: { rule_code: '', source_type: 'client', source_id: null, override_action: 'disable', patch: {}, effective_from: today, effective_until: null, justification: '' } },
      rowDialog: { visible: false, form: { reference_table_id: null, source_type: 'client', source_id: null, key: [], data: {}, effective_from: today, effective_until: null, legal_basis: '', justification: '' } } }
  },
  computed: {
    sources() { return [{ value: 'firm', label: 'Toda a firma' }, { value: 'client', label: 'Um cliente' }] },
    tableOptions() { return (this.tables.data ?? []).map(t => ({ value: t.id, label: `${t.name} (${t.key_names.join(' + ')})` })) },
    selectedTable() { return (this.tables.data ?? []).find(t => t.id === this.rowDialog.form.reference_table_id) },
  },
  methods: {
    toast(s, summary, detail) { this.$toast.add({ severity: s, summary, detail, life: 4000 }) },
    clientName(o) { return o.source_type === 'firm' ? 'firma' : (this.clients.data ?? []).find(c => c.id === o.source_id)?.legal_name ?? `cliente #${o.source_id}` },
    async saveRule() {
      const f = { ...this.ruleDialog.form }
      if (f.source_type === 'firm') f.source_id = null
      try { await this.createRule.mutateAsync(f); this.ruleDialog.visible = false; this.toast('success', 'Sobreposição criada') } catch (e) { this.toast('error', 'Falha', errorMessage(e)) }
    },
    async saveRow() {
      const f = { ...this.rowDialog.form }
      if (f.source_type === 'firm') f.source_id = null
      try { await this.createRow.mutateAsync(f); this.rowDialog.visible = false; this.toast('success', 'Linha sobreposta') } catch (e) { this.toast('error', 'Falha', errorMessage(e)) }
    },
    confirmDelete(kind, o) {
      this.$confirm.require({ header: 'Remover sobreposição', message: 'A regra/tabela da plataforma volta a valer. Continuar?', acceptLabel: 'Remover', rejectLabel: 'Cancelar',
        accept: () => (kind === 'rule' ? this.deleteRule : this.deleteRow).mutate(o.id) })
    },
  },
}
</script>

<template>
  <div>
    <PageHeader title="Sobreposições da firma" subtitle="Registre o entendimento do escritório quando ele diverge da plataforma. Toda sobreposição exige justificativa e fica identificada nos apontamentos como responsabilidade do escritório." />
    <div class="card">
    <Tabs value="rules">
      <TabList><Tab value="rules">Regras ({{ rules.data?.length ?? 0 }})</Tab><Tab value="rows">Tabelas ({{ rows.data?.length ?? 0 }})</Tab></TabList>
      <TabPanels>
        <TabPanel value="rules">
          <div class="space-y-3">
            <Button label="Nova sobreposição de regra" size="small" @click="ruleDialog.visible = true" />
            <DataTable :value="rules.data ?? []" :loading="rules.isPending" dataKey="id" size="small">
              <Column header="Regra"><template #body="{ data }"><span class="font-mono text-xs">{{ data.rule_code }}</span></template></Column>
              <Column header="Alvo" class="w-48"><template #body="{ data }">{{ clientName(data) }}</template></Column>
              <Column field="override_action" header="Ação" class="w-28" />
              <Column header="Patch"><template #body="{ data }"><span class="font-mono text-xs">{{ JSON.stringify(data.patch) }}</span></template></Column>
              <Column header="Vigência" class="w-44"><template #body="{ data }"><span class="text-xs">{{ data.effective_from }} → {{ data.effective_until ?? '…' }}</span></template></Column>
              <Column field="justification" header="Justificativa" />
              <Column header="Por" class="w-32"><template #body="{ data }"><span class="text-xs">{{ data.created_by }}</span></template></Column>
              <Column class="w-24"><template #body="{ data }"><Button label="Remover" size="small" severity="danger" text @click="confirmDelete('rule', data)" /></template></Column>
            </DataTable>
          </div>
        </TabPanel>
        <TabPanel value="rows">
          <div class="space-y-3">
            <Button label="Nova linha sobreposta" size="small" @click="rowDialog.visible = true" />
            <DataTable :value="rows.data ?? []" :loading="rows.isPending" dataKey="id" size="small">
              <Column header="Tabela" class="w-40"><template #body="{ data }"><span class="font-mono text-xs">{{ data.table_code }}</span></template></Column>
              <Column header="Alvo" class="w-48"><template #body="{ data }">{{ clientName(data) }}</template></Column>
              <Column header="Chave" class="w-40"><template #body="{ data }"><span class="font-mono text-xs">{{ data.key.join(' | ') }}</span></template></Column>
              <Column header="Dados"><template #body="{ data }"><span class="font-mono text-xs">{{ JSON.stringify(data.data) }}</span></template></Column>
              <Column header="Vigência" class="w-44"><template #body="{ data }"><span class="text-xs">{{ data.effective_from }} → {{ data.effective_until ?? '…' }}</span></template></Column>
              <Column field="legal_basis" header="Base legal" />
              <Column class="w-24"><template #body="{ data }"><Button label="Remover" size="small" severity="danger" text @click="confirmDelete('row', data)" /></template></Column>
            </DataTable>
          </div>
        </TabPanel>
      </TabPanels>
    </Tabs>
    </div>

    <Dialog v-model:visible="ruleDialog.visible" modal header="Sobrepor regra" class="w-[720px]">
      <div class="space-y-3 text-sm">
        <label class="block">Código da regra<InputText v-model="ruleDialog.form.rule_code" class="w-full mt-1 font-mono" placeholder="ICMS.CSOSN.SALE_RETURN" /></label>
        <div class="grid grid-cols-2 gap-3">
          <label class="block">Alvo<Select v-model="ruleDialog.form.source_type" :options="sources" optionValue="value" optionLabel="label" class="w-full mt-1" /></label>
          <label v-if="ruleDialog.form.source_type === 'client'" class="block">Cliente<Select v-model="ruleDialog.form.source_id" :options="clients.data ?? []" optionValue="id" optionLabel="legal_name" class="w-full mt-1" filter /></label>
        </div>
        <label class="block">Ação<Select v-model="ruleDialog.form.override_action" :options="actions" optionValue="value" optionLabel="label" class="w-full mt-1" /></label>
        <div v-if="ruleDialog.form.override_action === 'adjust'"><span>Patch (severity, params, assert, applies_when, message)</span><JsonEditor v-model="ruleDialog.form.patch" :rows="6" /></div>
        <div class="grid grid-cols-2 gap-3">
          <label class="block">Vigente de<InputText v-model="ruleDialog.form.effective_from" type="date" class="w-full mt-1" /></label>
          <label class="block">Vigente até<InputText v-model="ruleDialog.form.effective_until" type="date" class="w-full mt-1" /></label>
        </div>
        <label class="block">Justificativa (obrigatória)<Textarea v-model="ruleDialog.form.justification" rows="2" class="w-full mt-1" /></label>
      </div>
      <template #footer><Button label="Cancelar" severity="secondary" @click="ruleDialog.visible = false" /><Button label="Salvar" :loading="createRule.isPending" :disabled="!ruleDialog.form.rule_code || !ruleDialog.form.justification" @click="saveRule" /></template>
    </Dialog>

    <Dialog v-model:visible="rowDialog.visible" modal header="Sobrepor linha de tabela" class="w-[720px]">
      <div class="space-y-3 text-sm">
        <label class="block">Tabela<Select v-model="rowDialog.form.reference_table_id" :options="tableOptions" optionValue="value" optionLabel="label" class="w-full mt-1" /></label>
        <div class="grid grid-cols-2 gap-3">
          <label class="block">Alvo<Select v-model="rowDialog.form.source_type" :options="sources" optionValue="value" optionLabel="label" class="w-full mt-1" /></label>
          <label v-if="rowDialog.form.source_type === 'client'" class="block">Cliente<Select v-model="rowDialog.form.source_id" :options="clients.data ?? []" optionValue="id" optionLabel="legal_name" class="w-full mt-1" filter /></label>
        </div>
        <label class="block">Chave <span v-if="selectedTable" class="text-xs text-slate-500">({{ selectedTable.key_names.join(' + ') }})</span><TagsInput v-model="rowDialog.form.key" class="mt-1" placeholder="SP, 22021000" /></label>
        <div><span>Dados (ex.: {"rate": "12.00"})</span><JsonEditor v-model="rowDialog.form.data" :rows="4" /></div>
        <div class="grid grid-cols-2 gap-3">
          <label class="block">Vigente de<InputText v-model="rowDialog.form.effective_from" type="date" class="w-full mt-1" /></label>
          <label class="block">Vigente até<InputText v-model="rowDialog.form.effective_until" type="date" class="w-full mt-1" /></label>
        </div>
        <label class="block">Base legal<InputText v-model="rowDialog.form.legal_basis" class="w-full mt-1" placeholder="Regime especial nº…, Decreto…" /></label>
        <label class="block">Justificativa (obrigatória)<Textarea v-model="rowDialog.form.justification" rows="2" class="w-full mt-1" /></label>
      </div>
      <template #footer><Button label="Cancelar" severity="secondary" @click="rowDialog.visible = false" /><Button label="Salvar" :loading="createRow.isPending" :disabled="!rowDialog.form.reference_table_id || !rowDialog.form.key.length || !rowDialog.form.justification" @click="saveRow" /></template>
    </Dialog>
  </div>
</template>
