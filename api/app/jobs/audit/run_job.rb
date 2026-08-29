module Audit
  class RunJob < ApplicationJob
    queue_as :audit
    def perform(run_id) = Audit::Runner.new(Audit::AuditRun.find(run_id)).call
  end
end
