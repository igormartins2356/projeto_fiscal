<script>
import PageHeader from '../components/PageHeader.vue'
import { computed, reactive, ref } from 'vue'
import { useQuery, useMutation, useQueryClient } from '@tanstack/vue-query'
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import { auditRuns, errorMessage } from '../api/client'
import { useSession } from '../stores/session'
import { fmtDate, fmtDateTime, toIso } from '../utils/date'

export default {
  name: 'RunsView',
  components: { PageHeader, Button, InputText, DataTable, Column },
  setup() {
    const queryClient = useQueryClient()
    const session = useSession()
    const page = ref(1)
    const perPage = ref(25)
    // clientId na chave: sem ele o cache devolve as auditorias do cliente anterior ao trocar de cliente na topbar.
    const runs = reactive(useQuery({
      queryKey: ['audit_runs', computed(() => session.clientId), page, perPage],
      queryFn: () => auditRuns.list({ page: page.value, per_page: perPage.value }),
      placeholderData: (prev) => prev,
      refetchInterval: (q) => (q.state.data?.data?.some(r => ['queued', 'running'].includes(r.state)) ? 2000 : false),
    }))
    const create = reactive(useMutation({ mutationFn: auditRuns.create, onSuccess: () => queryClient.invalidateQueries({ queryKey: ['audit_runs'] }) }))
    return { runs, create, page, perPage }
  },
  data() {
    const today = new Date()
    return {
      periodStart: toIso(new Date(today.getFullYear(), today.getMonth() - 1, 1)),
      periodEnd: toIso(new Date(today.getFullYear(), today.getMonth(), 0)),
    }
  },
  computed: {
    rows() { return this.runs.data?.data ?? [] },
    total() { return this.runs.data?.total ?? 0 },
    first() { return (this.page - 1) * this.perPage },
  },
  methods: {
    async submit() {
      try { await this.create.mutateAsync({ period_start: this.periodStart, period_end: this.periodEnd }); this.page = 1 }
      catch (e) { this.$toast.add({ severity: 'error', summary: 'Falha ao criar a auditoria', detail: errorMessage(e), life: 4000 }) }
    },
    onPage(e) { this.page = e.page + 1; this.perPage = e.rows },
    fmtDate, fmtDateTime,
    open(e) { this.$router.push(`/runs/${e.data.id}`) },
  },
}
</script>

<template>
  <div>
    <PageHeader title="Auditorias" subtitle="Cada auditoria avalia os documentos do período com as regras vigentes na data de emissão.">
      <template #actions>
        <span class="field"><label class="text-secondary text-xs" for="period-start">Início</label><InputText id="period-start" v-model="periodStart" type="date" size="small" /></span>
        <span class="field"><label class="text-secondary text-xs" for="period-end">Fim</label><InputText id="period-end" v-model="periodEnd" type="date" size="small" /></span>
        <Button label="Nova auditoria" icon="pi pi-play" :loading="create.isPending" @click="submit" />
        <Button icon="pi pi-refresh" severity="secondary" outlined aria-label="Atualizar" @click="runs.refetch()" />
      </template>
    </PageHeader>
    <div class="card">
    <DataTable :value="rows" :loading="runs.isPending" lazy paginator :first="first" :rows="perPage" :totalRecords="total" :rowsPerPageOptions="[25, 50, 100]"
               dataKey="id" selectionMode="single" @page="onPage" @row-click="open">
      <Column field="id" header="#" />
      <Column header="Período"><template #body="{ data }">{{ fmtDate(data.period_start) }} → {{ fmtDate(data.period_end) }}</template></Column>
      <Column field="state" header="Estado" />
      <Column field="documents_count" header="Documentos" />
      <Column field="findings_count" header="Apontamentos" />
      <Column header="Criada"><template #body="{ data }"><span class="text-slate-500">{{ fmtDateTime(data.created_at) }}</span></template></Column>
      <template #empty><div class="empty-state"><i class="pi pi-check-square"></i>Nenhuma auditoria ainda. Envie XMLs e crie a primeira.</div></template>
    </DataTable>
    </div>
  </div>
</template>
