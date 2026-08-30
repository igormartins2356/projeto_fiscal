import axios from 'axios'

const BASE = `${import.meta.env.VITE_API_URL ?? 'http://localhost:3000'}/api/v1`
export const api = axios.create({ baseURL: BASE })

// ---- tokens (localStorage) ----
const KEY = 'fiscal.session'
export function loadSession() { try { return JSON.parse(localStorage.getItem(KEY)) } catch { return null } }
export function saveSession(s) { try { s ? localStorage.setItem(KEY, JSON.stringify(s)) : localStorage.removeItem(KEY) } catch {} }

let clientId = null
export function setClientId(id) { clientId = id }

api.interceptors.request.use((config) => {
  const s = loadSession()
  if (s?.access_token) config.headers.Authorization = `Bearer ${s.access_token}`
  if (clientId) config.headers['X-Client-Id'] = String(clientId)
  return config
})

// 401 → tenta refresh (uma vez, com fila para requisições concorrentes) → repete; falhando, limpa sessão.
let refreshing = null
export const onSessionLost = { handler: null }
api.interceptors.response.use(undefined, async (error) => {
  const { config, response } = error
  if (response?.status !== 401 || config._retried || config.url.startsWith('/auth/')) throw error
  const s = loadSession()
  if (!s?.refresh_token) throw error
  try {
    refreshing ??= axios.post(`${BASE}/auth/refresh`, { refresh_token: s.refresh_token }).then(r => r.data).finally(() => { refreshing = null })
    const fresh = await refreshing
    saveSession(fresh)
    config._retried = true
    return api(config)
  } catch (e) {
    saveSession(null)
    onSessionLost.handler?.()
    throw e
  }
})

export const auth = {
  login: (email, password) => api.post('/auth/login', { email, password }).then(r => r.data),
  mfa: (mfa_token, code) => api.post('/auth/mfa', { mfa_token, code }).then(r => r.data),
  logout: (refresh_token) => api.delete('/auth/logout', { data: { refresh_token } }),
  me: () => api.get('/auth/me').then(r => r.data),
  otpSetup: () => api.post('/auth/otp/setup').then(r => r.data),
  otpEnable: (code) => api.post('/auth/otp/enable', { code }).then(r => r.data),
  otpDisable: (password, code) => api.delete('/auth/otp', { data: { password, code } }).then(r => r.data),
  changePassword: (current_password, password) => api.post('/users/change_password', { current_password, password }),
}
export const users = {
  list: () => api.get('/users').then(r => r.data),
  create: (u) => api.post('/users', u).then(r => r.data),
  update: (id, u) => api.patch(`/users/${id}`, u).then(r => r.data),
  deactivate: (id) => api.delete(`/users/${id}`),
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

export function errorMessage(e) { return e?.response?.data?.error ?? e?.message ?? 'erro inesperado' }

export const clientsApi = {
  list: (params = {}) => api.get('/clients', { params }).then(r => r.data),
  get: (id) => api.get(`/clients/${id}`).then(r => r.data),
  create: (data) => api.post('/clients', data).then(r => r.data),
  update: (id, data) => api.patch(`/clients/${id}`, data).then(r => r.data),
}
export const scenarios = {
  list: (clientId) => api.get(`/clients/${clientId}/tax_scenarios`).then(r => r.data),
  create: (clientId, data) => api.post(`/clients/${clientId}/tax_scenarios`, data).then(r => r.data),
  update: (clientId, id, data) => api.patch(`/clients/${clientId}/tax_scenarios/${id}`, data).then(r => r.data),
  publish: (clientId, id) => api.post(`/clients/${clientId}/tax_scenarios/${id}/publish`).then(r => r.data),
  destroy: (clientId, id) => api.delete(`/clients/${clientId}/tax_scenarios/${id}`),
  infer: (clientId, months = 6) => api.post(`/clients/${clientId}/tax_scenarios/infer`, { months }).then(r => r.data),
}

// ---- admin ----
export const adminRules = {
  list: (params) => api.get('/admin/rules', { params }).then(r => r.data),
  get: (id) => api.get(`/admin/rules/${id}`).then(r => r.data),
  create: (data) => api.post('/admin/rules', data).then(r => r.data),
  update: (id, data) => api.patch(`/admin/rules/${id}`, data).then(r => r.data),
  validate: (id) => api.post(`/admin/rules/${id}/validate`).then(r => r.data),
  transition: (id, to) => api.post(`/admin/rules/${id}/transition`, { to }).then(r => r.data),
  stats: (id) => api.get(`/admin/rules/${id}/stats`).then(r => r.data),
  createCase: (id, data) => api.post(`/admin/rules/${id}/test_cases`, data).then(r => r.data),
  updateCase: (id, cid, data) => api.patch(`/admin/rules/${id}/test_cases/${cid}`, data).then(r => r.data),
  deleteCase: (id, cid) => api.delete(`/admin/rules/${id}/test_cases/${cid}`),
  runCase: (id, cid) => api.post(`/admin/rules/${id}/test_cases/${cid}/run`).then(r => r.data),
  runAll: (id) => api.post(`/admin/rules/${id}/test_cases/run_all`).then(r => r.data),
}
export const adminTables = {
  list: () => api.get('/admin/reference_tables').then(r => r.data),
  get: (id) => api.get(`/admin/reference_tables/${id}`).then(r => r.data),
  create: (data) => api.post('/admin/reference_tables', data).then(r => r.data),
  update: (id, data) => api.patch(`/admin/reference_tables/${id}`, data).then(r => r.data),
  sync: (id, file) => { const f = new FormData(); if (file) f.append('file', file); return api.post(`/admin/reference_tables/${id}/sync`, f).then(r => r.data) },
  version: (tid, vid) => api.get(`/admin/reference_tables/${tid}/versions/${vid}`).then(r => r.data),
  createVersion: (tid, data) => api.post(`/admin/reference_tables/${tid}/versions`, data).then(r => r.data),
  updateVersion: (tid, vid, data) => api.patch(`/admin/reference_tables/${tid}/versions/${vid}`, data).then(r => r.data),
  rows: (tid, vid, params) => api.get(`/admin/reference_tables/${tid}/versions/${vid}/rows`, { params }).then(r => r.data),
  import: (tid, vid, file, mode, legal_basis) => { const f = new FormData(); f.append('file', file); f.append('mode', mode); if (legal_basis) f.append('legal_basis', legal_basis); return api.post(`/admin/reference_tables/${tid}/versions/${vid}/import`, f).then(r => r.data) },
  publish: (tid, vid) => api.post(`/admin/reference_tables/${tid}/versions/${vid}/publish`).then(r => r.data),
  retire: (tid, vid) => api.post(`/admin/reference_tables/${tid}/versions/${vid}/retire`).then(r => r.data),
  diff: (tid, vid) => api.get(`/admin/reference_tables/${tid}/versions/${vid}/diff`).then(r => r.data),
}
export const overrides = {
  tables: () => api.get('/reference_tables').then(r => r.data),
  rules: (params) => api.get('/rule_overrides', { params }).then(r => r.data),
  createRule: (data) => api.post('/rule_overrides', data).then(r => r.data),
  deleteRule: (id) => api.delete(`/rule_overrides/${id}`),
  rows: (params) => api.get('/reference_row_overrides', { params }).then(r => r.data),
  createRow: (data) => api.post('/reference_row_overrides', data).then(r => r.data),
  deleteRow: (id) => api.delete(`/reference_row_overrides/${id}`),
}
