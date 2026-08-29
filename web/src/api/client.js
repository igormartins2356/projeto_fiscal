import axios from 'axios'

export const api = axios.create({ baseURL: `${import.meta.env.VITE_API_URL ?? 'http://localhost:3000'}/api/v1` })

// MVP: cliente selecionado vai no header (auth JWT entra depois)
export function setClientId(id) {
  if (id) api.defaults.headers.common['X-Client-Id'] = String(id)
  else delete api.defaults.headers.common['X-Client-Id']
}

export const clients = { list: () => api.get('/clients').then(r => r.data) }
export const uploads = {
  create: (file) => { const f = new FormData(); f.append('file', file); return api.post('/uploads', f).then(r => r.data) },
  get: (id) => api.get(`/uploads/${id}`).then(r => r.data),
}
export const auditRuns = {
  list: () => api.get('/audit_runs').then(r => r.data),
  get: (id) => api.get(`/audit_runs/${id}`).then(r => r.data),
  create: (params) => api.post('/audit_runs', params).then(r => r.data),
  findings: (id, params = {}) => api.get(`/audit_runs/${id}/findings`, { params }).then(r => r.data),
}
export const findings = { update: (id, params) => api.patch(`/findings/${id}`, params).then(r => r.data) }
