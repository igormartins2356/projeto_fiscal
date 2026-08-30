<script>
export default { name: 'AppFooter', data() { return { year: new Date().getFullYear() } } }
</script>

<template>
  <footer class="layout-footer">
    <span>Validador Fiscal © {{ year }}</span>
    <span>Auditoria fiscal a partir do XML · nunca emite documentos</span>
  </footer>
</template>
