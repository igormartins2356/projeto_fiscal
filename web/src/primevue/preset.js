// Preset Tailwind para o PrimeVue em modo unstyled (pass-through global).
// Cada componente usado no app tem suas seções aqui; ver https://primevue.dev/theming/unstyled/
const focus = 'focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-500/40'
const input = `w-full rounded-md border border-slate-300 bg-white px-3 py-1.5 text-sm text-slate-800 placeholder:text-slate-400 ${focus} disabled:opacity-50`

export default {
  button: {
    root: ({ props }) => ({
      class: [
        'inline-flex items-center justify-center gap-2 rounded-md text-sm font-medium transition-colors cursor-pointer', focus,
        'disabled:opacity-50 disabled:cursor-not-allowed',
        props.size === 'small' ? 'px-2.5 py-1 text-xs' : 'px-4 py-2',
        props.severity === 'secondary' ? 'border border-slate-300 bg-white text-slate-700 hover:bg-slate-50'
          : props.severity === 'danger' ? 'bg-red-600 text-white hover:bg-red-700'
          : props.text ? 'text-blue-700 hover:bg-blue-50'
          : 'bg-blue-700 text-white hover:bg-blue-800',
      ],
    }),
    label: { class: 'leading-none' },
    icon: { class: 'shrink-0' },
    loadingIcon: { class: 'animate-spin' },
  },
  inputtext: { root: { class: input } },
  select: {
    root: ({ props }) => ({ class: [`relative inline-flex items-center rounded-md border border-slate-300 bg-white text-sm cursor-pointer ${focus}`, props.disabled && 'opacity-50'] }),
    label: { class: 'flex-1 px-3 py-1.5 truncate text-slate-800' },
    dropdown: { class: 'flex items-center px-2 text-slate-500' },
    overlay: { class: 'mt-1 rounded-md border border-slate-200 bg-white shadow-lg z-50' },
    listContainer: { class: 'max-h-64 overflow-auto' },
    list: { class: 'py-1' },
    option: ({ context }) => ({ class: ['px-3 py-1.5 text-sm cursor-pointer', context.focused && 'bg-slate-100', context.selected && 'text-blue-700 font-medium'] }),
    emptyMessage: { class: 'px-3 py-2 text-sm text-slate-500' },
  },
  tag: {
    root: ({ props }) => ({
      class: ['inline-flex items-center rounded px-2 py-0.5 text-xs font-medium',
        { error: 'bg-red-100 text-red-800', danger: 'bg-red-100 text-red-800', warn: 'bg-amber-100 text-amber-800', warning: 'bg-amber-100 text-amber-800',
          info: 'bg-sky-100 text-sky-800', success: 'bg-emerald-100 text-emerald-800', secondary: 'bg-slate-100 text-slate-700' }[props.severity] ?? 'bg-slate-100 text-slate-700'],
    }),
  },
  message: {
    root: ({ props }) => ({ class: ['rounded-md border px-3 py-2 text-sm', { error: 'border-red-200 bg-red-50 text-red-800', warn: 'border-amber-200 bg-amber-50 text-amber-800', success: 'border-emerald-200 bg-emerald-50 text-emerald-800' }[props.severity] ?? 'border-sky-200 bg-sky-50 text-sky-800'] }),
    content: { class: 'flex items-center gap-2' },
  },
  datatable: {
    root: { class: 'rounded-md border border-slate-200 bg-white overflow-hidden' },
    tableContainer: { class: 'overflow-x-auto' },
    table: { class: 'w-full text-sm' },
    thead: { class: 'bg-slate-100 text-left text-xs uppercase text-slate-500' },
    headerCell: { class: 'px-3 py-2 font-medium' },
    bodyRow: ({ context }) => ({ class: ['border-t border-slate-100 hover:bg-slate-50', context.selected && 'bg-blue-50'] }),
    bodyCell: { class: 'px-3 py-2 align-top' },
    rowExpansion: { class: 'bg-slate-50' },
    rowExpansionCell: { class: 'px-3 py-3 bg-slate-50' },
    emptyMessageCell: { class: 'px-3 py-6 text-center text-slate-500' },
    loadingIcon: { class: 'animate-spin' },
  },
  paginator: {
    root: { class: 'flex items-center justify-between gap-2 px-3 py-2 border-t border-slate-200 bg-white text-sm' },
    content: { class: 'flex items-center gap-1' },
    first: { class: 'size-8 rounded hover:bg-slate-100 inline-flex items-center justify-center cursor-pointer disabled:opacity-40' },
    prev: { class: 'size-8 rounded hover:bg-slate-100 inline-flex items-center justify-center cursor-pointer disabled:opacity-40' },
    next: { class: 'size-8 rounded hover:bg-slate-100 inline-flex items-center justify-center cursor-pointer disabled:opacity-40' },
    last: { class: 'size-8 rounded hover:bg-slate-100 inline-flex items-center justify-center cursor-pointer disabled:opacity-40' },
    pages: { class: 'flex items-center gap-1' },
    page: ({ context }) => ({ class: ['size-8 rounded inline-flex items-center justify-center cursor-pointer', context.active ? 'bg-blue-700 text-white' : 'hover:bg-slate-100'] }),
    current: { class: 'text-slate-500' },
    pcRowPerPageDropdown: { root: { class: 'inline-flex items-center rounded-md border border-slate-300 bg-white text-sm cursor-pointer' }, label: { class: 'px-2 py-1' }, dropdown: { class: 'px-1 text-slate-500' },
      overlay: { class: 'mt-1 rounded-md border border-slate-200 bg-white shadow-lg z-50' }, list: { class: 'py-1' }, option: ({ context }) => ({ class: ['px-3 py-1 text-sm cursor-pointer', context.focused && 'bg-slate-100'] }) },
  },
  column: {
    headerCell: { class: 'px-3 py-2 font-medium' },
    columnHeaderContent: { class: 'flex items-center gap-1' },
    sort: { class: 'text-slate-400' },
    filter: { class: 'flex items-center gap-1' },
    filterElementContainer: { class: 'flex-1' },
    rowToggleButton: { class: 'size-7 rounded hover:bg-slate-200 inline-flex items-center justify-center cursor-pointer' },
  },
  toast: {
    root: { class: 'fixed top-4 right-4 w-96 z-[1000] space-y-2' },
    message: ({ props }) => ({ class: ['rounded-md border p-3 shadow-lg text-sm bg-white', { error: 'border-red-300', warn: 'border-amber-300', success: 'border-emerald-300' }[props.message.severity] ?? 'border-sky-300'] }),
    messageContent: { class: 'flex items-start gap-2' },
    messageText: { class: 'flex-1' },
    summary: { class: 'font-medium' },
    detail: { class: 'text-slate-600 mt-0.5' },
    closeButton: { class: 'size-6 rounded hover:bg-slate-100 inline-flex items-center justify-center cursor-pointer text-slate-500' },
  },
  dialog: {
    mask: { class: 'fixed inset-0 bg-black/40 flex items-center justify-center z-[900]' },
    root: { class: 'rounded-lg bg-white shadow-xl w-full max-w-lg' },
    header: { class: 'flex items-center justify-between px-5 py-3 border-b border-slate-200' },
    title: { class: 'font-semibold' },
    pcCloseButton: { root: { class: 'size-7 rounded hover:bg-slate-100 inline-flex items-center justify-center cursor-pointer text-slate-500' } },
    content: { class: 'px-5 py-4 text-sm' },
    footer: { class: 'flex justify-end gap-2 px-5 py-3 border-t border-slate-200' },
  },
  textarea: { root: { class: input + ' min-h-24' } },
  progressspinner: { root: { class: 'inline-block size-6' }, spin: { class: 'animate-spin text-blue-700' }, circle: { class: 'stroke-current' } },
}
