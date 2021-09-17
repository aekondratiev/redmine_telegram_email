require 'redmine'

require_dependency 'redmine_telegram_email/listener'

Redmine::Plugin.register :redmine_telegram_email do
	name 'Redmine Telegram Email'
	author 'Andry Kondratiev'
	url 'https://github.com/aekondratiev/redmine_telegram_email'
	author_url 'https://github.com/aekondratiev'
	description 'Telegram integration'
	version '0.3'

	requires_redmine :version_or_higher => '0.8.0'

	settings \
		:default => {
                        'callback_url' => 'https://api.telegram.org/bot',
                        'display_watchers' => 'yes',
                        'auto_mentions' => 'yes',
                        'new_include_description' => 1,
                        'updated_include_description' => 1,
                        'use_proxy' => 0,
                        'proxyurl' => nil,
                        'selfupdate_dont_send' => 0
		},
		:partial => 'settings/telegram_email_settings'
end

((Rails.version > "5")? ActiveSupport::Reloader : ActionDispatch::Callbacks).to_prepare do
	require_dependency 'issue'
	unless Issue.included_modules.include? RedmineTelegram::IssuePatch
		Issue.send(:include, RedmineTelegram::IssuePatch)
	end
end


