<script>
import PageHeader from '../components/PageHeader.vue'
import { reactive } from 'vue'
import { useQuery, useMutation, useQueryClient } from '@tanstack/vue-query'
import { Form, Field, FieldArray } from 'vee-validate'
import { toTypedSchema } from '@vee-validate/zod'
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import Checkbox from 'primevue/checkbox'
import Dialog from 'primevue/dialog'
import Message from 'primevue/message'
import Tag from 'primevue/tag'
import FormField from '../components/FormField.vue'
import TagsInput from '../components/TagsInput.vue'
import { clientsApi, scenarios, errorMessage } from '../api/client'
import { taxScenarioSchema, TAX_REGIMES, ACTIVITIES, UFS } from '../schemas/taxScenario'

const ACTIVITY_LABELS = { commerce: 'Comércio', industry: 'Indústria', service: 'Serviços', rural: 'Rural' }
const BENEFIT_KINDS = [
  { value: 'reduced_base', label: 'Redução de base' }, { value: 'presumed_credit', label: 'Crédito presumido' },
  { value: 'deferral', label: 'Diferimento' }, { value: 'exemption', label: 'Isenção' }, { value: 'suspension', label: 'Suspensão' },
]
const PIS_REGIMES = [{ value: 'simples', label: 'Simples Nacional' }, { value: 'cumulative', label: 'Cumulativo (0,65% / 3%)' }, { value: 'non_cumulative', label: 'Não cumulativo (1,65% / 7,6%)' }]
const IBS_REGIMES = [{ value: 'regular', label: 'Regular' }, { value: 'simples_nacional_opt_in', label: 'Simples com opção IBS/CBS por fora' }]
const EMPTY = { tax_regime: undefined, uf: 'SP', city_code: '', icms_taxpayer: true, ipi_taxpayer: false, iss_taxpayer: false, activity: [], cnae: { primary: '', secondary: [] },
  sells_to_final_consumer: false, uses_nfce: false, exports: false, imports: false, st: { source: 'catalog', overrides: [] }, benefits: [],
  pis_cofins: { regime: undefined }, ibs_cbs: { regime: 'regular' }, effective_from: new Date().toISOString().slice(0, 10), effective_until: null }

