<script>
// Cabeçalho padrão de página: título, subtítulo e ações à direita.
export default { name: 'PageHeader', props: { title: { type: String, required: true }, subtitle: { type: String, default: '' } } }
</script>

<template>
  <div class="page-header">
    <div><h1>{{ title }}</h1><p v-if="subtitle || $slots.subtitle" class="page-subtitle"><slot name="subtitle">{{ subtitle }}</slot></p></div>
    <div v-if="$slots.actions" class="flex items-center gap-2 flex-wrap"><slot name="actions" /></div>
  </div>
</template>
