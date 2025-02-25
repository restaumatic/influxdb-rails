require "spec_helper"
require "shared_examples/data"

RSpec.describe InfluxDB::Rails::Middleware::RenderSubscriber do
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
    let(:hook_name) { "render_partial.action_view" }
    let(:payload) { { identifier: "index.html", count: 43, cache_hits: 42 } }
    let(:data) do
      {
        values:    {
          value:      2000,
          count:      43,
          cache_hits: 42
        },
        tags:      {
          filename: "index.html",
          location: "Foo#bar",
          hook:     "render_partial",
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

      it_behaves_like "with additional data"

      context "with an empty value" do
        before do
          payload[:count] = nil
          data[:values].delete(:count)
        end

        it "does not write empty value" do
          expect_any_instance_of(InfluxDB::Client).to receive(:write_point).with(
            config.measurement_name, data
          )
          subject.call("name", start, finish, "id", payload)
        end
      end

      context "disabled" do
        before do
          allow(config).to receive(:ignored_hooks).and_return(["render_partial.action_view"])
        end

        subject { described_class.new(config, nil) }

        it "does not write a data point" do
          expect_any_instance_of(InfluxDB::Client).not_to receive(:write_point)
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
  end
end
