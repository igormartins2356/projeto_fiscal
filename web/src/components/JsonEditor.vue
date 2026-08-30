<script>
// Editor de JSON simples (Textarea PrimeVue) com validação de sintaxe e formatação.
import Textarea from 'primevue/textarea'
import Button from 'primevue/button'

export default {
  name: 'JsonEditor',
  components: { Textarea, Button },
  props: { modelValue: { type: [Object, Array], default: () => ({}) }, rows: { type: Number, default: 18 } },
  emits: ['update:modelValue', 'error'],
  data() { return { text: JSON.stringify(this.modelValue, null, 2), error: null } },
  watch: { modelValue(v) { const t = JSON.stringify(v, null, 2); if (t !== this.text && !this.error) this.text = t } },
  methods: {
    onInput(t) {
      this.text = t
      try { const v = JSON.parse(t); this.error = null; this.$emit('update:modelValue', v); this.$emit('error', null) }
      catch (e) { this.error = e.message; this.$emit('error', e.message) }
    },
    format() { if (!this.error) this.text = JSON.stringify(JSON.parse(this.text), null, 2) },
  },
}
</script>

<template>
  <div class="space-y-1">
    <Textarea :modelValue="text" :rows="rows" class="w-full font-mono text-xs" spellcheck="false" @update:modelValue="onInput" />
    <div class="flex items-center gap-2 text-xs"><span v-if="error" class="text-red-700">JSON inválido: {{ error }}</span><Button label="Formatar" text size="small" :disabled="!!error" @click="format" /></div>
  </div>
</template>
