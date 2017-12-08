require_relative 'hawkular_helper'

# VCR Cassettes: Hawkular Services 0.40.0.Final-SNAPSHOT (commit 61ad2c1db6dc94062841ca2f5be9699e69d96cfe)

describe ManageIQ::Providers::Hawkular::MiddlewareManager::MiddlewareServer do
  subject { described_class.new(:properties => {}) }

  let(:ems_hawkular) do
    # allow(MiqServer).to receive(:my_zone).and_return("default")
    _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone
    auth = AuthToken.new(:name     => "test",
                         :auth_key => "valid-token",
                         :userid   => test_userid,
                         :password => test_password)
    FactoryGirl.create(:ems_hawkular,
                       :hostname        => test_hostname,
                       :port            => test_port,
                       :authentications => [auth],
                       :zone            => zone)
  end

  let(:eap) do
    FactoryGirl.create(:hawkular_middleware_server,
                       :name                  => 'Local',
                       :feed                  => test_mw_manager_feed_id,
                       :ems_ref               => "#{test_mw_manager_feed_id}~Local~~",
                       :nativeid              => "#{test_mw_manager_feed_id}~Local~~",
                       :ext_management_system => ems_hawkular)
  end

  let(:expected_metrics) do
    {
      "Heap Used"                                  => "mw_heap_used",
      "Heap Max"                                   => "mw_heap_max",
      "Heap Committed"                             => "mw_heap_committed",
      "NonHeap Used"                               => "mw_non_heap_used",
      "NonHeap Committed"                          => "mw_non_heap_committed",
      "Accumulated GC Duration"                    => "mw_accumulated_gc_duration",
      "Aggregated Servlet Request Time"            => "mw_aggregated_servlet_time",
      "Aggregated Servlet Request Count"           => "mw_aggregated_servlet_request_count",
      "Aggregated Expired Web Sessions"            => "mw_aggregated_expired_web_sessions",
      "Aggregated Max Active Web Sessions"         => "mw_aggregated_max_active_web_sessions",
      "Aggregated Active Web Sessions"             => "mw_aggregated_active_web_sessions",
      "Aggregated Rejected Web Sessions"           => "mw_aggregated_rejected_web_sessions",
      "Thread Count"                               => "mw_thread_count",
      "App Server"                                 => "mw_availability_app_server",
      "Number of Aborted Transactions"             => "mw_tx_aborted",
      "Number of In-Flight Transactions"           => "mw_tx_inflight",
      "Number of Committed Transactions"           => "mw_tx_committed",
      "Number of Transactions"                     => "mw_tx_total",
      "Number of Application Rollbacks"            => "mw_tx_application_rollbacks",
      "Number of Resource Rollbacks"               => "mw_tx_resource_rollbacks",
      "Number of Timed Out Transactions"           => "mw_tx_timeout",
      "Number of Nested Transactions"              => "mw_tx_nested",
      "Number of Heuristics"                       => "mw_tx_heuristics"
    }.freeze
  end

  it "#collect_stats_metrics" do
    start_time = test_start_time
    end_time = test_end_time
    interval = 3600
    VCR.use_cassette(described_class.name.underscore.to_s,
                     :allow_unused_http_interactions => true,
                     :match_requests_on              => [:method, :uri, :body],
                     :decode_compressed_response     => true) do # , :record => :new_episodes) do
                       metrics_available = eap.metrics_available
                       metrics_ids_map, raw_stats = eap.collect_stats_metrics(metrics_available, start_time, end_time, interval)
                       expect(metrics_ids_map.keys.size).to be > 0
                       expect(raw_stats.keys.size).to be > 0
                     end
  end

  it "#collect_live_metrics for all metrics available" do
    start_time = test_start_time
    end_time = test_end_time
    interval = 3600
    VCR.use_cassette(described_class.name.underscore.to_s,
                     :allow_unused_http_interactions => true,
                     :match_requests_on              => [:method, :uri, :body],
                     :decode_compressed_response     => true) do # , :record => :new_episodes) do
                       metrics_available = eap.metrics_available
                       metrics_data = eap.collect_live_metrics(metrics_available, start_time, end_time, interval)
                       keys = metrics_data.keys
                       expect(metrics_data[keys[0]].keys.size).to be > 3
                     end
  end

  it "#collect_live_metrics for three metrics" do
    start_time = test_start_time
    end_time = test_end_time
    interval = 3600
    VCR.use_cassette(described_class.name.underscore.to_s,
                     :allow_unused_http_interactions => true,
                     :match_requests_on              => [:method, :uri, :body],
                     :decode_compressed_response     => true) do # , :record => :new_episodes) do
                       metrics_available = eap.metrics_available
                       expect(metrics_available.size).to be > 3
                       metrics_data = eap.collect_live_metrics(metrics_available[0, 3],
                                                               start_time,
                                                               end_time,
                                                               interval)
                       keys = metrics_data.keys
                       # Assuming that for the test the first key has data for 3 metrics
                       expect(metrics_data[keys[0]].keys.size).to eq(3)
                     end
  end

  it "#first_and_last_capture" do
    VCR.use_cassette(described_class.name.underscore.to_s,
                     :allow_unused_http_interactions => true,
                     :match_requests_on              => [:method, VCR.request_matchers.uri_without_params(:end,:start)],
                     :decode_compressed_response     => true) do # , :record => :new_episodes) do
                       capture = eap.first_and_last_capture
                       expect(capture.any?).to be true
                       expect(capture[0]).to be < capture[1]
                     end
  end

  it "#supported_metrics" do
    supported_metrics = eap.supported_metrics['default']
    expected_metrics.each { |k, v| expect(supported_metrics[k]).to eq(v) }

    model_config = MiddlewareServer.live_metrics_config
    supported_metrics = model_config['supported_metrics']['default']
    expected_metrics.each { |k, v| expect(supported_metrics[k]).to eq(v) }
  end

  it "#metrics_available" do
    VCR.use_cassette(described_class.name.underscore.to_s,
                     :allow_unused_http_interactions => true,
                     :decode_compressed_response     => true) do # , :record => :new_episodes) do
                       metrics_available = eap.metrics_available
                       metrics_available.each { |metric| expect(expected_metrics.value?(metric['name'])).to be(true) }
                     end
  end

  it '#enqueue_diagnostic_report' do
    report = eap.enqueue_diagnostic_report(:requesting_user => 'my_user')
    expect(report.persisted?).to be_truthy
    expect(report.middleware_server).to be == eap
    expect(report.queued?).to be_truthy
  end

  describe '#feed' do
    it 'unescape escaped characters' do
      subject.feed = 'master.Unnamed%20Domain'
      expect(subject.feed).to eq 'master.Unnamed Domain'
    end

    it 'keeps other characters equal' do
      subject.feed = 'thisisnormal'
      expect(subject.feed).to eq 'thisisnormal'
    end
  end

  describe '#immutable?' do
    it 'is true if "Immutable" is set as true' do
      subject.properties = { 'Immutable' => 'true' }
      expect(subject).to be_immutable
    end

    it 'is false if "Immutable" is set as false' do
      subject.properties = { 'Immutable' => 'false' }
      expect(subject).not_to be_immutable
    end

    it 'is false if no keys are defined' do
      expect(subject).not_to be_immutable
    end
  end
end
