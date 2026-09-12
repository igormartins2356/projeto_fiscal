// Adia a chamada até `wait` ms sem novas invocações (filtro de texto → uma requisição por pausa de digitação, não por tecla).
export function debounce(fn, wait = 300) {
  let timer = null
  const debounced = (...args) => {
    clearTimeout(timer)
    timer = setTimeout(() => { timer = null; fn(...args) }, wait)
  }
  debounced.cancel = () => { clearTimeout(timer); timer = null }
  return debounced
}
