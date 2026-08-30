<script>
// Lista de códigos (NCM, CFOP, CNAE) como chips. Enter, vírgula ou espaço adicionam; clique remove.
import InputText from 'primevue/inputtext'

export default {
  name: 'TagsInput',
  components: { InputText },
  props: { modelValue: { type: Array, default: () => [] }, placeholder: { type: String, default: '' } },
  emits: ['update:modelValue'],
  data() { return { draft: '' } },
  methods: {
    commit() {
      const parts = this.draft.split(/[\s,;]+/).map(s => s.trim()).filter(Boolean)
      if (parts.length) this.$emit('update:modelValue', [...new Set([...this.modelValue, ...parts])])
      this.draft = ''
    },
    remove(i) { this.$emit('update:modelValue', this.modelValue.filter((_, idx) => idx !== i)) },
    onKeydown(e) {
      if (['Enter', ',', ' '].includes(e.key)) { e.preventDefault(); this.commit() }
      if (e.key === 'Backspace' && !this.draft && this.modelValue.length) this.remove(this.modelValue.length - 1)
    },
  },
}
</script>

<template>
  <div class="flex flex-wrap items-center gap-1 rounded-md border border-slate-300 bg-white px-2 py-1 min-h-9">
    <button v-for="(t, i) in modelValue" :key="t" type="button" class="rounded bg-slate-100 px-2 py-0.5 text-xs font-mono hover:bg-red-100 cursor-pointer" :title="'remover ' + t" @click="remove(i)">{{ t }} ×</button>
    <input v-model="draft" class="flex-1 min-w-24 text-sm outline-none bg-transparent" :placeholder="placeholder" @keydown="onKeydown" @blur="commit" />
  </div>
</template>
