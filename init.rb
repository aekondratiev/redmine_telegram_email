require 'redmine'

require 'telegram_mailer_patch'

Redmine::Plugin.register :redmine_telegram_email do
	name 'Redmine Telegram Email'
	author 'Andry Kondratiev'
	url 'https://github.com/massdest/redmine_telegram_email'
	author_url 'https://github.com/massdest'
	description 'Telegram messenger plugin, like email, but to Telegram'
	version '0.1'

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
