import { mount } from '@vue/test-utils'
import { describe, expect, it } from 'vitest'
import JsonEditor from '../JsonEditor.vue'

const stubs = {
  Textarea: { props: ['modelValue'], emits: ['update:modelValue'], template: '<textarea :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)"></textarea>' },
  Button: true,
}
const montar = (modelValue) => mount(JsonEditor, { props: { modelValue }, global: { stubs } })

describe('JsonEditor', () => {
  it('não reformata o texto quando o pai devolve o mesmo valor em outro objeto (cursor pulava)', async () => {
    const w = montar({ a: 1 })
    const digitado = '{ "a": 1, "b": 2 }'
    await w.find('textarea').setValue(digitado)
    expect(w.emitted('update:modelValue').at(-1)[0]).toEqual({ a: 1, b: 2 })
    await w.setProps({ modelValue: { a: 1, b: 2 } }) // objeto novo, mesmo conteúdo
    expect(w.vm.text).toBe(digitado)
  })

  it('sincroniza quando o valor recebido é semanticamente diferente', async () => {
    const w = montar({ a: 1 })
    await w.setProps({ modelValue: { a: 9 } })
    expect(JSON.parse(w.vm.text)).toEqual({ a: 9 })
  })

  it('mantém o texto inválido enquanto o JSON está incompleto e avisa o pai', async () => {
    const w = montar({ a: 1 })
    await w.find('textarea').setValue('{ "a": ')
    expect(w.vm.text).toBe('{ "a": ')
    expect(w.emitted('error').at(-1)[0]).toBeTruthy()
  })
})
