class Rack::Attack
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new unless Rails.env.production?

  throttle("auth/login/ip", limit: 10, period: 60) { |req| req.ip if req.path == "/api/v1/auth/login" && req.post? }
  throttle("auth/login/email", limit: 5, period: 60) do |req|
    if req.path == "/api/v1/auth/login" && req.post?
      req.params["email"].to_s.downcase.presence
    end
  end
  throttle("auth/mfa/ip", limit: 10, period: 60) { |req| req.ip if req.path.start_with?("/api/v1/auth/mfa") && req.post? }
  throttle("api/ip", limit: 600, period: 60) { |req| req.ip if req.path.start_with?("/api/") }

  self.throttled_responder = ->(_req) { [429, { "Content-Type" => "application/json" }, [{ error: "muitas tentativas; aguarde um minuto" }.to_json]] }
end
Rack::Attack.enabled = !Rails.env.test?
Rails.application.config.middleware.use Rack::Attack
