<script>
import { reactive } from 'vue'
import { useQuery } from '@tanstack/vue-query'
import { mapState, mapActions } from 'pinia'
import Select from 'primevue/select'
import Toast from 'primevue/toast'
import { clients } from './api/client'
import { useSession } from './stores/session'

export default {
  name: 'App',
  components: { Select, Toast },
  // Único uso de setup(): registrar a query (exigência do Vue Query). Todo o resto é Options API.
  setup() {
    // reactive() desembrulha as refs do Vue Query para uso normal em Options API (this.clientsQuery.data)
    const clientsQuery = reactive(useQuery({ queryKey: ['clients'], queryFn: clients.list }))
    return { clientsQuery }
  },
  computed: {
    ...mapState(useSession, ['clientId']),
    clients() { return this.clientsQuery.data ?? [] },
  },
  watch: {
    clients(list) { if (list.length && !this.clientId) this.restore(list) },
  },
  methods: {
    ...mapActions(useSession, ['select', 'restore']),
    onSelect(id) { this.select(id); this.$router.push('/runs') },
  },
}
</script>

<template>
  <div class="min-h-screen">
    <Toast />
    <header class="bg-white border-b border-slate-200">
      <div class="max-w-6xl mx-auto px-4 h-14 flex items-center gap-6">
        <span class="font-semibold tracking-tight">Validador Fiscal</span>
        <nav class="flex gap-4 text-sm">
          <RouterLink to="/runs" class="hover:text-blue-700" active-class="text-blue-700 font-medium">Auditorias</RouterLink>
          <RouterLink to="/upload" class="hover:text-blue-700" active-class="text-blue-700 font-medium">Enviar XMLs</RouterLink>
        </nav>
        <Select class="ml-auto min-w-72" :modelValue="clientId" :options="clients" optionValue="id" optionLabel="legal_name"
                placeholder="Selecione o cliente" :loading="clientsQuery.isPending" @update:modelValue="onSelect">
          <template #option="{ option }">{{ option.legal_name }} <span class="text-slate-400">— {{ option.cnpj }}</span></template>
        </Select>
      </div>
    </header>
    <main class="max-w-6xl mx-auto px-4 py-6">
      <RouterView v-if="clientId" :key="clientId" />
      <p v-else class="text-slate-500">Nenhum cliente selecionado.</p>
    </main>
  </div>
</template>
