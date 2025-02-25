require "spec_helper"
require "shared_examples/data"

RSpec.describe InfluxDB::Rails::Middleware::SqlSubscriber do
  let(:config) { InfluxDB::Rails::Configuration.new }
  let(:logger) { double(:logger) }

  before do
    allow(config).to receive(:application_name).and_return("my-rails-app")
    allow(config).to receive(:ignored_environments).and_return([])
    allow(config.client).to receive(:time_precision).and_return("ms")
  end

  describe ".call" do
    let(:start)   { Time.at(1_517_567_368) }
    let(:finish)  { Time.at(1_517_567_370) }
    let(:hook_name) { "sql.active_record" }
    let(:payload) { { sql: "SELECT * FROM POSTS WHERE id = 1", name: "Post Load", binds: %w[1 2 3] } }
    let(:data) do
      {
        values:    {
          value: 2000,
          sql:   "SELECT * FROM POSTS WHERE id = xxx"
        },
        tags:      {
          location:   "Foo#bar",
          operation:  "SELECT",
          class_name: "Post",
          hook:       "sql",
          name:       "Post Load",
        },
        timestamp: 1_517_567_370_000
      }
    end

    subject { described_class.new(config, hook_name) }

    before do
      InfluxDB::Rails.current.controller = "Foo"
      InfluxDB::Rails.current.action = "bar"
    end

    after do
      InfluxDB::Rails.current.reset
    end

    context "successfully" do
      it "writes to InfluxDB" do
        expect_any_instance_of(InfluxDB::Client).to receive(:write_point).with(
          config.measurement_name, data
        )
        subject.call("name", start, finish, "id", payload)
      end

      context "with not relevant queries" do
        before do
          payload[:sql] = "SHOW FULL FIELDS FROM `users`"
        end

        it "does not write to InfluxDB" do
          expect_any_instance_of(InfluxDB::Client).not_to receive(:write_point)
          subject.call("name", start, finish, "id", payload)
        end
      end

      it_behaves_like "with additional data", ["sql"]

      context "without location" do
        before do
          InfluxDB::Rails.current.reset
        end

        it "does use the default location" do
          data[:tags] = data[:tags].merge(location: :raw)
          expect_any_instance_of(InfluxDB::Client).to receive(:write_point).with(
            config.measurement_name, data
          )
          subject.call("name", start, finish, "id", payload)
        end
      end
    end

    context "unsuccessfully" do
      before do
        allow(config).to receive(:logger).and_return(logger)
        InfluxDB::Rails.configuration = config
      end

      it "does log exceptions" do
        allow_any_instance_of(InfluxDB::Client).to receive(:write_point).and_raise("boom")
        expect(logger).to receive(:error).with(/boom/)
        subject.call("name", start, finish, "id", payload)
      end
    end

    context "disabled" do
      before do
        allow(config).to receive(:ignored_hooks).and_return(["sql.active_record"])
      end

      subject { described_class.new(config, "sql.active_record") }

      it "does not write a data point" do
        expect_any_instance_of(InfluxDB::Client).not_to receive(:write_point)
        subject.call("name", start, finish, "id", payload)
      end
    end
  end
end
