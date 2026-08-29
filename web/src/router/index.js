import { createRouter, createWebHistory } from 'vue-router'

export default createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', redirect: '/runs' },
    { path: '/runs', component: () => import('../views/RunsView.vue') },
    { path: '/runs/:id', component: () => import('../views/RunDetailView.vue'), props: true },
    { path: '/upload', component: () => import('../views/UploadView.vue') },
  ],
})
