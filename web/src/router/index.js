import { createRouter, createWebHistory } from 'vue-router'
import { useSession } from '../stores/session'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/login', component: () => import('../views/LoginView.vue'), meta: { public: true } },
    { path: '/', redirect: '/runs' },
    { path: '/runs', component: () => import('../views/RunsView.vue') },
    { path: '/runs/:id', component: () => import('../views/RunDetailView.vue'), props: true },
    { path: '/upload', component: () => import('../views/UploadView.vue') },
    { path: '/clients', component: () => import('../views/ClientsView.vue') },
    { path: '/clients/:id/scenario', component: () => import('../views/ScenarioView.vue'), props: true },
    { path: '/security', component: () => import('../views/SecurityView.vue') },
    { path: '/users', component: () => import('../views/UsersView.vue'), meta: { role: 'firm_admin' } },
    { path: '/overrides', component: () => import('../views/OverridesView.vue'), meta: { role: 'firm_admin' } },
    { path: '/admin/rules', component: () => import('../views/admin/RulesView.vue'), meta: { role: 'platform_admin' } },
    { path: '/admin/rules/:id', component: () => import('../views/admin/RuleEditorView.vue'), props: true, meta: { role: 'platform_admin' } },
    { path: '/admin/tables', component: () => import('../views/admin/TablesView.vue'), meta: { role: 'platform_admin' } },
    { path: '/admin/tables/:id', component: () => import('../views/admin/TableDetailView.vue'), props: true, meta: { role: 'platform_admin' } },
  ],
})

router.beforeEach((to) => {
  const session = useSession()
  if (to.meta.public) return session.authenticated ? '/' : true
  if (!session.authenticated) return { path: '/login', query: { redirect: to.fullPath } }
  if (to.meta.role === 'firm_admin' && !session.isFirmAdmin) return '/'
  if (to.meta.role === 'platform_admin' && !session.isPlatformAdmin) return '/'
  return true
})

export default router
