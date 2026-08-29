import { createApp } from 'vue'
import { createPinia } from 'pinia'
import PrimeVue from 'primevue/config'
import ToastService from 'primevue/toastservice'
import { VueQueryPlugin, QueryClient } from '@tanstack/vue-query'
import App from './App.vue'
import router from './router'
import preset from './primevue/preset'
import './style.css'

const queryClient = new QueryClient({ defaultOptions: { queries: { retry: 1, refetchOnWindowFocus: false } } })

createApp(App)
  .use(createPinia())
  .use(router)
  .use(PrimeVue, { unstyled: true, pt: preset, ptOptions: { mergeProps: true }, locale: { emptyMessage: 'Nenhum resultado', emptyFilterMessage: 'Nenhum resultado' } })
  .use(ToastService)
  .use(VueQueryPlugin, { queryClient })
  .mount('#app')
