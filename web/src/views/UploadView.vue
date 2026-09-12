<script>
import { computed, reactive, ref } from 'vue'
import { useMutation, useQuery, useQueryClient } from '@tanstack/vue-query'
import Button from 'primevue/button'
import Message from 'primevue/message'
import DataTable from 'primevue/datatable'
import Column from 'primevue/column'
import Tag from 'primevue/tag'
import PageHeader from '../components/PageHeader.vue'
import { uploads, fiscalFiles, errorMessage } from '../api/client'
import { useSession } from '../stores/session'
import { fmtDate } from '../utils/date'

export default {
  name: 'UploadView',
  components: { Button, Message, DataTable, Column, Tag, PageHeader },
  setup() {
    const queryClient = useQueryClient()
    const session = useSession()
    const clientId = computed(() => session.clientId)
    const batchId = ref(null)
    const page = ref(1)
    const perPage = ref(25)
    // Enquanto a EFD é processada em segundo plano a listagem ainda não tem a linha nova: continuamos
    // pedindo por alguns ciclos em vez de um único setTimeout (que perdia o arquivo em máquina lenta).
    const pollUntil = ref(0)
    const upload = reactive(useMutation({ mutationFn: uploads.create }))
    const batchQuery = reactive(useQuery({
      queryKey: ['upload', batchId, clientId],
      queryFn: () => uploads.get(batchId.value),
      enabled: () => !!batchId.value,
      refetchInterval: (q) => (['done', 'failed'].includes(q.state.data?.state) ? false : 1500),
    }))
    const files = reactive(useQuery({
      queryKey: ['fiscal_files', clientId, page, perPage],
      queryFn: () => fiscalFiles.list({ page: page.value, per_page: perPage.value }),
      placeholderData: (prev) => prev,
      refetchInterval: (q) => (Date.now() < pollUntil.value || q.state.data?.data?.some(f => ['parsing', 'pending'].includes(f.state)) ? 2000 : false),
    }))
    const uploadSped = reactive(useMutation({
      mutationFn: fiscalFiles.create,
      onSuccess: () => { pollUntil.value = Date.now() + 20000; queryClient.invalidateQueries({ queryKey: ['fiscal_files'] }) },
    }))
    return { upload, batchQuery, batchId, files, uploadSped, page, perPage }
  },
  data() { return { file: null, spedFile: null } },
  computed: {
    batch() { return this.batchQuery.data },
    finished() { return ['done', 'failed'].includes(this.batch?.state) },
    uploadError() { return this.upload.isError ? errorMessage(this.upload.error) : '' },
    rows() { return this.files.data?.data ?? [] },
    total() { return this.files.data?.total ?? 0 },
    first() { return (this.page - 1) * this.perPage },
  },
  methods: {
    fmtDate,
    onFile(e) { this.file = e.target.files?.[0] ?? null },
    onPage(e) { this.page = e.page + 1; this.perPage = e.rows },
    async send() {
      // 422 de extensão/tamanho vem em pt-BR do backend; sem o catch a promessa rejeitada só aparecia no console.
      try { const batch = await this.upload.mutateAsync(this.file); this.batchId = batch.id }
      catch (e) { this.$toast.add({ severity: 'error', summary: 'Falha no envio', detail: errorMessage(e), life: 5000 }) }
    },
    async sendSped() {
      try { await this.uploadSped.mutateAsync(this.spedFile); this.spedFile = null; this.$toast.add({ severity: 'success', summary: 'EFD recebida', detail: 'Processando; o cross-check entra na próxima auditoria do período.', life: 4000 }) }
      catch (e) { this.$toast.add({ severity: 'error', summary: 'Falha no envio', detail: errorMessage(e), life: 5000 }) }
    },
    stateSev(s) { return { done: 'success', failed: 'danger', parsing: 'info', pending: 'secondary' }[s] ?? 'secondary' },
  },
}
</script>

