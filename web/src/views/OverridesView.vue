<script>
import PageHeader from '../components/PageHeader.vue'
import { reactive } from 'vue'
import { useQuery, useMutation, useQueryClient } from '@tanstack/vue-query'
import { Form, Field } from 'vee-validate'
import { toTypedSchema } from '@vee-validate/zod'
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
import FormField from '../components/FormField.vue'
import JsonEditor from '../components/JsonEditor.vue'
import TagsInput from '../components/TagsInput.vue'
import { overrides, clientsApi, errorMessage } from '../api/client'
import { ruleOverrideSchema, rowOverrideSchema, OVERRIDE_ACTIONS, OVERRIDE_SOURCES } from '../schemas/override'
import { fmtDate, todayIso } from '../utils/date'

export default {
  name: 'OverridesView',
  components: { PageHeader, Form, Field, Button, InputText, Select, Textarea, DataTable, Column, Dialog, Tabs, TabList, Tab, TabPanels, TabPanel, FormField, JsonEditor, TagsInput },
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
    return { actions: OVERRIDE_ACTIONS, sources: OVERRIDE_SOURCES,
      ruleSchema: toTypedSchema(ruleOverrideSchema), rowSchema: toTypedSchema(rowOverrideSchema),
      ruleDialog: { visible: false, initial: {} }, rowDialog: { visible: false, initial: {} } }
  },
  computed: {
    tableOptions() { return (this.tables.data ?? []).map(t => ({ value: t.id, label: `${t.name} (${t.key_names.join(' + ')})` })) },
  },
  methods: {
    toast(s, summary, detail) { this.$toast.add({ severity: s, summary, detail, life: 4000 }) },
    fmtDate,
    clientName(o) { return o.source_type === 'firm' ? 'firma' : (this.clients.data ?? []).find(c => c.id === o.source_id)?.legal_name ?? `cliente #${o.source_id}` },
    keyNamesOf(id) { return (this.tables.data ?? []).find(t => t.id === id)?.key_names ?? [] },
    openRule() {
      this.ruleDialog = { visible: true, initial: { rule_code: '', source_type: 'client', source_id: null, override_action: 'disable', patch: {}, effective_from: todayIso(), effective_until: null, justification: '' } }
    },
    openRow() {
      this.rowDialog = { visible: true, initial: { reference_table_id: null, source_type: 'client', source_id: null, key: [], data: {}, effective_from: todayIso(), effective_until: null, legal_basis: '', justification: '' } }
    },
    // O payload enviado é o mesmo de antes: alvo "firma" zera source_id e vigência vazia vai como null.
    payload(values) {
      const f = { ...values, effective_until: values.effective_until || null }
      if (f.source_type === 'firm') f.source_id = null
      return f
    },
    async saveRule(values) {
      try { await this.createRule.mutateAsync({ ...this.payload(values), patch: values.patch ?? {} }); this.ruleDialog.visible = false; this.toast('success', 'Sobreposição criada') }
      catch (e) { this.toast('error', 'Falha', errorMessage(e)) }
    },
    async saveRow(values) {
      try { await this.createRow.mutateAsync({ ...this.payload(values), data: values.data ?? {} }); this.rowDialog.visible = false; this.toast('success', 'Linha sobreposta') }
      catch (e) { this.toast('error', 'Falha', errorMessage(e)) }
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
            <Button label="Nova sobreposição de regra" size="small" @click="openRule" />
            <DataTable :value="rules.data ?? []" :loading="rules.isPending" dataKey="id" size="small">
              <Column header="Regra"><template #body="{ data }"><span class="font-mono text-xs">{{ data.rule_code }}</span></template></Column>
              <Column header="Alvo" class="w-48"><template #body="{ data }">{{ clientName(data) }}</template></Column>
              <Column field="override_action" header="Ação" class="w-28" />
              <Column header="Patch"><template #body="{ data }"><span class="font-mono text-xs">{{ JSON.stringify(data.patch) }}</span></template></Column>
              <Column header="Vigência" class="w-44"><template #body="{ data }"><span class="text-xs">{{ fmtDate(data.effective_from) }} → {{ data.effective_until ? fmtDate(data.effective_until) : '…' }}</span></template></Column>
              <Column field="justification" header="Justificativa" />
              <Column header="Por" class="w-32"><template #body="{ data }"><span class="text-xs">{{ data.created_by }}</span></template></Column>
              <Column class="w-24"><template #body="{ data }"><Button label="Remover" size="small" severity="danger" text @click="confirmDelete('rule', data)" /></template></Column>
            </DataTable>
          </div>
        </TabPanel>
        <TabPanel value="rows">
          <div class="space-y-3">
            <Button label="Nova linha sobreposta" size="small" @click="openRow" />
            <DataTable :value="rows.data ?? []" :loading="rows.isPending" dataKey="id" size="small">
              <Column header="Tabela" class="w-40"><template #body="{ data }"><span class="font-mono text-xs">{{ data.table_code }}</span></template></Column>
              <Column header="Alvo" class="w-48"><template #body="{ data }">{{ clientName(data) }}</template></Column>
              <Column header="Chave" class="w-40"><template #body="{ data }"><span class="font-mono text-xs">{{ data.key.join(' | ') }}</span></template></Column>
              <Column header="Dados"><template #body="{ data }"><span class="font-mono text-xs">{{ JSON.stringify(data.data) }}</span></template></Column>
              <Column header="Vigência" class="w-44"><template #body="{ data }"><span class="text-xs">{{ fmtDate(data.effective_from) }} → {{ data.effective_until ? fmtDate(data.effective_until) : '…' }}</span></template></Column>
              <Column field="legal_basis" header="Base legal" />
              <Column class="w-24"><template #body="{ data }"><Button label="Remover" size="small" severity="danger" text @click="confirmDelete('row', data)" /></template></Column>
            </DataTable>
          </div>
        </TabPanel>
      </TabPanels>
    </Tabs>
    </div>

    <Dialog v-model:visible="ruleDialog.visible" modal header="Sobrepor regra" class="w-[720px]">
      <Form :validation-schema="ruleSchema" :initial-values="ruleDialog.initial" @submit="saveRule" v-slot="{ errors, values, isSubmitting }">
        <div class="space-y-3 text-sm">
          <Field name="rule_code" v-slot="{ value, handleChange, handleBlur }">
            <FormField label="Código da regra" :error="errors.rule_code"><InputText :modelValue="value" class="w-full font-mono" placeholder="ICMS.CSOSN.SALE_RETURN" @update:modelValue="handleChange" @blur="handleBlur" /></FormField>
          </Field>
          <div class="grid grid-cols-2 gap-3">
            <Field name="source_type" v-slot="{ value, handleChange }">
              <FormField label="Alvo" :error="errors.source_type"><Select :modelValue="value" :options="sources" optionValue="value" optionLabel="label" class="w-full" @update:modelValue="handleChange" /></FormField>
            </Field>
            <Field v-if="values.source_type === 'client'" name="source_id" v-slot="{ value, handleChange }">
              <FormField label="Cliente" :error="errors.source_id"><Select :modelValue="value" :options="clients.data ?? []" optionValue="id" optionLabel="legal_name" class="w-full" filter @update:modelValue="handleChange" /></FormField>
            </Field>
          </div>
          <Field name="override_action" v-slot="{ value, handleChange }">
            <FormField label="Ação" :error="errors.override_action"><Select :modelValue="value" :options="actions" optionValue="value" optionLabel="label" class="w-full" @update:modelValue="handleChange" /></FormField>
          </Field>
          <Field v-if="values.override_action === 'adjust'" name="patch" v-slot="{ value, handleChange }">
            <FormField label="Patch (severity, params, assert, applies_when, message)" :error="errors.patch"><JsonEditor :modelValue="value ?? {}" :rows="6" @update:modelValue="handleChange" /></FormField>
          </Field>
          <div class="grid grid-cols-2 gap-3">
            <Field name="effective_from" v-slot="{ value, handleChange }">
              <FormField label="Vigente de" :error="errors.effective_from"><InputText :modelValue="value" type="date" class="w-full" @update:modelValue="handleChange" /></FormField>
            </Field>
            <Field name="effective_until" v-slot="{ value, handleChange }">
              <FormField label="Vigente até" :error="errors.effective_until" hint="vazio = em aberto"><InputText :modelValue="value ?? ''" type="date" class="w-full" @update:modelValue="v => handleChange(v || null)" /></FormField>
            </Field>
          </div>
          <Field name="justification" v-slot="{ value, handleChange, handleBlur }">
            <FormField label="Justificativa (obrigatória)" :error="errors.justification"><Textarea :modelValue="value" rows="2" class="w-full" @update:modelValue="handleChange" @blur="handleBlur" /></FormField>
          </Field>
          <div class="flex justify-end gap-2 pt-2">
            <Button type="button" label="Cancelar" severity="secondary" @click="ruleDialog.visible = false" />
            <Button type="submit" label="Salvar" :loading="isSubmitting || createRule.isPending" />
          </div>
        </div>
      </Form>
    </Dialog>

    <Dialog v-model:visible="rowDialog.visible" modal header="Sobrepor linha de tabela" class="w-[720px]">
      <Form :validation-schema="rowSchema" :initial-values="rowDialog.initial" @submit="saveRow" v-slot="{ errors, values, isSubmitting }">
        <div class="space-y-3 text-sm">
          <Field name="reference_table_id" v-slot="{ value, handleChange }">
            <FormField label="Tabela" :error="errors.reference_table_id"><Select :modelValue="value" :options="tableOptions" optionValue="value" optionLabel="label" class="w-full" @update:modelValue="handleChange" /></FormField>
          </Field>
          <div class="grid grid-cols-2 gap-3">
            <Field name="source_type" v-slot="{ value, handleChange }">
              <FormField label="Alvo" :error="errors.source_type"><Select :modelValue="value" :options="sources" optionValue="value" optionLabel="label" class="w-full" @update:modelValue="handleChange" /></FormField>
            </Field>
            <Field v-if="values.source_type === 'client'" name="source_id" v-slot="{ value, handleChange }">
              <FormField label="Cliente" :error="errors.source_id"><Select :modelValue="value" :options="clients.data ?? []" optionValue="id" optionLabel="legal_name" class="w-full" filter @update:modelValue="handleChange" /></FormField>
            </Field>
          </div>
          <Field name="key" v-slot="{ value, handleChange }">
            <FormField label="Chave" :error="errors.key" :hint="keyNamesOf(values.reference_table_id).join(' + ')"><TagsInput :modelValue="value ?? []" placeholder="SP, 22021000" @update:modelValue="handleChange" /></FormField>
          </Field>
          <Field name="data" v-slot="{ value, handleChange }">
            <FormField label="Dados (ex.: {&quot;rate&quot;: &quot;12.00&quot;})" :error="errors.data"><JsonEditor :modelValue="value ?? {}" :rows="4" @update:modelValue="handleChange" /></FormField>
          </Field>
          <div class="grid grid-cols-2 gap-3">
            <Field name="effective_from" v-slot="{ value, handleChange }">
              <FormField label="Vigente de" :error="errors.effective_from"><InputText :modelValue="value" type="date" class="w-full" @update:modelValue="handleChange" /></FormField>
            </Field>
            <Field name="effective_until" v-slot="{ value, handleChange }">
              <FormField label="Vigente até" :error="errors.effective_until" hint="vazio = em aberto"><InputText :modelValue="value ?? ''" type="date" class="w-full" @update:modelValue="v => handleChange(v || null)" /></FormField>
            </Field>
          </div>
          <Field name="legal_basis" v-slot="{ value, handleChange }">
            <FormField label="Base legal" :error="errors.legal_basis"><InputText :modelValue="value ?? ''" class="w-full" placeholder="Regime especial nº…, Decreto…" @update:modelValue="handleChange" /></FormField>
          </Field>
          <Field name="justification" v-slot="{ value, handleChange, handleBlur }">
            <FormField label="Justificativa (obrigatória)" :error="errors.justification"><Textarea :modelValue="value" rows="2" class="w-full" @update:modelValue="handleChange" @blur="handleBlur" /></FormField>
          </Field>
          <div class="flex justify-end gap-2 pt-2">
            <Button type="button" label="Cancelar" severity="secondary" @click="rowDialog.visible = false" />
            <Button type="submit" label="Salvar" :loading="isSubmitting || createRow.isPending" />
          </div>
        </div>
      </Form>
    </Dialog>
  </div>
</template>
