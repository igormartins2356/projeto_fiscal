module Rules
  # Dicionário resumido do canônico (CANONICO.md) para validação estática de caminhos.
  # Prefixos conhecidos: caminho que começa por um deles é aceito. Desconhecido gera *aviso*, não erro
  # (o canônico evolui; avisos aparecem no painel para o curador conferir).
  # Só entra aqui o que o parser/derivação REALMENTE produz: campo marcado [P] no CANONICO.md (previsto e
  # ainda não implementado) fica de fora de propósito, para a regra que o usar sair com aviso.
  module CanonicalSchema
    ROOTS = {
      "item" => %w[item document],
      "doc" => %w[item document],
      "scenario" => %w[item document cross_document period scenario],
      "period" => %w[cross_document period scenario],
      "fiscal_file" => %w[period],
      "stats" => %w[scenario],
      "params" => %w[item document cross_document period scenario]
    }.freeze

    DOC = %w[
      schema_version kind model access_key layout_version layout_groups xml_hash environment monitored_cnpj role reference_date period
      issuance.issued_at issuance.dispatched_at issuance.series issuance.number issuance.numeric_code issuance.emission_type issuance.purpose issuance.app_version
      operation.nature_text operation.direction_declared operation.direction operation.scope operation.taxable_event_city_code operation.final_consumer operation.presence
      operation.intermediary operation.nature operation.cfops operation.mixed_cfop operation.origin_uf operation.destination_uf
      references references[].kind references[].access_key references[].resolved references[].document_id
      status.state status.cancelled_at protocol.number protocol.received_at protocol.status_code protocol.digest
      issuer.cnpj issuer.cpf issuer.legal_name issuer.trade_name issuer.ie issuer.ie_st issuer.im issuer.cnae issuer.crt issuer.tax_regime issuer.uf issuer.address
      recipient.cnpj recipient.cpf recipient.foreign_id recipient.legal_name recipient.ie_indicator recipient.ie recipient.isuf recipient.im recipient.email recipient.uf recipient.person_type recipient.icms_taxpayer recipient.address
      transport.freight_mode transport.carrier transport.volumes billing payments payments[].timing payments[].method payments[].amount change_amount
      totals.icms_base totals.icms totals.icms_exempted totals.fcp totals.icms_st_base totals.icms_st totals.fcp_st totals.fcp_st_withheld totals.fcp_uf_dest_base totals.fcp_uf_dest totals.icms_uf_dest totals.icms_uf_sender
      totals.products totals.freight totals.insurance totals.discount totals.other_expenses totals.ii totals.ipi totals.ipi_returned totals.pis totals.cofins totals.total totals.approx_taxes
      totals.withholdings totals.ibs_cbs totals.items_sum totals.totals_mismatch additional_info technical_responsible ibs_cbs items
    ].freeze

    ITEM = %w[
      number product.code product.gtin product.taxable_gtin product.no_gtin product.description product.ncm product.nve product.cest product.scale_indicator product.manufacturer_cnpj
      product.benefit_code product.ex_tipi product.cfop product.commercial_unit product.commercial_quantity product.commercial_unit_price product.taxable_unit product.taxable_quantity
      product.taxable_unit_price product.gross_amount product.freight product.insurance product.discount product.other_expenses product.included_in_total product.purchase_order
      product.purchase_order_item product.fci product.used_movable_good product.batches product.import_declarations product.export_detail additional_info approx_taxes
      net_amount cfop_nature cfop_group cfop_scope cfop_known cfop_st_role cfop_requires_reference cfop_own_production ncm_valid ncm_chapter ncm_generic expected_cest st_applicable_by_catalog is_service has_difal
      icms.group icms.origin icms.origin_category icms.cst icms.csosn icms.situation_code icms.situation_field icms.base_mode icms.base_reduction_pct icms.base_amount icms.rate icms.amount
      icms.fcp icms.exemption icms.deferral icms.simples_credit icms.expected_base_amount icms.expected_base_reliable icms.expected_amount icms.taxation_kind icms.highlights_icms
      icms_st.expected_base_amount icms_st.expected_amount icms_st.base_mode icms_st.mva_pct icms_st.base_reduction_pct icms_st.base_amount icms_st.rate icms_st.amount icms_st.fcp icms_st.withheld icms_st.exemption icms_st.highlights_st icms_st.has_withheld_st
      icms_uf_dest.base_amount icms_uf_dest.fcp icms_uf_dest.destination_internal_rate icms_uf_dest.interstate_rate icms_uf_dest.sharing_pct icms_uf_dest.destination_amount icms_uf_dest.sender_amount icms_uf_dest.expected_destination_amount
      ipi.cst ipi.cst_direction ipi.taxation_kind ipi.taxed ipi.base_amount ipi.rate ipi.amount ipi.quantity ipi.unit_amount ipi.expected_amount ipi.framing_code ii
      pis.group pis.cst pis.base_amount pis.rate pis.amount pis.base_quantity pis.unit_rate pis.expected_amount pis.taxation_kind pis.cst_direction pis_st
      cofins.group cofins.cst cofins.base_amount cofins.rate cofins.amount cofins.base_quantity cofins.unit_rate cofins.expected_amount cofins.taxation_kind cofins.cst_direction cofins_st issqn
      ibs_cbs.present ibs_cbs.cst ibs_cbs.class_code ibs_cbs.base_amount ibs_cbs.ibs_uf ibs_cbs.ibs_city ibs_cbs.ibs ibs_cbs.cbs ibs_cbs.regular_taxation ibs_cbs.presumed_credit
      ibs_cbs.single_phase ibs_cbs.schedule_rates ibs_cbs.ibs.amount ibs_cbs.cbs.rate ibs_cbs.cbs.amount ibs_cbs.cbs.effective_rate ibs_cbs.cbs.expected_amount
      ibs_cbs.schedule_rates.cbs ibs_cbs.schedule_rates.ibs_uf ibs_cbs.schedule_rates.ibs_city is.cst is.class_code is.base_amount is.rate is.amount
    ].freeze

    SCENARIO = %w[tax_regime simples_annex uf city_code icms_taxpayer ipi_taxpayer iss_taxpayer activity cnae sells_to_final_consumer uses_nfce exports imports st st.source st.overrides benefits pis_cofins pis_cofins.regime ibs_cbs ibs_cbs.regime].freeze

    # Retorna :ok, :unknown_root, :unknown_path
    def self.check(path, scope:, extra_vars: [])
      root, rest = path.to_s.split(".", 2)
      root = root.sub(/\[\d+\]\z/, "")
      return :ok if extra_vars.include?(root)
      scopes = ROOTS[root] or return :unknown_root
      return :unknown_root unless scopes.include?(scope)
      return :ok if rest.nil?
      known = case root
              when "doc" then DOC
              when "item" then ITEM
              when "scenario" then SCENARIO
              else return :ok
              end
      norm = rest.gsub(/\[\d+\]/, "[]")
      known.any? { |k| norm == k || norm.start_with?("#{k}.") || norm.start_with?("#{k}[]") } ? :ok : :unknown_path
    end
  end
end