export default {
  name: 'ScenarioView',
  components: { PageHeader, Form, Field, FieldArray, Button, InputText, Select, Checkbox, Dialog, Message, Tag, FormField, TagsInput },
  props: { id: { type: String, required: true } },
  setup(props) {
    const queryClient = useQueryClient()
    const client = reactive(useQuery({ queryKey: ['client', props.id], queryFn: () => clientsApi.get(props.id) }))
    const list = reactive(useQuery({ queryKey: ['scenarios', props.id], queryFn: () => scenarios.list(props.id) }))
    const invalidate = () => queryClient.invalidateQueries({ queryKey: ['scenarios', props.id] })
    const save = reactive(useMutation({ mutationFn: ({ sid, payload }) => (sid ? scenarios.update(props.id, sid, payload) : scenarios.create(props.id, payload)), onSuccess: invalidate }))
    const publish = reactive(useMutation({ mutationFn: (sid) => scenarios.publish(props.id, sid), onSuccess: invalidate }))
    const destroy = reactive(useMutation({ mutationFn: (sid) => scenarios.destroy(props.id, sid), onSuccess: invalidate }))
    const infer = reactive(useMutation({ mutationFn: (months) => scenarios.infer(props.id, months) }))
    return { client, list, save, publish, destroy, infer }
  },
  data() {
    return {
      schema: toTypedSchema(taxScenarioSchema), regimes: TAX_REGIMES, activities: ACTIVITIES, activityLabels: ACTIVITY_LABELS, ufs: UFS,
      benefitKinds: BENEFIT_KINDS, pisRegimes: PIS_REGIMES, ibsRegimes: IBS_REGIMES, annexes: ['I', 'II', 'III', 'IV', 'V'],
      editing: null,        // { sid, initial, fieldOrigins }
      inferDialog: false, proposal: null, months: 6,
    }
  },
  computed: {
    versions() { return this.list.data ?? [] },
  },
  methods: {
    toast(severity, summary, detail) { this.$toast.add({ severity, summary, detail, life: 4000 }) },
    newVersion(base = null) {
      const src = base ? { ...EMPTY, ...base.data, effective_from: new Date().toISOString().slice(0, 10), effective_until: null } : { ...EMPTY, uf: this.client.data?.uf ?? 'SP', city_code: this.client.data?.city_code ?? '' }
      this.editing = { sid: null, initial: src, fieldOrigins: base ? { ...base.field_origins } : {} }
    },
    edit(s) { this.editing = { sid: s.id, initial: { ...EMPTY, ...s.data, effective_from: s.effective_from, effective_until: s.effective_until }, fieldOrigins: { ...s.field_origins } } },
    async submit(values) {
      const { effective_from, effective_until, ...data } = values
      try {
        await this.save.mutateAsync({ sid: this.editing.sid, payload: { effective_from, effective_until: effective_until || null, data, field_origins: this.editing.fieldOrigins } })
        this.editing = null; this.toast('success', 'Rascunho salvo')
      } catch (e) { this.toast('error', 'Falha ao salvar', errorMessage(e)) }
    },
    async doPublish(s) {
      this.$confirm.require({ header: 'Publicar cenário', message: `Publicar a versão vigente a partir de ${s.effective_from}? A versão anterior será encerrada no dia anterior.`, acceptLabel: 'Publicar', rejectLabel: 'Cancelar',
        accept: async () => { try { await this.publish.mutateAsync(s.id); this.toast('success', 'Cenário publicado') } catch (e) { this.toast('error', 'Cenário inválido', (e?.response?.data?.errors ?? [errorMessage(e)]).join('; ')) } } })
    },
    doDestroy(s) { this.$confirm.require({ header: 'Excluir rascunho', message: 'Excluir este rascunho?', acceptLabel: 'Excluir', rejectLabel: 'Cancelar', accept: () => this.destroy.mutate(s.id) }) },
    async runInference() {
      try { this.proposal = await this.infer.mutateAsync(this.months); this.inferDialog = true } catch (e) { this.toast('error', 'Falha na inferência', errorMessage(e)) }
    },
    applyProposal(setValues) {
      const fields = this.proposal.fields
      const patch = {}
      const origins = {}
      for (const [k, f] of Object.entries(fields)) { patch[k] = f.value; origins[k] = 'inferred' }
      setValues(patch)
      this.editing.fieldOrigins = { ...this.editing.fieldOrigins, ...origins }
      this.inferDialog = false
      this.toast('info', 'Proposta aplicada', 'Revise cada campo antes de salvar.')
    },
    confidenceSeverity(c) { return c >= 0.85 ? 'success' : c >= 0.6 ? 'warn' : 'error' },
    fmt(v) { return typeof v === 'object' ? JSON.stringify(v) : String(v) },
    stateSeverity(s) { return s === 'published' ? 'success' : 'secondary' },
  },
}
</script>

