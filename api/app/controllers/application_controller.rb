class ApplicationController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods

  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "não encontrado" }, status: :not_found
  end
  rescue_from ActiveRecord::RecordInvalid do |e|
    render json: { error: e.record.errors.full_messages.join(", "), errors: e.record.errors.to_hash }, status: :unprocessable_entity
  end
  rescue_from ActionController::ParameterMissing do |e|
    render json: { error: "parâmetro obrigatório: #{e.param}" }, status: :bad_request
  end

  private

  def current_user
    return @current_user if defined?(@current_user)
    @current_user = authenticate_with_http_token do |token, _|
      payload = Auth::Tokens.decode(token, purpose: "access")
      user = Accounts::User.active.find_by(id: payload["sub"])
      # Token emitido antes da última troca de senha não vale mais (reset por administrador de conta comprometida).
      user if user && payload["pwd"].to_i == Auth::Tokens.password_stamp(user)
    rescue Auth::Tokens::Invalid
      nil
    end
  end

  def current_firm = current_user&.firm

  def authenticate!
    render json: { error: "não autenticado" }, status: :unauthorized unless current_user
  end

  def require_role!(*roles)
    return if current_user && (current_user.platform_admin? || roles.include?(current_user.role))
    render json: { error: "sem permissão" }, status: :forbidden
  end

  def audit!(action, subject: nil, **meta)
    Audit::AuditLog.record!(action, user: current_user, firm: current_firm, subject:, ip: request.remote_ip, **meta)
  end
end
