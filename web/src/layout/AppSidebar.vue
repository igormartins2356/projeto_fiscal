<script>
import { mapState } from 'pinia'
import { useSession } from '../stores/session'
import menu from './menu'

export default {
  name: 'AppSidebar',
  computed: {
    ...mapState(useSession, ['isFirmAdmin', 'isPlatformAdmin']),
    groups() {
      return menu.filter(g => this.allowed(g.role)).map(g => ({ ...g, items: g.items.filter(i => this.allowed(i.role)) })).filter(g => g.items.length)
    },
  },
  methods: {
    allowed(role) { return !role || (role === 'firm_admin' && this.isFirmAdmin) || (role === 'platform_admin' && this.isPlatformAdmin) },
    isActive(to) { return this.$route.path === to || this.$route.path.startsWith(to + '/') },
  },
}
</script>

<template>
  <aside class="layout-sidebar">
    <div class="sidebar-header">
      <RouterLink to="/" class="flex items-center gap-2 text-primary">
        <span class="inline-flex items-center justify-center w-9 h-9 rounded-lg bg-primary text-white"><i class="pi pi-verified text-lg"></i></span>
        <span class="text-lg font-semibold text-color tracking-tight">Validador Fiscal</span>
      </RouterLink>
    </div>
    <div class="layout-menu-container">
      <ul class="layout-menu">
        <li v-for="g in groups" :key="g.label" class="layout-root-menuitem">
          <div class="layout-menuitem-root-text">{{ g.label }}</div>
          <ul>
            <li v-for="i in g.items" :key="i.to">
              <RouterLink :to="i.to" :class="{ 'active-route': isActive(i.to) }">
                <i :class="['layout-menuitem-icon', i.icon]"></i><span class="layout-menuitem-text">{{ i.label }}</span>
              </RouterLink>
            </li>
          </ul>
        </li>
      </ul>
    </div>
  </aside>
</template>
