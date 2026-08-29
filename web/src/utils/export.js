import ExcelJS from 'exceljs'

function download(blob, filename) {
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url; a.download = filename; a.click()
  URL.revokeObjectURL(url)
}

// columns: [{ field, header, value?: (row) => any }]
export async function exportXlsx(rows, columns, filename) {
  const wb = new ExcelJS.Workbook()
  const ws = wb.addWorksheet('Dados')
  ws.columns = columns.map(c => ({ header: c.header, key: c.field, width: Math.max(12, c.header.length + 4) }))
  rows.forEach(r => ws.addRow(Object.fromEntries(columns.map(c => [c.field, c.value ? c.value(r) : r[c.field]]))))
  ws.getRow(1).font = { bold: true }
  download(new Blob([await wb.xlsx.writeBuffer()], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }), filename)
}

export function exportCsv(rows, columns, filename) {
  const esc = v => `"${String(v ?? '').replace(/"/g, '""')}"`
  const lines = [columns.map(c => esc(c.header)).join(';'), ...rows.map(r => columns.map(c => esc(c.value ? c.value(r) : r[c.field])).join(';'))]
  download(new Blob(['﻿' + lines.join('\n')], { type: 'text/csv;charset=utf-8' }), filename)
}