<template>
  <div>
    <PageHeader title="Cenário tributário" :subtitle="client.data ? `${client.data.legal_name} · ${client.data.cnpj} · ${client.data.documents_count} documentos` : ''">
      <template #actions v-if="!editing"><Button label="Nova versão" icon="pi pi-plus" @click="newVersion(versions.find(v => v.state === 'published'))" /></template>
    </PageHeader>

    <!-- Versões -->
    <div v-if="!editing" class="card !p-0 divide-y divide-surface">
      <div v-for="s in versions" :key="s.id" class="flex items-center gap-3 px-4 py-3 text-sm">
        <Tag :severity="stateSeverity(s.state)" :value="s.state === 'published' ? 'publicado' : 'rascunho'" />
        <span>{{ s.effective_from }} → {{ s.effective_until ?? 'em aberto' }}</span>
        <span class="text-slate-500">{{ regimes.find(r => r.value === s.data.tax_regime)?.label ?? s.data.tax_regime }} · {{ s.data.uf }}</span>
        <div class="ml-auto flex gap-1">
          <Button v-if="s.state === 'draft'" label="Editar" size="small" severity="secondary" @click="edit(s)" />
          <Button v-if="s.state === 'draft'" label="Publicar" size="small" @click="doPublish(s)" />
          <Button v-if="s.state === 'draft'" label="Excluir" size="small" severity="danger" @click="doDestroy(s)" />
          <Button v-else label="Duplicar" size="small" severity="secondary" @click="newVersion(s)" />
        </div>
      </div>
      <p v-if="!versions.length && !list.isPending" class="px-4 py-6 text-center text-slate-500 text-sm">Nenhum cenário. Crie uma versão — ou infira a partir das notas já enviadas.</p>
    </div>

    <!-- Editor -->
    <Form v-if="editing" :validation-schema="schema" :initial-values="editing.initial" @submit="submit" v-slot="{ errors, values, setValues, isSubmitting }">
      <div class="space-y-6">
        <div class="flex items-center gap-2">
          <Button type="button" label="Inferir das notas" severity="secondary" size="small" :loading="infer.isPending" @click="runInference" />
          <Select v-model="months" :options="[3, 6, 12]" class="text-xs" />
          <span class="text-xs text-slate-500">últimos meses</span>
          <span class="ml-auto text-xs text-slate-500">Campos marcados <Tag severity="info" value="inferido" /> vieram das notas — confirme cada um.</span>
        </div>

        <section class="card grid grid-cols-3 gap-4">
          <h2 class="col-span-3 card-title !mb-0">Regime e localização</h2>
          <Field name="tax_regime" v-slot="{ value, handleChange }">
            <FormField label="Regime tributário" :error="errors.tax_regime"><Select :modelValue="value" :options="regimes" optionValue="value" optionLabel="label" class="w-full" placeholder="Selecione" @update:modelValue="handleChange" /><Tag v-if="editing.fieldOrigins.tax_regime === 'inferred'" severity="info" value="inferido" class="mt-1" /></FormField>
          </Field>
          <Field name="simples_annex" v-slot="{ value, handleChange }">
            <FormField label="Anexo do Simples" :error="errors.simples_annex"><Select :modelValue="value" :options="annexes" class="w-full" showClear placeholder="—" :disabled="!String(values.tax_regime ?? '').startsWith('simples')" @update:modelValue="handleChange" /></FormField>
          </Field>
          <Field name="effective_from" v-slot="{ value, handleChange }">
            <FormField label="Vigência a partir de" :error="errors.effective_from"><InputText :modelValue="value" type="date" @update:modelValue="handleChange" /></FormField>
          </Field>
          <Field name="uf" v-slot="{ value, handleChange }">
            <FormField label="UF" :error="errors.uf"><Select :modelValue="value" :options="ufs" class="w-full" @update:modelValue="handleChange" /></FormField>
          </Field>
          <Field name="city_code" v-slot="{ value, handleChange }">
            <FormField label="Município (IBGE)" :error="errors.city_code"><InputText :modelValue="value" placeholder="3550308" @update:modelValue="handleChange" /></FormField>
          </Field>
          <Field name="effective_until" v-slot="{ value, handleChange }">
            <FormField label="Vigência até" :error="errors.effective_until" hint="vazio = em aberto"><InputText :modelValue="value ?? ''" type="date" @update:modelValue="v => handleChange(v || null)" /></FormField>
          </Field>
          <Field name="cnae.primary" v-slot="{ value, handleChange }">
            <FormField label="CNAE principal" :error="errors['cnae.primary']"><InputText :modelValue="value" placeholder="4711302" @update:modelValue="handleChange" /></FormField>
          </Field>
          <Field name="cnae.secondary" v-slot="{ value, handleChange }">
            <FormField label="CNAEs secundários" :error="errors['cnae.secondary']" class="col-span-2"><TagsInput :modelValue="value ?? []" placeholder="digite e Enter" @update:modelValue="handleChange" /></FormField>
          </Field>
        </section>

        <section class="card space-y-4">
          <h2 class="card-title !mb-0">Atividade e perfil de operação</h2>
          <Field name="activity" v-slot="{ value, handleChange }">
            <FormField label="Atividades" :error="errors.activity">
              <div class="flex gap-4">
                <label v-for="a in activities" :key="a" class="inline-flex items-center gap-2 text-sm"><Checkbox :modelValue="value ?? []" :value="a" @update:modelValue="handleChange" /> {{ activityLabels[a] }}</label>
              </div>
              <Tag v-if="editing.fieldOrigins.activity === 'inferred'" severity="info" value="inferido" class="mt-1" />
            </FormField>
          </Field>
          <div class="grid grid-cols-4 gap-3">
            <Field v-for="f in ['icms_taxpayer', 'ipi_taxpayer', 'iss_taxpayer', 'sells_to_final_consumer', 'uses_nfce', 'exports', 'imports']" :key="f" :name="f" type="checkbox" :value="true" :unchecked-value="false" v-slot="{ value, handleChange }">
              <label class="inline-flex items-center gap-2 text-sm">
                <Checkbox :modelValue="value" binary @update:modelValue="handleChange" />
                {{ { icms_taxpayer: 'Contribuinte de ICMS', ipi_taxpayer: 'Contribuinte de IPI', iss_taxpayer: 'Contribuinte de ISS', sells_to_final_consumer: 'Vende a consumidor final', uses_nfce: 'Emite NFC-e', exports: 'Exporta', imports: 'Importa' }[f] }}
                <Tag v-if="editing.fieldOrigins[f] === 'inferred'" severity="info" value="inferido" />
              </label>
            </Field>
          </div>
        </section>

        <section class="card grid grid-cols-2 gap-4">
          <h2 class="col-span-2 card-title !mb-0">PIS/COFINS e IBS/CBS</h2>
          <Field name="pis_cofins.regime" v-slot="{ value, handleChange }">
            <FormField label="Regime de PIS/COFINS" :error="errors['pis_cofins.regime']"><Select :modelValue="value" :options="pisRegimes" optionValue="value" optionLabel="label" class="w-full" placeholder="Selecione" @update:modelValue="handleChange" /></FormField>
          </Field>
          <Field name="ibs_cbs.regime" v-slot="{ value, handleChange }">
            <FormField label="Regime de IBS/CBS" :error="errors['ibs_cbs.regime']"><Select :modelValue="value" :options="ibsRegimes" optionValue="value" optionLabel="label" class="w-full" @update:modelValue="handleChange" /></FormField>
          </Field>
        </section>

        <section class="card space-y-3">
          <div class="flex items-center gap-3"><h2 class="card-title !mb-0">Substituição tributária</h2>
            <Field name="st.source" v-slot="{ value, handleChange }"><Select :modelValue="value" :options="[{ value: 'catalog', label: 'Pela tabela da UF (catálogo)' }, { value: 'manual', label: 'Somente exceções manuais' }]" optionValue="value" optionLabel="label" class="text-xs" @update:modelValue="handleChange" /></Field>
          </div>
          <FieldArray name="st.overrides" v-slot="{ fields, push, remove }">
            <div v-for="(entry, idx) in fields" :key="entry.key" class="grid grid-cols-[1fr_120px_2fr_140px_140px_auto] gap-2 items-end">
              <Field :name="`st.overrides[${idx}].ncm`" v-slot="{ value, handleChange }"><FormField label="NCM" :error="errors[`st.overrides[${idx}].ncm`]"><InputText :modelValue="value" placeholder="2202* ou 22021000" @update:modelValue="handleChange" /></FormField></Field>
              <Field :name="`st.overrides[${idx}].applies`" v-slot="{ value, handleChange }"><FormField label="Tem ST?" :error="errors[`st.overrides[${idx}].applies`]"><Select :modelValue="value" :options="[{ value: true, label: 'Sim' }, { value: false, label: 'Não' }]" optionValue="value" optionLabel="label" class="w-full" @update:modelValue="handleChange" /></FormField></Field>
              <Field :name="`st.overrides[${idx}].legal_basis`" v-slot="{ value, handleChange }"><FormField label="Base legal" :error="errors[`st.overrides[${idx}].legal_basis`]"><InputText :modelValue="value" @update:modelValue="handleChange" /></FormField></Field>
              <Field :name="`st.overrides[${idx}].effective_from`" v-slot="{ value, handleChange }"><FormField label="De" :error="errors[`st.overrides[${idx}].effective_from`]"><InputText :modelValue="value" type="date" @update:modelValue="handleChange" /></FormField></Field>
              <Field :name="`st.overrides[${idx}].effective_until`" v-slot="{ value, handleChange }"><FormField label="Até" :error="errors[`st.overrides[${idx}].effective_until`]"><InputText :modelValue="value ?? ''" type="date" @update:modelValue="v => handleChange(v || null)" /></FormField></Field>
              <Button type="button" label="Remover" size="small" severity="danger" @click="remove(idx)" />
            </div>
            <Button type="button" label="Adicionar exceção de ST" size="small" severity="secondary" @click="push({ ncm: '', applies: true, legal_basis: '', effective_from: values.effective_from, effective_until: null })" />
          </FieldArray>
        </section>

        <section class="card space-y-3">
          <h2 class="card-title !mb-0">Benefícios fiscais e regimes especiais</h2>
          <FieldArray name="benefits" v-slot="{ fields, push, remove }">
            <div v-for="(entry, idx) in fields" :key="entry.key" class="rounded-md border border-surface p-3 grid grid-cols-[160px_100px_1fr_1fr_140px_140px_auto] gap-2 items-end">
              <Field :name="`benefits[${idx}].kind`" v-slot="{ value, handleChange }"><FormField label="Tipo" :error="errors[`benefits[${idx}].kind`]"><Select :modelValue="value" :options="benefitKinds" optionValue="value" optionLabel="label" class="w-full" @update:modelValue="handleChange" /></FormField></Field>
              <Field :name="`benefits[${idx}].pct`" v-slot="{ value, handleChange }"><FormField label="%" :error="errors[`benefits[${idx}].pct`]"><InputText :modelValue="value ?? ''" placeholder="33.33" @update:modelValue="v => handleChange(v || undefined)" /></FormField></Field>
              <Field :name="`benefits[${idx}].applies_to.ncm`" v-slot="{ value, handleChange }"><FormField label="NCMs" :error="errors[`benefits[${idx}].applies_to.ncm`]"><TagsInput :modelValue="value ?? []" @update:modelValue="handleChange" /></FormField></Field>
              <Field :name="`benefits[${idx}].applies_to.cfop`" v-slot="{ value, handleChange }"><FormField label="CFOPs" :error="errors[`benefits[${idx}].applies_to.cfop`]"><TagsInput :modelValue="value ?? []" @update:modelValue="handleChange" /></FormField></Field>
              <Field :name="`benefits[${idx}].effective_from`" v-slot="{ value, handleChange }"><FormField label="De" :error="errors[`benefits[${idx}].effective_from`]"><InputText :modelValue="value" type="date" @update:modelValue="handleChange" /></FormField></Field>
              <Field :name="`benefits[${idx}].effective_until`" v-slot="{ value, handleChange }"><FormField label="Até" :error="errors[`benefits[${idx}].effective_until`]"><InputText :modelValue="value ?? ''" type="date" @update:modelValue="v => handleChange(v || null)" /></FormField></Field>
              <Button type="button" label="Remover" size="small" severity="danger" @click="remove(idx)" />
              <Field :name="`benefits[${idx}].legal_basis`" v-slot="{ value, handleChange }"><FormField label="Base legal" :error="errors[`benefits[${idx}].legal_basis`]" class="col-span-7"><InputText :modelValue="value" placeholder="Decreto, artigo, regime especial nº…" @update:modelValue="handleChange" /></FormField></Field>
            </div>
            <Button type="button" label="Adicionar benefício" size="small" severity="secondary" @click="push({ kind: 'reduced_base', applies_to: { ncm: [], cfop: [] }, legal_basis: '', effective_from: values.effective_from, effective_until: null })" />
          </FieldArray>
        </section>

        <Message v-if="Object.keys(errors).length" severity="warn">Corrija os {{ Object.keys(errors).length }} campo(s) destacado(s).</Message>
        <div class="flex gap-2">
          <Button type="submit" label="Salvar rascunho" :loading="isSubmitting || save.isPending" />
          <Button type="button" label="Cancelar" severity="secondary" @click="editing = null" />
        </div>

        <Dialog v-model:visible="inferDialog" modal header="Proposta de cenário a partir das notas" class="!max-w-3xl">
          <div v-if="proposal" class="space-y-3 text-sm">
            <p class="text-slate-600">{{ proposal.sample.documents }} documentos e {{ proposal.sample.items }} itens emitidos desde {{ proposal.sample.since }}.</p>
            <p v-if="proposal.message" class="text-amber-700">{{ proposal.message }}</p>
            <table class="w-full text-xs">
              <thead class="text-left text-slate-500 uppercase"><tr><th class="py-1">Campo</th><th>Valor proposto</th><th>Confiança</th><th>Evidência</th></tr></thead>
              <tbody><tr v-for="(f, k) in proposal.fields" :key="k" class="border-t border-slate-100"><td class="py-1 font-mono">{{ k }}</td><td class="font-mono">{{ fmt(f.value) }}</td><td><Tag :severity="confidenceSeverity(f.confidence)" :value="Math.round(f.confidence * 100) + '%'" /></td><td class="text-slate-600">{{ f.evidence }}</td></tr></tbody>
            </table>
          </div>
          <template #footer><Button label="Fechar" severity="secondary" @click="inferDialog = false" /><Button label="Aplicar ao formulário" :disabled="!proposal || !Object.keys(proposal.fields).length" @click="applyProposal(setValues)" /></template>
        </Dialog>
      </div>
    </Form>
  </div>
</template>
