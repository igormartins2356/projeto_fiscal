import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { debounce } from '../debounce'

describe('debounce', () => {
  beforeEach(() => vi.useFakeTimers())
  afterEach(() => vi.useRealTimers())

  it('dispara uma única vez, com os últimos argumentos, após a pausa', () => {
    const fn = vi.fn()
    const d = debounce(fn, 300)
    d('a'); d('ab'); d('abc')
    vi.advanceTimersByTime(299)
    expect(fn).not.toHaveBeenCalled()
    vi.advanceTimersByTime(1)
    expect(fn.mock.calls).toEqual([['abc']])
  })

  it('cancel impede a chamada pendente', () => {
    const fn = vi.fn()
    const d = debounce(fn, 300)
    d('x')
    d.cancel()
    vi.advanceTimersByTime(1000)
    expect(fn).not.toHaveBeenCalled()
  })
})
