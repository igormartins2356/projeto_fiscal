module Audit
  # Divide o período do run em intervalos dentro dos quais nenhuma vigência muda (regra, sobreposição de
  # regra, versão/linha de tabela, sobreposição de linha, cenário). Sem isso, um documento de 02/08 seria
  # avaliado com a regra que só passa a valer em 03/08 — ARQUITETURA §3.4: a data de referência é a do
  # fato gerador (dhEmi), não o fim do período.
  class TemporalPartition
    Interval = Struct.new(:from, :to, keyword_init: true) do
      def cover?(date) = date && date >= from && date <= to
    end

    def self.call(client:, period_start:, period_end:) = new(client:, period_start:, period_end:).call

    def initialize(client:, period_start:, period_end:)
      @client = client
      @from = period_start
      @to = period_end
    end

    def call
      starts = [@from] + cuts
      starts.each_with_index.map { |s, i| Interval.new(from: s, to: starts[i + 1] ? starts[i + 1] - 1 : @to) }
    end

    private

    # Datas em que alguma vigência começa ou termina DENTRO do período (a do primeiro dia não corta nada).
    def cuts
      dates = []
      collect(dates, Rules::Rule.active.where(source_type: "platform")
                       .or(Rules::Rule.active.where(source_type: "firm", source_id: @client.firm_id)))
      collect(dates, Rules::RuleOverride.where(source_type: "firm", source_id: @client.firm_id)
                       .or(Rules::RuleOverride.where(source_type: "client", source_id: @client.id)))
      collect(dates, Catalog::ReferenceVersion.published)
      # só linhas de versão publicada e vigente dentro do período: rascunho e versão superada não mudam
      # resultado nenhum, mas cada corte extra custa um Resolver + um Lookup
      collect(dates, Catalog::ReferenceRow.where(reference_version_id: published_versions_in_period))
      collect(dates, Catalog::ReferenceRowOverride.where(source_type: "firm", source_id: @client.firm_id)
                       .or(Catalog::ReferenceRowOverride.where(source_type: "client", source_id: @client.id)))
      collect(dates, Scenario::TaxScenario.published.where(client_id: @client.id))
      dates.uniq.sort
    end

    def published_versions_in_period
      Catalog::ReferenceVersion.published
        .where("effective_from <= ? AND (effective_until IS NULL OR effective_until >= ?)", @to, @from).select(:id)
    end

    def collect(dates, scope)
      dates.concat(scope.where(effective_from: (@from + 1)..@to).distinct.pluck(:effective_from))
      # fim de vigência em X: o corte é no dia seguinte, primeiro dia em que a regra/linha já não vale
      dates.concat(scope.where(effective_until: @from..(@to - 1)).distinct.pluck(:effective_until).map { |d| d + 1 })
    end
  end
end
