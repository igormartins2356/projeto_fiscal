if Sidekiq.server?
  Sidekiq::Cron::Job.load_from_hash!(YAML.load_file(Rails.root.join("config/schedule.yml"))) if defined?(Sidekiq::Cron)
end
