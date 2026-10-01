# Login, logout e falhas de login entram na trilha de auditoria (RF 1).
Warden::Manager.after_authentication do |user, auth, _opts|
  next unless user.is_a?(User)

  AuditLog.create!(action: "login", area: "acesso", user: user, auditable: user,
                   auditable_label: user.name, ip_address: auth.request.remote_ip)
end

Warden::Manager.before_failure do |env, opts|
  request = ActionDispatch::Request.new(env)
  next unless request.post? && opts[:action] == "unauthenticated" && opts[:scope] == :user
  next if opts[:message] == :timeout

  email = request.params.dig("user", "email").to_s.strip.downcase
  next if email.blank?

  user = User.find_by(email: email)
  AuditLog.create!(action: "login_failed", area: "acesso", user: user, auditable: user,
                   auditable_label: email, changeset: { "motivo" => opts[:message].to_s },
                   ip_address: request.remote_ip)
end

Warden::Manager.before_logout do |user, auth, _opts|
  next unless user.is_a?(User)

  AuditLog.create!(action: "logout", area: "acesso", user: user, auditable: user,
                   auditable_label: user.name, ip_address: auth.request.remote_ip)
end
