import { describe, expect, it, vi } from 'vitest'
import { exportCsv } from '../export'

// exportCsv monta o Blob e chama download(); capturamos o conteúdo pelo Blob passado a URL.createObjectURL.
async function csvOf(rows, columns) {
  let blob = null
  const createObjectURL = vi.fn((b) => { blob = b; return 'blob:x' })
  const original = { createObjectURL: URL.createObjectURL, revokeObjectURL: URL.revokeObjectURL, click: HTMLAnchorElement.prototype.click }
  URL.createObjectURL = createObjectURL
  URL.revokeObjectURL = vi.fn()
  HTMLAnchorElement.prototype.click = vi.fn()
  try { exportCsv(rows, columns, 'x.csv') } finally { Object.assign(URL, { createObjectURL: original.createObjectURL, revokeObjectURL: original.revokeObjectURL }); HTMLAnchorElement.prototype.click = original.click }
  return await blob.text()
}

describe('exportCsv', () => {
  it('neutraliza fórmula vinda de texto de terceiros (xProd, infCpl)', async () => {
    const csv = await csvOf([{ message: '=HYPERLINK("http://x","clique")' }], [{ field: 'message', header: 'Mensagem' }])
    expect(csv).toContain('"\'=HYPERLINK')
  })

  it('mantém texto comum e escapa aspas', async () => {
    const csv = await csvOf([{ message: 'CFOP 5102 "venda"' }], [{ field: 'message', header: 'Mensagem' }])
    expect(csv).toContain('"CFOP 5102 ""venda"""')
  })
})
