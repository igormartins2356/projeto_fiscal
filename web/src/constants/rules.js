// Ciclo de vida de regra (DSL_RULES.md §9) e severidade do Tag por estado.
export const RULE_STATES = ['draft', 'testing', 'shadow', 'published', 'retired']
export const RULE_SCOPES = ['item', 'document', 'cross_document', 'period', 'scenario']
export const RULE_SEVERITIES = ['error', 'warning', 'info']
export const STATE_SEVERITY = { draft: 'secondary', testing: 'info', shadow: 'warn', published: 'success', retired: 'danger' }
