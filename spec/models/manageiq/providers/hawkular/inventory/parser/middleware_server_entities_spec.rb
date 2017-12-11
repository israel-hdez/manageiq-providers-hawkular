require_relative '../../middleware_manager/hawkular_helper'

describe ManageIQ::Providers::Hawkular::Inventory::Parser::MiddlewareServerEntities do
  let(:ems_hawkular) { ems_hawkular_fixture }
  let(:eap_with_tree) do
    Hawkular::Inventory::Resource.new(
      'id'       => 'server1',
      'feedId'   => 'feed1',
      'type'     => {'id' => 'WildFly Server WF10'},
      'config'   => {
        'Suspend State'  => 'RUNNING',
        'Bound Address'  => '127.0.0.1',
        'Running Mode'   => 'NORMAL',
        'Home Directory' => '/opt/jboss/wildfly',
        'Version'        => '11.0.0.Final',
        'Node Name'      => 'wf-standalone',
        'Server State'   => 'running',
        'Product Name'   => 'WildFly Full',
        'Hostname'       => 'wf-standalone',
        'UUID'           => 'uuid1',
        'Name'           => 'wf-standalone'
      },
      'children' => [eap_children_hash]
    )
  end
  let(:collector) do
    ManageIQ::Providers::Hawkular::Inventory::Collector::MiddlewareManager
      .new(ems_hawkular, ems_hawkular)
      .tap do |collector|
        allow(collector).to receive(:resource_tree).with('server1').and_return(eap_with_tree)
        allow(collector).to receive(:deployments).and_return([])
        allow(collector).to receive(:subdeployments).and_return([])
      end
  end
  let(:persister) do
    ManageIQ::Providers::Hawkular::Inventory::Persister::MiddlewareManager
      .new(ems_hawkular, ems_hawkular)
      .tap { |persister| persister.middleware_servers.build(:ems_ref => 'server1') }
  end
  subject(:parser) do
    described_class.new.tap do |parser|
      parser.collector = collector
      parser.persister = persister
    end
  end

  describe 'datasources parser' do
    let(:eap_children_hash) do
      {
        'id'       => 'ds1',
        'name'     => 'Datasource 1',
        'feedId'   => 'feed1',
        'type'     => {'id' => 'Datasource WF10'},
        'parentId' => 'server1',
        'config'   => {
          'Connection Properties' => nil,
          'Datasource Class'      => nil,
          'Security Domain'       => nil,
          'Username'              => 'sa',
          'Driver Name'           => 'h2',
          'JNDI Name'             => 'java:jboss/datasources/ExampleDS',
          'Connection URL'        => 'jdbc:h2:mem:test;DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE',
          'Enabled'               => 'true',
          'Driver Class'          => nil,
          'Password'              => 'sa'
        },
        'children' => []
      }
    end
    it 'parses a basic datasource' do
      parser.parse
      expect(persister.middleware_datasources.size).to eq(1)
      expect(persister.middleware_datasources.data.first.data).to include(
        :name       => 'Datasource 1',
        :nativeid   => 'ds1',
        :ems_ref    => 'ds1',
        :properties => include(
          'Driver Name'    => 'h2',
          'JNDI Name'      => 'java:jboss/datasources/ExampleDS',
          'Connection URL' => 'jdbc:h2:mem:test;DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE',
          'Enabled'        => 'true'
        )
      )
    end
  end

  describe 'deployments parser' do
    let(:metric_data) do
      { 'metric' => {'__name__' => 'wildfly_deployment_availability'}, 'value' => [123, 'arbitary value'] }
    end
    let(:eap_children_hash) do
      {
        'id'       => 'deploy1',
        'name'     => 'dp1.ear',
        'feedId'   => 'feed1',
        'type'     => {'id' => 'Deployment WF10'},
        'parentId' => 'server1',
        'config'   => {},
        'children' => [],
        'metrics'  => [
          {
            'displayName' => 'Deployment Status',
            'family'      => 'wildfly_deployment_availability',
            'unit'        => 'NONE',
            'expression'  => 'wildfly_deployment_availability{feed_id=\"feed1\",deployment=\"dp1.ear\"}',
            'labels'      => {
              'feed_id'    => 'feed1',
              'deployment' => 'dp1.ear'
            }
          }
        ]
      }
    end

    before do
      allow(collector).to receive(:deployments).and_return(eap_with_tree.children)
      allow(collector).to receive(:raw_availability_data)
        .with(array_including(hash_including('displayName' => 'Deployment Status')), any_args)
        .and_return([metric_data])
    end

    def parsed_deployment
      persister.middleware_deployments.data.first
    end

    delegate :data, :to => :parsed_deployment, :prefix => true

    it 'parses a basic deployment' do
      parser.parse

      expect(persister.middleware_deployments.size).to eq(1)
      expect(parsed_deployment_data).to include(
        :name       => 'dp1.ear',
        :nativeid   => 'deploy1',
        :ems_ref    => 'deploy1',
        :feed       => 'feed1',
        :properties => {}
      )
    end

    it 'assigns enabled status to a deployment with "up" metric' do
      metric_data['value'][1] = '1'

      parser.parse
      expect(parsed_deployment.status).to eq('Enabled')
    end

    it 'assigns disabled status to a deployment with "down" metric' do
      metric_data['value'][1] = '0'

      parser.parse
      expect(parsed_deployment.status).to eq('Disabled')
    end

    it 'assigns unknown status to a deployment with a missing metric' do
      allow(collector).to receive(:raw_availability_data)
        .with(array_including(hash_including('displayName' => 'Deployment Status')), any_args)
        .and_return([])

      parser.parse
      expect(parsed_deployment.status).to eq('Unknown')
    end
  end
end
