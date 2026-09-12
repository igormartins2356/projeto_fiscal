module Api
  module V1
    module Auth
      class SessionsController < ApplicationController
        before_action :authenticate!, only: %i[me logout_all]

        # POST /auth/login → tokens ou desafio MFA
        def login
          email = params.require(:email).to_s.strip.downcase
          # Exigir a senha ANTES de olhar a conta: com o require dentro do `if`, faltar `password` dava 400 para
          # e-mail existente e 401 para inexistente — o status enumerava contas que a mensagem única escondia.
          password = params.require(:password)
          user = Accounts::User.active.find_by(email:)
          if user.nil? || user.locked? || !user.authenticate(password)
            # Mesma mensagem e mesmo custo de bcrypt em todos os casos: distinguir "bloqueada" de "inválida"
            # (ou responder mais rápido para e-mail inexistente) revela quais contas existem.
            # Conta bloqueada não chega a chamar `authenticate`: sem o dummy, o tempo de resposta separaria
            # "bloqueada" de "senha errada".
            Accounts::User.dummy_authenticate(password) if user.nil? || user.locked?
            user&.register_failed_attempt!
            Audit::AuditLog.record!("login_failed", user:, ip: request.remote_ip, email: params[:email].to_s.first(100), locked: user&.locked?)
            return render json: { error: "credenciais inválidas" }, status: :unauthorized
          end
          if user.otp_enabled
            render json: { mfa_required: true, mfa_token: ::Auth::Tokens.issue_mfa(user) }
          else
            issue_session(user)
          end
        end

        # POST /auth/mfa { mfa_token, code }
        def mfa
          payload = ::Auth::Tokens.decode(params.require(:mfa_token), purpose: "mfa")
          user = Accounts::User.active.find(payload["sub"])
          # Sem esta checagem o bloqueio da conta não vale para o segundo fator: com a senha vazada e um
          # mfa_token válido (5 min), o código de 6 dígitos podia ser tentado sem limite.
          if user.locked?
            Audit::AuditLog.record!("mfa_blocked", user:, ip: request.remote_ip)
            return render json: { error: "conta bloqueada temporariamente" }, status: :unauthorized
          end
          unless user.verify_otp(params.require(:code))
            user.register_failed_attempt!
            Audit::AuditLog.record!("mfa_failed", user:, ip: request.remote_ip)
            return render json: { error: "código inválido" }, status: :unauthorized
          end
          issue_session(user)
        rescue ::Auth::Tokens::Invalid
          render json: { error: "desafio MFA expirado; faça login novamente" }, status: :unauthorized
        end

        # POST /auth/refresh { refresh_token }
        def refresh
          user, new_refresh = ::Auth::Tokens.rotate_refresh(params.require(:refresh_token), request:)
          return render json: { error: "usuário inativo" }, status: :unauthorized unless user.active
          render json: session_payload(user, new_refresh)
        rescue ::Auth::Tokens::Invalid => e
          render json: { error: e.message }, status: :unauthorized
        end

        # DELETE /auth/logout { refresh_token }
        def logout
          ::Auth::Tokens.revoke_refresh(params[:refresh_token].to_s) if params[:refresh_token].present?
          head :no_content
        end

        def logout_all
          current_user.refresh_tokens.update_all(revoked_at: Time.current)
          audit!("logout_all")
          head :no_content
        end

        def me = render(json: user_payload(current_user))

        private

        def issue_session(user)
          user.register_success!
          Audit::AuditLog.record!("login", user:, ip: request.remote_ip)
          render json: session_payload(user, ::Auth::Tokens.issue_refresh(user, request:))
        end

        def session_payload(user, refresh)
          { access_token: ::Auth::Tokens.issue_access(user), refresh_token: refresh, expires_in: ::Auth::Tokens::ACCESS_TTL.to_i, user: user_payload(user) }
        end

        def user_payload(u)
          { id: u.id, name: u.name, email: u.email, role: u.role, otp_enabled: u.otp_enabled, firm: { id: u.firm.id, name: u.firm.name } }
        end
      end
    end
  end
end
