require "rails_helper"

RSpec.describe Ingestion::Sped::Parser do
  before { seed_all! }
  let(:client) { Accounts::Client.find_by!(cnpj: "12345678000190") }

  def key_for(n) = "3526071234567800019055001000" + n.to_s.rjust(6, "0") + "1000" + n.to_s.rjust(6, "0")

  def c100(n) = "|C100|1|0|CLI001|55|00|1|#{n}|#{key_for(n)}|10072026|10072026|1000,00|2|0,00|0,00|1000,00|9|0,00|0,00|0,00|1000,00|180,00|0,00|0,00|0,00|6,50|30,00|0,00|0,00|"
  C170 = "|C170|1|A1|Produto A|2,0000|UN|1000,00|0,00|0|000|5102|001|1000,00|18,00|180,00|0,00|0,00|0,00|0|50||1000,00|0,00|0,00|01|1000,00|0,65||0,00|6,50|01|1000,00|3,00||0,00|30,00|CTA||0,00|"

  def efd(count = 20, header: "|0000|020|0|01072026|31072026|CLIENTE EXEMPLO|12345678000190||SP|123456789012|3550308|||A|0|")
    body = (1..count).flat_map { |n| [c100(n), C170] }.join("\n")
    "#{header}\n|0001|0|\n|C001|0|\n#{body}\n|9999|#{count * 2 + 4}|\n"
  end

  it "grava os registros em blocos, e não uma query por linha" do
    inserts = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| inserts += 1 if payload[:sql].start_with?("INSERT") && payload[:name] != "SCHEMA" }
    file = described_class.call(efd, client:, storage_ref: "spec/sped.txt")
    ActiveSupport::Notifications.unsubscribe(sub)
    expect(file.state).to eq("done")
    expect(file.records_count).to eq(44)
    expect(inserts).to be <= 2
    c170 = file.records.find_by(record_type: "C170", line_number: 5)
    expect(c170.parent_id).to eq(file.records.find_by(record_type: "C100", line_number: 4).id)
  end

  it "marca o arquivo como failed quando a persistência falha, em vez de deixá-lo em parsing" do
    allow(Ingestion::FiscalRecord).to receive(:insert_all!).and_raise(ActiveRecord::RecordNotUnique.new("simulado"))
    file = described_class.call(efd(2), client:, storage_ref: "spec/sped_falha.txt")
    expect(file.state).to eq("failed")
    expect(file.errors_log.first["error"]).to include("RecordNotUnique")
  end

  it "recusa arquivo sem DT_INI válido em vez de datar o leiaute em Date.current" do
    expect { described_class.call(efd(1, header: "|0000|020|0|||CLIENTE EXEMPLO|12345678000190||SP|123456789012|3550308|||A|0|"), client:, storage_ref: "spec/sem_data.txt") }
      .to raise_error(described_class::InvalidFile, /DT_INI/)
  end

  it "é idempotente: reimportar o mesmo arquivo devolve o registro já processado" do
    file = described_class.call(efd(2), client:, storage_ref: "spec/sped.txt")
    again = described_class.call(efd(2), client:, storage_ref: "spec/sped.txt")
    expect(again.id).to eq(file.id)
    expect(Ingestion::FiscalRecord.where(fiscal_file_id: file.id).count).to eq(file.records_count)
  end
end
