<script>
import PageHeader from '../components/PageHeader.vue'
import { reactive, ref } from 'vue'
import { useMutation, useQuery } from '@tanstack/vue-query'
import Button from 'primevue/button'
import Message from 'primevue/message'
import { uploads } from '../api/client'

export default {
  name: 'UploadView',
  components: { PageHeader, Button, Message },
  setup() {
    const batchId = ref(null)
    const upload = reactive(useMutation({ mutationFn: uploads.create }))
    // Polling do lote enquanto está processando (refetchInterval reativo ao estado)
    const batchQuery = reactive(useQuery({
      queryKey: ['upload', batchId],
      queryFn: () => uploads.get(batchId.value),
      enabled: () => !!batchId.value,
      refetchInterval: (q) => (['done', 'failed'].includes(q.state.data?.state) ? false : 1500),
    }))
    return { upload, batchQuery, batchId }
  },
  data() { return { file: null } },
  computed: {
    batch() { return this.batchQuery.data },
    finished() { return ['done', 'failed'].includes(this.batch?.state) },
  },
  methods: {
    onFile(e) { this.file = e.target.files?.[0] ?? null },
    async send() {
      const batch = await this.upload.mutateAsync(this.file)
      this.batchId = batch.id
    },
  },
}
</script>

<template>
  <div class="max-w-2xl">
    <PageHeader title="Enviar XMLs" subtitle="Um XML de NF-e/NFC-e/evento ou um ZIP com vários. Notas de homologação e de outros CNPJs são ignoradas." />
    <div class="card space-y-4">
    <input type="file" accept=".xml,.zip" class="block text-sm file:mr-3 file:rounded-md file:border file:border-slate-300 file:bg-white file:px-3 file:py-1.5 file:text-sm" @change="onFile" />
    <Button label="Enviar" icon="pi pi-upload" :disabled="!file" :loading="upload.isPending" @click="send" />
    <Message v-if="upload.isError" severity="error">Falha no envio: {{ upload.error?.message }}</Message>
    <div v-if="batch" class="rounded-md border border-surface p-4 text-sm space-y-1 bg-surface-50">
      <div>Lote #{{ batch.id }} — <span class="font-medium">{{ batch.state }}</span></div>
      <div>{{ batch.files_parsed }} / {{ batch.files_total }} processados, {{ batch.files_failed }} com erro</div>
      <ul v-if="batch.errors_log?.length" class="text-red-700 list-disc pl-5"><li v-for="e in batch.errors_log" :key="e.file">{{ e.file }}: {{ e.error }}</li></ul>
      <RouterLink v-if="finished" to="/runs" class="text-primary font-medium">Ir para auditorias →</RouterLink>
    </div>
    </div>
  </div>
</template>
