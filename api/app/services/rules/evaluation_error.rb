module Rules
  # Regra mal escrita ou dado inesperado: nunca vira finding, vai para audit_run.evaluation_errors.
  class EvaluationError < StandardError; end
end
