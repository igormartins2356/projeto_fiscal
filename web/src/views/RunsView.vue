<script>
import { reactive } from 'vue'
import { useQuery, useMutation, useQueryClient } from '@tanstack/vue-query'
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import { auditRuns } from '../api/client'

function iso(d) { return d.toISOString().slice(0, 10) }

export default {
  name: 'RunsView',
  components: { Button, InputText, DataTable, Column },
  setup() {
    const queryClient = useQueryClient()
    const runs = reactive(useQuery({ queryKey: ['audit_runs'], queryFn: auditRuns.list, refetchInterval: (q) => (q.state.data?.some(r => ['queued', 'running'].includes(r.state)) ? 2000 : false) }))
    const create = reactive(useMutation({ mutationFn: auditRuns.create, onSuccess: () => queryClient.invalidateQueries({ queryKey: ['audit_runs'] }) }))
    return { runs, create }
  },
  data() {
    const today = new Date()
    return {
      periodStart: iso(new Date(today.getFullYear(), today.getMonth() - 1, 1)),
      periodEnd: iso(new Date(today.getFullYear(), today.getMonth(), 0)),
    }
  },
  methods: {
    submit() { this.create.mutate({ period_start: this.periodStart, period_end: this.periodEnd }) },
    fmtDate(v) { return new Date(v).toLocaleString('pt-BR') },
    open(e) { this.$router.push(`/runs/${e.data.id}`) },
  },
}
</script>

<template>
  <div class="space-y-6">
    <div class="flex items-end gap-3">
      <label class="text-xs text-slate-500">Início<InputText v-model="periodStart" type="date" class="mt-1" /></label>
      <label class="text-xs text-slate-500">Fim<InputText v-model="periodEnd" type="date" class="mt-1" /></label>
      <Button label="Nova auditoria" :loading="create.isPending" @click="submit" />
      <Button label="Atualizar" severity="secondary" @click="runs.refetch()" />
    </div>
    <DataTable :value="runs.data ?? []" :loading="runs.isPending" dataKey="id" selectionMode="single" @row-click="open">
      <Column field="id" header="#" />
      <Column header="Período"><template #body="{ data }">{{ data.period_start }} → {{ data.period_end }}</template></Column>
      <Column field="state" header="Estado" />
      <Column field="documents_count" header="Documentos" />
      <Column field="findings_count" header="Apontamentos" />
      <Column header="Criada"><template #body="{ data }"><span class="text-slate-500">{{ fmtDate(data.created_at) }}</span></template></Column>
      <template #empty>Nenhuma auditoria ainda.</template>
    </DataTable>
  </div>
</template>
