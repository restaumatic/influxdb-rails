require "influxdb"
require "rails"

module InfluxDB
  module Rails
    class Railtie < ::Rails::Railtie # :nodoc:
      initializer "influxdb.insert_rack_middleware" do |app|
        app.config.middleware.insert 0, InfluxDB::Rails::Rack
      end

      config.after_initialize do # rubocop:disable Metrics/BlockLength
        InfluxDB::Rails.configure do |config|
          config.logger           ||= ::Rails.logger
          config.environment      ||= ::Rails.env
          config.application_root ||= ::Rails.root
          config.application_name ||= ::Rails.application.class.parent_name
          config.framework          = "Rails".freeze
          config.framework_version  = ::Rails.version
        end

        ActiveSupport.on_load(:action_controller) do
          require "influxdb/rails/air_traffic_controller"
          include InfluxDB::Rails::AirTrafficController
          require "influxdb/rails/instrumentation"
          include InfluxDB::Rails::Instrumentation
        end

        cache = lambda do |_, _, _, _, payload|
          current = InfluxDB::Rails.current
          current.controller = payload[:controller]
          current.action     = payload[:action]
        end
        ActiveSupport::Notifications.subscribe "start_processing.action_controller", &cache

        {
          "process_action.action_controller" => Middleware::RequestSubscriber,
          "render_template.action_view"      => Middleware::RenderSubscriber,
          "render_partial.action_view"       => Middleware::RenderSubscriber,
          "render_collection.action_view"    => Middleware::RenderSubscriber,
          "sql.active_record"                => Middleware::SqlSubscriber,
        }.each do |hook_name, subscriber_class|
          subscribe_to(hook_name, subscriber_class)
        end
      end

      def subscribe_to(hook_name, subscriber_class)
        subscriber = subscriber_class.new(InfluxDB::Rails.configuration, hook_name)
        ActiveSupport::Notifications.subscribe hook_name, subscriber
      end
    end
  end
end
