namespace :ingestion do
  desc "Rederiva o canônico dos documentos (após publicar tabela do Catalog): rake 'ingestion:rederive[client_id,period]'"
  task :rederive, [:client_id, :period] => :environment do |_t, args|
    scope = Ingestion::Document.fiscal
    scope = scope.where(client_id: args[:client_id]) if args[:client_id].present?
    scope = scope.where(period: args[:period]) if args[:period].present?
    puts "rederivando #{scope.count} documento(s)…"
    puts "#{Ingestion::Rederive.call(scope)} documento(s) rederivado(s)"
  end
end
