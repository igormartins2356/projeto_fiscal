module Api
  module V1
    module Auth
      # 2FA TOTP: setup (segredo + QR) → enable (confirma código, gera backup codes) → disable (senha + código)
      class OtpController < BaseController
        def setup
          current_user.update!(otp_secret: ROTP::Base32.random) unless current_user.otp_enabled
          return render json: { error: "2FA já ativo" }, status: :unprocessable_entity if current_user.otp_enabled
          uri = current_user.otp_provisioning_uri
          svg = RQRCode::QRCode.new(uri).as_svg(module_size: 4, color: "000", viewbox: true)
          render json: { otpauth_uri: uri, secret: current_user.otp_secret, qr_svg: svg }
        end

        def enable
          return render json: { error: "faça o setup primeiro" }, status: :unprocessable_entity if current_user.otp_secret.blank?
          return render json: { error: "código inválido" }, status: :unprocessable_entity unless current_user.verify_otp(params.require(:code))
          current_user.update!(otp_enabled: true)
          codes = current_user.generate_backup_codes!
          current_user.refresh_tokens.update_all(revoked_at: Time.current)
          audit!("mfa_enabled")
          render json: { otp_enabled: true, backup_codes: codes }
        end

        def disable
          unless current_user.authenticate(params.require(:password)) && current_user.verify_otp(params.require(:code))
            return render json: { error: "senha ou código inválidos" }, status: :unprocessable_entity
          end
          current_user.update!(otp_enabled: false, otp_secret: nil, otp_backup_codes: [])
          audit!("mfa_disabled")
          render json: { otp_enabled: false }
        end
      end
    end
  end
end
