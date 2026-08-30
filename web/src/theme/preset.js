// Tema do produto: reproduz os tokens visuais do template Apollo (PrimeTek) — Lara, primária indigo, superfícies slate,
// Poppins 14px, raio 6px. Os valores são os do tema "theme-light/indigo" do Apollo; a implementação é nossa (o template é licenciado).
import Lara from '@primeuix/themes/lara'
import { definePreset } from '@primeuix/themes'

export const tokens = {
  primary: { 50: '#f7f7fe', 100: '#dadafc', 200: '#bcbdf9', 300: '#9ea0f6', 400: '#8183f4', 500: '#6366f1', 600: '#5457cd', 700: '#4547a9', 800: '#363885', 900: '#282960', 950: '#1b1c40' },
  surface: { 0: '#ffffff', 50: '#f8fafc', 100: '#f1f5f9', 200: '#e2e8f0', 300: '#cbd5e1', 400: '#94a3b8', 500: '#64748b', 600: '#475569', 700: '#334155', 800: '#1e293b', 900: '#0f172a', 950: '#020617' },
  ground: '#eff3f8', border: '#dfe7ef', hover: '#f6f9fc', text: '#1e293b', textSecondary: '#64748b',
  cardShadow: '0px 4px 30px rgba(221, 224, 255, 0.54)', sidebarShadow: '0px 4px 50px #d9ddfc', radius: '6px', cardRadius: '12px',
}

export default definePreset(Lara, {
  primitive: { borderRadius: { none: '0', xs: '2px', sm: '4px', md: '6px', lg: '8px', xl: '12px' } },
  semantic: {
    primary: tokens.primary,
    focusRing: { width: '0', style: 'none', color: 'transparent', offset: '0', shadow: '0 0 0 0.2rem #c7d2fe' },
    colorScheme: {
      light: {
        surface: tokens.surface,
        primary: { color: '{primary.500}', contrastColor: '#ffffff', hoverColor: '{primary.600}', activeColor: '{primary.700}' },
        highlight: { background: '#eef2ff', focusBackground: '#e0e7ff', color: '#4338ca', focusColor: '#312e81' },
        formField: { background: '{surface.0}', borderColor: '{surface.300}', hoverBorderColor: '{primary.color}', focusBorderColor: '{primary.color}', color: '{surface.800}', placeholderColor: '{surface.500}', shadow: 'none' },
        text: { color: tokens.text, hoverColor: '{surface.900}', mutedColor: tokens.textSecondary, hoverMutedColor: '{surface.600}' },
        content: { background: '{surface.0}', hoverBackground: tokens.hover, borderColor: '{surface.200}', color: tokens.text, hoverColor: '{surface.900}' },
        overlay: { select: { background: '{surface.0}', borderColor: '{surface.200}', color: tokens.text }, popover: { background: '{surface.0}', borderColor: '{surface.200}', color: tokens.text }, modal: { background: '{surface.0}', borderColor: '{surface.200}', color: tokens.text } },
      },
    },
  },
  components: {
    datatable: { colorScheme: { light: { headerCell: { background: '#f8fafc', color: '#334155', borderColor: '#e2e8f0' }, row: { background: '{surface.0}', hoverBackground: tokens.hover, color: tokens.text }, bodyCell: { borderColor: '#e2e8f0' } } }, headerCell: { padding: '1rem' }, bodyCell: { padding: '0.85rem 1rem' } },
    card: { root: { borderRadius: tokens.cardRadius, shadow: tokens.cardShadow, background: '{surface.0}' }, body: { padding: '2rem' } },
    dialog: { root: { borderRadius: tokens.radius, shadow: '0 1px 3px rgba(0,0,0,.3)' }, header: { padding: '1.5rem' }, content: { padding: '0 1.5rem 2rem 1.5rem' } },
    tag: { root: { fontSize: '0.75rem', fontWeight: '700', padding: '0.25rem 0.4rem', borderRadius: tokens.radius } },
    button: { root: { borderRadius: tokens.radius, sm: { fontSize: '0.875rem', paddingX: '1.09375rem', paddingY: '0.65625rem' } } },
    inputtext: { root: { borderRadius: tokens.radius, sm: { fontSize: '0.875rem', paddingX: '0.65625rem', paddingY: '0.65625rem' } } },
    select: { root: { borderRadius: tokens.radius } },
    checkbox: { root: { borderRadius: tokens.radius, width: '22px', height: '22px', borderColor: '#cbd5e1' } },
    menu: { root: { borderRadius: tokens.radius } },
    tabs: { tab: { fontWeight: '700', padding: '1.25rem' } },
  },
})
