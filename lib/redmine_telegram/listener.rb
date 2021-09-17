require 'httpclient'

class TelegramListener < Redmine::Hook::Listener

  $DEBUG = 0

	def redmine_telegram_email_issues_new_after_save(context={})
		issue = context[:issue]

    users = []
    users.push(issue.author) if issue.author != issue.assigned_to
    users.push(issue.assigned_to) if issue.assigned_to

		msg = "<b>[#{escape issue.project}]</b>\n<a href='#{object_url issue}'>#{escape issue}</a>\n<b>#{escape issue.author}</b> #{l(:field_created_on)}\n"
		Rails.logger.info("TELEGRAM NEW ISSUE [#{issue.project.name} - #{issue.tracker.name} ##{issue.id}] (#{issue.status.name}) #{issue.subject}")

		attachment = {}
		attachment[:text] = escape issue.description if issue.description
		attachment[:fields] = [{
			:title => I18n.t("field_status"),
			:value => escape(issue.status.to_s),
			:short => true
		}, {
			:title => I18n.t("field_priority"),
			:value => escape(issue.priority.to_s),
			:short => true
		}, {
			:title => I18n.t("field_assigned_to"),
			:value => escape(issue.assigned_to.to_s),
			:short => true
		}]

		attachment[:fields] << {
			:title => I18n.t("field_watcher"),
			:value => escape(issue.watcher_users.join(', ')),
			:short => true
		} if Setting.plugin_redmine_telegram_email['display_watchers'] == 'yes'

    users_processing users, issue, msg, attachment

	end

	def redmine_telegram_email_issues_edit_after_save(context={})
		issue = context[:issue]
		journal = context[:journal]

		Rails.logger.info("TELEGRAM CONTENT #{context} WATCHERS #{issue.watcher_users} ASSIGNED_TO #{issue.assigned_to} ISSUEAUTHOR #{issue.author}") if $DEBUG == 1

    users = []
    users.push(issue.author) if issue.author != issue.assigned_to
    users.push(issue.assigned_to) if issue.assigned_to

    issue.watcher_users.each do |watcher|
      users.push(watcher)
    end

    users = users.uniq

    msg = "<b>[#{escape issue.project}]</b>\n<a href='#{object_url issue}'>#{escape issue}</a>\n<b>#{journal.user.to_s}</b> #{l(:field_updated_on)}"
    Rails.logger.info("TELEGRAM EDITED ISSUE [#{issue.project.name} - #{issue.tracker.name} ##{issue.id}] (#{issue.status.name}) #{issue.subject}")

    attachment = {}
    attachment[:text] = escape journal.notes if journal.notes
    attachment[:fields] = journal.details.map { |d| detail_to_field d }

    users_processing users, issue, msg, attachment

	end

  def users_processing(users, issue, msg, attachment)
    users.each do |user|
      Rails.logger.info("TELEGRAM USER ARRAY NAME: #{user}") if $DEBUG == 1
      next if user.id.to_i == issue.author_id.to_i and Setting.plugin_redmine_telegram_email[:selfupdate_dont_send] == '1'
      telegram_chat_id = 0
      telegram_disable = 0
      user.custom_field_values.each do |telegram_field|
        if telegram_field.custom_field.name.to_s == 'Telegram Channel' and telegram_field.value.to_i != 0
          telegram_chat_id = telegram_field.value.to_i
        end
        if telegram_field.custom_field.name.to_s == 'Telegram disable email'
          telegram_disable = telegram_field.value.to_i
        end
      end
      Rails.logger.info("TELEGRAM CHAT AND DISABLED #{telegram_chat_id} #{telegram_disable}") if $DEBUG == 1
      if telegram_chat_id != 0
        speak msg, telegram_chat_id, attachment
        Rails.logger.info("TELEGRAM SPEAK TO #{telegram_chat_id} #{attachment} #{user.login}")
      end
    end
  end

	def speak(msg, channel, attachment=nil)
		Rails.logger.info("TELEGRAM SPEAK\n #{msg}\n => #{channel}") if $DEBUG == 1
		token = Setting.plugin_redmine_telegram_email['telegram_bot_token']
		Rails.logger.info("TELEGRAM TOKEN EMPTY, PLEASE SET IT IN PLUGIN SETTINGS") if token.nil? || token.empty?
		proxyurl = Setting.plugin_redmine_telegram_email['proxyurl']

		telegram_url = "https://api.telegram.org/bot#{token}/sendMessage"

		Rails.logger.info("telegram_url #{telegram_url}")

		params = {}
		params[:chat_id] = channel if channel
		params[:parse_mode] = "HTML"
		params[:disable_web_page_preview] = 1

		if attachment
			msg = msg + "\r\n"
			msg = msg + attachment[:text] if attachment[:text]
			for field_item in attachment[:fields] do
        msg = msg +"\r\n"+"<b>"+field_item[:title]+":</b> " + escape(field_item[:value])
			end
		end

		params[:text] = msg

		Thread.new do
			retries = 0
			begin
				if Setting.plugin_redmine_telegram_email['use_proxy'] == '1'
					client = HTTPClient.new(proxyurl)
				else
					client = HTTPClient.new
				end
				client.connect_timeout = 2
				client.send_timeout = 2
				client.receive_timeout = 2
				client.keep_alive_timeout = 2
				client.ssl_config.timeout = 2
				conn = client.post_async(telegram_url, params)
        Rails.logger.info("TELEGRAM TEXT TO SEND #{params[:text]}") if $DEBUG == 1
        Rails.logger.info("TELEGRAM ANSWER #{conn.pop.body.read}") if $DEBUG == 1
				Rails.logger.info("TELEGRAM CODE: #{conn.pop.status_code}")
			rescue Exception => e
				Rails.logger.warn("TELEGRAM CANNOT CONNECT TO #{telegram_url} RETRY ##{retries}, ERROR #{e}")
				retry if (retries += 1) < 5
			end
		end
	end

	private
	def escape(msg)
		msg.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
	end

	def object_url(obj)
		if Setting.host_name.to_s =~ /\A(https?\:\/\/)?(.+?)(\:(\d+))?(\/.+)?\z/i
			host, port, prefix = $2, $4, $5
			Rails.application.routes.url_for(obj.event_url({
				:host => host,
				:protocol => Setting.protocol,
				:port => port,
				:script_name => prefix
			}))
		else
			Rails.application.routes.url_for(obj.event_url({
				:host => Setting.host_name,
				:protocol => Setting.protocol
			}))
		end
	end

	def detail_to_field(detail)
		case detail.property
		when "cf"
			custom_field = detail.custom_field
			key = custom_field.name
			title = key
			value = (detail.value)? IssuesController.helpers.format_value(detail.value, custom_field) : ""
		when "attachment"
			key = "attachment"
			title = I18n.t :label_attachment
			value = escape detail.value.to_s
		else
			key = detail.prop_key.to_s.sub("_id", "")
			if key == "parent"
				title = I18n.t "field_#{key}_issue"
			else
				title = I18n.t "field_#{key}"
			end
			value = escape detail.value.to_s
		end

		short = true

		case key
		when "title", "subject", "description"
			short = false
		when "tracker"
			tracker = Tracker.find(detail.value) rescue nil
			value = escape tracker.to_s
		when "project"
			project = Project.find(detail.value) rescue nil
			value = escape project.to_s
		when "status"
			status = IssueStatus.find(detail.value) rescue nil
			value = escape status.to_s
		when "priority"
			priority = IssuePriority.find(detail.value) rescue nil
			value = escape priority.to_s
		when "category"
			category = IssueCategory.find(detail.value) rescue nil
			value = escape category.to_s
		when "assigned_to"
			user = User.find(detail.value) rescue nil
			value = escape user.to_s
		when "fixed_version"
			version = Version.find(detail.value) rescue nil
			value = escape version.to_s
		when "attachment"
			attachment = Attachment.find(detail.prop_key) rescue nil
			value = "<#{object_url attachment}|#{escape attachment.filename}>" if attachment
		when "parent"
			issue = Issue.find(detail.value) rescue nil
			value = "<#{object_url issue}|#{escape issue}>" if issue
		end

		value = "-" if value.empty?

		result = { :title => title, :value => value }
		result[:short] = true if short
		result
	end

end
