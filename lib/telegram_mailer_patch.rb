require 'httpclient'

require_dependency 'mailer'

module TelegramMailerPatch
  def self.included(base) # :nodoc:
    
    base.extend(ClassMethods)

    base.send(:include, InstanceMethods)

    base.class_eval do
      alias_method_chain :issue_add, :telegram
      alias_method_chain :issue_edit, :telegram
    end
  end
  
  module ClassMethods

    def speak(msg, channel, attachment=nil)
      Rails.logger.info("TELEGRAM SPEAK #{msg} => #{channel}")
      token = Setting.plugin_redmine_telegram_email[:telegram_bot_token]
      Rails.logger.info("TELEGRAM TOKEN EMPTY, PLEASE SET IT IN PLUGIN SETTINGS") if token.nil? || token.empty?
      proxyurl = Setting.plugin_redmine_telegram_email[:proxyurl]
      
      telegram_url = "https://api.telegram.org/bot#{token}/sendMessage"
      
      Rails.logger.info("telegram_url #{telegram_url}")
      
      params = {}
      params[:chat_id] = channel if channel
      params[:parse_mode] = "HTML"
      params[:disable_web_page_preview] = 1

      if attachment
        
        msg = msg +"\r\n"
        msg = msg +attachment[:text] if attachment[:text]
        
        for field_item in attachment[:fields] do
          
          msg = msg +"\r\n"+"<b>"+field_item[:title]+":</b> "+field_item[:value]
          
        end
      end

      params[:text] = msg
      
      begin
        if Setting.plugin_redmine_telegram_email[:use_proxy] == '1'
          client = HTTPClient.new(proxyurl)
        else
          client = HTTPClient.new
        end
        # client.ssl_config.cert_store.set_default_paths
        # client.ssl_config.ssl_version = "SSLv23"
        # client.post_async url, {:payload => params.to_json}
        client.connect_timeout = 1
        client.send_timeout = 1
        client.receive_timeout = 1
        client.keep_alive_timeout = 1
        client.ssl_config.timeout = 1
        conn = client.post_async(telegram_url, params)
        Rails.logger.info("TELEGRAM SEND CODE: #{conn.pop.status_code}")
      rescue Exception => e
        Rails.logger.warn("TELEGRAM CANNOT CONNECT TO #{telegram_url}")
        Rails.logger.warn(e)
      end
    end

  end
  
  module InstanceMethods
    def issue_add_with_telegram(issue, to_users, cc_users)
      
      issue_url = url_for(:controller => 'issues', :action => 'show', :id => issue)
      users = to_users + cc_users

      msg = "<b>[#{escape issue.project}]</b>\n<a href='#{issue_url}'>#{escape issue}</a> #{mentions issue.description if Setting.plugin_redmine_telegram_email[:auto_mentions] == '1'}\n<b>#{escape issue.author}</b> #{l(:field_created_on)}\n"
      Rails.logger.info("TELEGRAM Add Issue [#{issue.project.name} - #{issue.tracker.name} ##{issue.id}] (#{issue.status.name}) #{issue.subject}")
      
      attachment = {}
      attachment[:text] = escape issue.description if issue.description if Setting.plugin_redmine_telegram_email[:new_include_description] == '1'
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
      } if Setting.plugin_redmine_telegram_email[:display_watchers] == 'yes'

      users.each do |user|
        next if user.id.to_i == issue.author_id.to_i
        telegram_chat_id = 0
        telegram_disable_email = 0
        user.custom_field_values.each do |telegram_field|
          if telegram_field.custom_field.name.to_s == 'Telegram Channel' and telegram_field.value.to_i != 0
            telegram_chat_id = telegram_field.value.to_i
          end
          if telegram_field.custom_field.name.to_s == 'Telegram disable email'
            telegram_disable_email = telegram_field.value.to_i
          end
        end
        if telegram_chat_id != 0
          Mailer.speak(msg, telegram_chat_id, attachment)
          Rails.logger.info("SPEAK TO TELEGRAM #{telegram_chat_id} #{attachment} #{user.login}")
        end
        if telegram_disable_email != 0 and telegram_chat_id != 0
          current_user = []
          current_user << user
          to_users = to_users - current_user
          cc_users = cc_users - current_user
        end
      end

      issue_add_without_telegram(issue, to_users, cc_users)
    end

    def issue_edit_with_telegram(journal, to_users, cc_users)
      
      issue = journal.journalized
      issue_url = url_for(:controller => 'issues', :action => 'show', :id => issue, :anchor => "change-#{journal.id}")
      users = to_users + cc_users
      journal_details = journal.visible_details(users.first)

      msg = "<b>[#{escape issue.project}]</b>\n<a href='#{issue_url}'>#{escape issue}</a> #{mentions journal.notes if Setting.plugin_redmine_telegram_email[:auto_mentions] == '1'}\n<b>#{journal.user.to_s}</b> #{l(:field_updated_on)}"
      Rails.logger.info("TELEGRAM Edit Issue [#{issue.project} - #{issue} ##{issue_url}]")

      attachment = {}
      attachment[:text] = "<b>#{l(:field_comments)}</b>: #{escape journal.notes}" if Setting.plugin_redmine_telegram_email[:updated_include_description] == '1' if journal.notes != ""
      attachment[:fields] = journal.details.map { |d| detail_to_field d }

      users.each do |user|
        next if user.id.to_i == journal.user.id.to_i
        telegram_chat_id = 0
        telegram_disable_email = 0
        user.custom_field_values.each do |telegram_field|
          if telegram_field.custom_field.name.to_s == 'Telegram Channel' and telegram_field.value.to_i != 0
            telegram_chat_id = telegram_field.value.to_i
          end
          if telegram_field.custom_field.name.to_s == 'Telegram disable email'
            telegram_disable_email = telegram_field.value.to_i
          end
        end
        if telegram_chat_id != 0
          Mailer.speak(msg, telegram_chat_id, attachment)
          Rails.logger.info("SPEAK TO TELEGRAM #{telegram_chat_id} #{attachment} #{user.login}")
        end
        if telegram_disable_email != 0 and telegram_chat_id != 0
          current_user = []
          current_user << user
          to_users = to_users - current_user
          cc_users = cc_users - current_user
        end
      end

      issue_edit_without_telegram(journal, to_users, cc_users)
    end

    def escape(msg)
      msg.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub("[", "\[").gsub("]", "\]").gsub("&lt;pre&gt;", "<code>").gsub("&lt;/pre&gt;", "</code>")
    end

    def object_url(obj)
      Rails.application.routes.url_for(obj.event_url({:host => Setting.host_name, :protocol => Setting.protocol}))
    end

    def detail_to_field(detail)
      if detail.property == "cf"
        key = CustomField.find(detail.prop_key).name rescue nil
        title = key
      elsif detail.property == "attachment"
        key = "attachment"
        title = I18n.t :label_attachment
      else
        key = detail.prop_key.to_s.sub("_id", "")
        title = I18n.t "field_#{key}"
      end

      short = true
      value = escape detail.value.to_s

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
        value = "#{object_url attachment}" if attachment
      when "parent"
        issue = Issue.find(detail.value) rescue nil
        value = "#{object_url issue}" if issue
      end

      value = " - " if value.empty?

      result = { :title => title, :value => value }
      result[:short] = true if short
      result
    end

    def mentions text
      names = extract_usernames text
      names.present? ? "\nTo: " + names.join(', ') : nil
    end

    def extract_usernames text = ''
      # slack usernames may only contain lowercase letters, numbers,
      # dashes and underscores and must start with a letter or number.
      begin
        text.scan(/@[a-z0-9][a-z0-9_\-]*/).uniq
      rescue
        ""
      end
    end

  end
end

Mailer.send(:include, TelegramMailerPatch)


