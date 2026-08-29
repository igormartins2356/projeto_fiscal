<script>
import Tag from 'primevue/tag'

const LABEL = { error: 'erro', warning: 'alerta', info: 'info' }

export default {
  name: 'SeverityTag',
  components: { Tag },
  props: { severity: { type: String, required: true } },
  computed: { label() { return LABEL[this.severity] ?? this.severity } },
}
</script>

<template>
  <Tag :severity="severity" :value="label" />
</template>
