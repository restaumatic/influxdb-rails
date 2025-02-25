require "spec_helper"

RSpec.describe InfluxDB::Rails do
  before do
    InfluxDB::Rails.configure do |config|
      config.application_name = "my-rails-app"
      config.ignored_environments = []
      config.client.time_precision = "ms"
    end
  end

  describe ".current_timestamp" do
    let(:timestamp) { 1_513_009_229_111 }

    it "should return the current timestamp in the configured precision" do
      expect(Process).to receive(:clock_gettime)
        .with(Process::CLOCK_REALTIME, :millisecond)
        .and_return(timestamp)

      expect(InfluxDB::Rails.current_timestamp).to eq(timestamp)
    end
  end

  describe ".ignorable_exception?" do
    it "should be true for exception types specified in the configuration" do
      class DummyException < RuntimeError; end
      exception = DummyException.new

      InfluxDB::Rails.configure do |config|
        config.ignored_exceptions << "DummyException"
      end

      expect(InfluxDB::Rails.ignorable_exception?(exception)).to be_truthy
    end

    it "should be true for exception types specified in the configuration" do
      exception = ActionController::RoutingError.new("foo")
      expect(InfluxDB::Rails.ignorable_exception?(exception)).to be_truthy
    end

    it "should be false for valid exceptions" do
      exception = ZeroDivisionError.new
      expect(InfluxDB::Rails.ignorable_exception?(exception)).to be_falsey
    end
  end

  describe "rescue" do
    it "should transmit an exception when passed" do
      expect(InfluxDB::Rails.client).to receive(:write_point)

      InfluxDB::Rails.rescue do
        raise ArgumentError, "wrong"
      end
    end

    it "should also raise the exception when in an ignored environment" do
      InfluxDB::Rails.configure do |config|
        config.ignored_environments = %w[development test]
      end

      expect do
        InfluxDB::Rails.rescue do
          raise ArgumentError, "wrong"
        end
      end.to raise_error(ArgumentError)
    end
  end

  describe "rescue_and_reraise" do
    it "should transmit an exception when passed" do
      expect(InfluxDB::Rails.client).to receive(:write_point)

      expect do
        InfluxDB::Rails.rescue_and_reraise { raise ArgumentError, "wrong" }
      end.to raise_error(ArgumentError)
    end
  end
end
