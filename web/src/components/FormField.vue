<script>
// Rótulo + mensagem de erro para um Field do vee-validate (padrão .field do design system).
export default {
  name: 'FormField',
  props: { label: { type: String, required: true }, error: { type: String, default: '' }, hint: { type: String, default: '' } },
}
</script>

<template>
  <label class="field">
    <span class="field-label">{{ label }}</span>
    <slot />
    <span v-if="error" class="field-error">{{ error }}</span>
    <span v-else-if="hint" class="field-hint">{{ hint }}</span>
  </label>
</template>
