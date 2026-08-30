<script>
import { reactive } from 'vue'
import { useQuery } from '@tanstack/vue-query'
import { mapState, mapActions } from 'pinia'
import Select from 'primevue/select'
import Button from 'primevue/button'
import Menu from 'primevue/menu'
import Avatar from 'primevue/avatar'
import { clients } from '../api/client'
import { useSession } from '../stores/session'
import menu from './menu'

export default {
  name: 'AppTopbar',
  components: { Select, Button, Menu, Avatar },
  emits: ['toggle-menu'],
  setup() {
    const session = useSession()
    const clientsQuery = reactive(useQuery({ queryKey: ['clients'], queryFn: clients.list, enabled: () => session.authenticated }))
    return { clientsQuery }
  },
  computed: {
    ...mapState(useSession, ['clientId', 'user']),
    clients() { return this.clientsQuery.data ?? [] },
    breadcrumb() {
      const path = this.$route.path
      for (const g of menu) for (const i of g.items) if (path === i.to || path.startsWith(i.to + '/')) {
        const crumbs = [g.label, i.label]
        if (path !== i.to) crumbs.push(this.$route.meta.crumb ?? 'Detalhe')
        return crumbs
      }
      return ['Início']
    },
    initials() { return (this.user?.name ?? '?').split(' ').map(s => s[0]).slice(0, 2).join('').toUpperCase() },
    profileItems() {
      return [
        { label: this.user?.email, disabled: true },
        { separator: true },
        { label: 'Segurança', icon: 'pi pi-shield', command: () => this.$router.push('/security') },
        { label: 'Sair', icon: 'pi pi-sign-out', command: () => this.doLogout() },
      ]
    },
  },
  watch: { clients(list) { if (list.length && !this.clientId) this.restore(list) } },
  methods: {
    ...mapActions(useSession, ['select', 'restore', 'logout']),
    onSelect(id) { this.select(id); if (!this.$route.path.startsWith('/runs')) this.$router.push('/runs') },
    async doLogout() { await this.logout(); this.$router.push('/login') },
  },
}
</script>

<template>
  <header class="layout-topbar">
    <div class="topbar-start">
      <button type="button" class="topbar-menubutton" aria-label="Menu" @click="$emit('toggle-menu')"><i class="pi pi-bars text-lg"></i></button>
      <nav class="layout-breadcrumb" aria-label="breadcrumb">
        <ol><template v-for="(c, i) in breadcrumb" :key="i"><li v-if="i > 0" class="pi pi-angle-right text-xs"></li><li>{{ c }}</li></template></ol>
      </nav>
    </div>
    <div class="topbar-end">
      <Select class="w-72" :modelValue="clientId" :options="clients" optionValue="id" optionLabel="legal_name" placeholder="Selecione o cliente" filter :loading="clientsQuery.isPending" @update:modelValue="onSelect">
        <template #value="{ value, placeholder }"><span v-if="value" class="flex items-center gap-2"><i class="pi pi-building text-secondary"></i>{{ clients.find(c => c.id === value)?.legal_name }}</span><span v-else>{{ placeholder }}</span></template>
        <template #option="{ option }"><div><div>{{ option.legal_name }}</div><div class="text-xs text-secondary mono">{{ option.cnpj }}</div></div></template>
      </Select>
      <Button type="button" text rounded class="ml-1" @click="$refs.profile.toggle($event)" aria-haspopup="true" aria-controls="profile_menu">
        <Avatar :label="initials" shape="circle" class="bg-primary text-white font-semibold" />
      </Button>
      <Menu ref="profile" id="profile_menu" :model="profileItems" popup />
    </div>
  </header>
</template>
