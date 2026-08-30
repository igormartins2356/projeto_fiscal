// Menu lateral (grupos com rótulo uppercase, como no Apollo). `role` limita a exibição.
export default [
  { label: 'Auditoria', items: [
    { label: 'Auditorias', icon: 'pi pi-check-square', to: '/runs' },
    { label: 'Enviar XMLs', icon: 'pi pi-upload', to: '/upload' },
  ] },
  { label: 'Cadastros', items: [
    { label: 'Clientes', icon: 'pi pi-building', to: '/clients' },
    { label: 'Usuários', icon: 'pi pi-users', to: '/users', role: 'firm_admin' },
    { label: 'Sobreposições', icon: 'pi pi-sliders-h', to: '/overrides', role: 'firm_admin' },
  ] },
  { label: 'Plataforma', role: 'platform_admin', items: [
    { label: 'Regras', icon: 'pi pi-list-check', to: '/admin/rules' },
    { label: 'Tabelas de referência', icon: 'pi pi-table', to: '/admin/tables' },
  ] },
  { label: 'Conta', items: [
    { label: 'Segurança', icon: 'pi pi-shield', to: '/security' },
  ] },
]
