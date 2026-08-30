<script>
import { mapState } from 'pinia'
import ConfirmDialog from 'primevue/confirmdialog'
import Toast from 'primevue/toast'
import AppSidebar from './AppSidebar.vue'
import AppTopbar from './AppTopbar.vue'
import AppFooter from './AppFooter.vue'
import { useSession } from '../stores/session'

export default {
  name: 'AppLayout',
  components: { ConfirmDialog, Toast, AppSidebar, AppTopbar, AppFooter },
  data() { return { mobileActive: false } },
  computed: { ...mapState(useSession, ['clientId']) },
  watch: { $route() { this.mobileActive = false } },
}
</script>

<template>
  <div class="layout-container" :class="{ 'layout-mobile-active': mobileActive }">
    <Toast position="top-right" />
    <ConfirmDialog />
    <AppSidebar />
    <div v-if="mobileActive" class="layout-mask" @click="mobileActive = false"></div>
    <div class="layout-content-wrapper">
      <AppTopbar @toggle-menu="mobileActive = !mobileActive" />
      <main class="layout-content">
        <RouterView v-if="clientId || !['/runs', '/upload'].some(p => $route.path.startsWith(p))" :key="$route.path.startsWith('/clients') ? 'clients' : clientId" />
        <div v-else class="card"><div class="empty-state"><i class="pi pi-building"></i>Nenhum cliente cadastrado nesta firma. Cadastre um em <RouterLink to="/clients" class="text-primary font-medium">Clientes</RouterLink>.</div></div>
      </main>
      <AppFooter />
    </div>
  </div>
</template>
