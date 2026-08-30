<script>
import { mapState } from 'pinia'
import AppLayout from './layout/AppLayout.vue'
import Toast from 'primevue/toast'
import { useSession } from './stores/session'

export default {
  name: 'App',
  components: { AppLayout, Toast },
  computed: { ...mapState(useSession, ['authenticated']) },
}
</script>

<template>
  <AppLayout v-if="authenticated" />
  <template v-else><Toast position="top-right" /><RouterView /></template>
</template>
