import { createApp } from 'vue'
import { createPinia } from 'pinia'
import PrimeVue from 'primevue/config'
import preset from './theme/preset'
import ToastService from 'primevue/toastservice'
import ConfirmationService from 'primevue/confirmationservice'
import { VueQueryPlugin, QueryClient } from '@tanstack/vue-query'
import App from './App.vue'
import router from './router'
import ptBR from './locale/pt-BR'
import { useSession } from './stores/session'
import 'primeicons/primeicons.css'
import './style.css'


const queryClient = new QueryClient({ defaultOptions: { queries: { retry: 1, refetchOnWindowFocus: false } } })
const pinia = createPinia()

const app = createApp(App)
  .use(pinia)
  .use(router)
  .use(PrimeVue, {
    theme: { preset, options: { darkModeSelector: false, cssLayer: { name: 'primevue', order: 'theme, base, primevue' } } },
    locale: ptBR,
  })
  .use(ToastService)
  .use(ConfirmationService)
  .use(VueQueryPlugin, { queryClient })

useSession(pinia).bindSessionLost(router, queryClient)
app.mount('#app')
