# Seeds (and on every later boot re-applies) the deployment's administrator.
#
# A stock Chatwoot production deploy creates no user at all: db/seeds.rb only
# seeds an account in non-production, ENABLE_ACCOUNT_SIGNUP ships as false, and
# Api::V1::AccountsController#check_signup_enabled then answers the signup route
# with 404. There is no other HTTP path to a first account, so the instance is
# unusable. This runs before the web server binds the port.
email = ENV['CHATWOOT_ADMIN_EMAIL'].to_s.strip.downcase
password = ENV['CHATWOOT_ADMIN_PASSWORD'].to_s
account_name = ENV['CHATWOOT_ACCOUNT_NAME'].to_s.strip
account_name = 'My Company' if account_name.empty?

abort('[railway] CHATWOOT_ADMIN_EMAIL is required') if email.empty?
abort('[railway] CHATWOOT_ADMIN_PASSWORD is required') if password.empty?

GlobalConfig.clear_cache
account = Account.first || Account.create!(name: account_name)

user = User.find_by(email: email)
if user
  user.password = password
  user.password_confirmation = password
  user.confirmed_at ||= Time.current
  user.save!
  puts "[railway] administrator #{email} password re-applied"
else
  user = User.new(name: ENV.fetch('CHATWOOT_ADMIN_NAME', 'Administrator'),
                  email: email, password: password, type: 'SuperAdmin')
  user.skip_confirmation!
  user.save!
  puts "[railway] administrator #{email} created"
end

account_user = AccountUser.find_or_initialize_by(account_id: account.id, user_id: user.id)
account_user.role = :administrator
account_user.save!
puts "[railway] account '#{account.name}' ready with #{User.count} user(s)"
