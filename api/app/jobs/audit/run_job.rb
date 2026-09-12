module Audit
  class RunJob < ApplicationJob
    queue_as :audit
    # O run é caro (milhares de notas) e já registra o erro em `evaluation_errors` com state "failed":
    # as 25 retentativas padrão do Sidekiq só multiplicariam o trabalho. Duas repetições cobrem falha
    # transitória de banco/rede; o `delete_all` do Runner garante que a repetição não colida no índice único.
    retry_on StandardError, wait: :polynomially_longer, attempts: 3
    discard_on ActiveRecord::RecordNotFound # run apagado (exclusão do cliente): retentar não o traz de volta

    def perform(run_id) = Audit::Runner.new(Audit::AuditRun.find(run_id)).call
  end
end