<template>
  <div class="max-w-4xl">
    <PageHeader title="Enviar arquivos" subtitle="XMLs de NF-e/NFC-e (auditoria) e EFD ICMS/IPI (cross-check SPED × XML)." />

    <div class="card space-y-4">
      <h2 class="card-title">XMLs (NF-e / NFC-e / eventos)</h2>
      <p class="text-sm text-secondary">Um XML, ou um ZIP com vários — inclusive no formato de exportação do ERP (nota cancelada como zip com autorização + cancelamento). Notas de homologação e de outros CNPJs são ignoradas. Limite de 200 MB por envio.</p>
      <label class="block text-sm" for="xml-file">Arquivo XML ou ZIP</label>
      <input id="xml-file" type="file" accept=".xml,.zip" class="block text-sm" @change="onFile" />
      <Button label="Enviar XMLs" icon="pi pi-upload" :disabled="!file" :loading="upload.isPending" @click="send" />
      <Message v-if="uploadError" severity="error">Falha no envio: {{ uploadError }}</Message>
      <div v-if="batch" class="rounded-md border border-surface p-4 text-sm space-y-1 bg-surface-50">
        <div>Lote #{{ batch.id }} — <span class="font-medium">{{ batch.state }}</span></div>
        <div>{{ batch.files_parsed }} / {{ batch.files_total }} processados, {{ batch.files_failed }} com erro</div>
        <ul v-if="batch.errors_log?.length" class="text-red-700 list-disc pl-5"><li v-for="e in batch.errors_log" :key="e.file">{{ e.file }}: {{ e.error }}</li></ul>
        <RouterLink v-if="finished" to="/runs" class="text-primary font-medium">Ir para auditorias →</RouterLink>
      </div>
    </div>

    <div class="card space-y-4">
      <h2 class="card-title">EFD ICMS/IPI (SPED Fiscal)</h2>
      <p class="text-sm text-secondary">Arquivo .txt gerado pelo ERP (antes ou depois do PVA), até 300 MB. O cross-check confronta C100/C170/C190 com os XMLs do mesmo período e aponta a nota de origem de cada divergência.</p>
      <div class="flex items-center gap-3">
        <label class="sr-only" for="sped-file">Arquivo da EFD (.txt)</label>
        <input id="sped-file" type="file" accept=".txt,.TXT" class="block text-sm" @change="e => spedFile = e.target.files?.[0] ?? null" />
        <Button label="Enviar EFD" icon="pi pi-file-check" :disabled="!spedFile" :loading="uploadSped.isPending" @click="sendSped" />
      </div>
      <DataTable :value="rows" :loading="files.isPending" lazy paginator :first="first" :rows="perPage" :totalRecords="total" :rowsPerPageOptions="[25, 50, 100]" dataKey="id" size="small" @page="onPage">
        <Column header="Período"><template #body="{ data }">{{ fmtDate(data.period_start) }} → {{ fmtDate(data.period_end) }}</template></Column>
        <Column field="layout_version" header="Leiaute" class="w-20" />
        <Column field="purpose" header="Finalidade" class="w-28"><template #body="{ data }">{{ data.purpose === 'rectifying' ? 'retificadora' : 'original' }}</template></Column>
        <Column header="Registros" class="w-40"><template #body="{ data }">{{ data.records_count }} ({{ data.summary?.c100 ?? 0 }} C100, {{ data.summary?.linked_documents ?? 0 }} vinculados)</template></Column>
        <Column header="Estado" class="w-40"><template #body="{ data }"><Tag :severity="stateSev(data.state)" :value="data.state" /><span v-if="data.errors_count > 0" class="ml-2 text-xs text-amber-700">{{ data.errors_count }} aviso(s)</span></template></Column>
        <template #empty><div class="empty-state"><i class="pi pi-file-check"></i>Nenhuma EFD enviada para este cliente.</div></template>
      </DataTable>
    </div>
  </div>
</template>
