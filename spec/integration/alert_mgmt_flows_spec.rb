require_relative '../models/manageiq/providers/hawkular/middleware_manager/hawkular_helper'

describe "Alert mgmt flow:" do
  vcr_cassette_prefix = 'integration/alert_mgmt_flows/'

  let(:alert) { FactoryGirl.create(:miq_alert_mw_heap_used, :id => 201) }

  subject!(:ems) do
    ems = ems_hawkular_fixture
    ems.guid = "def"
    ems.save!
    ems
  end

  before do
    MiqRegion.seed
    MiqRegion.my_region.guid = "abc"
    MiqRegion.my_region.save!
    @hwclient = nil
  end

  def ems_class
    ManageIQ::Providers::Hawkular::MiddlewareManager
  end

  def alert_manager_class
    ManageIQ::Providers::Hawkular::MiddlewareManager::AlertManager
  end

  def hawkular_client
    @hclient ||= Hawkular::Client.new(
      :credentials => {
        :username => test_userid,
        :password => test_password
      },
      :options     => { :tenant => 'hawkular' },
      :entrypoint  => URI::HTTP.build(:host => test_hostname, :port => test_port)
    )
  end

  def alerts_client
    hawkular_client.alerts
  end

  describe "alerts" do
    it "CRUD flow is propagated to Hawkular" do
      VCR.use_cassette("#{vcr_cassette_prefix}alerts_crud_flow",
                       :allow_unused_http_interactions => true,
                       :match_requests_on              => [:method, :uri],
                       :decode_compressed_response     => true) do # , :record => :new_episodes) do

        # STAGE 1
        # Notify to EMS an alert was created
        ems_class.update_alert(:operation => :new, :alert => alert)

        # Verify a trigger is in Hawkular
        hawkular_alert_id = alert_manager_class.build_hawkular_trigger_id(:ems => ems, :alert => alert)
        trigger = alerts_client.list_triggers(hawkular_alert_id)
        expect(trigger.count).to eq(1)

        # STAGE 2
        # Update alert condition and notify to EMS
        alert.expression[:options][:value_mw_greater_than] = 50
        alert.save
        ems_class.update_alert(:operation => :update, :alert => alert)

        # Verify trigger condition was updated in Hawkular
        trigger = alerts_client.get_single_trigger(hawkular_alert_id, true)
        expect(trigger.conditions.count).to eq(1)
        expect trigger.conditions[0].expression.include?('> 0.5')

        # STAGE 3
        # Delete alert and notify to EMS
        alert.destroy
        ems_class.update_alert(:operation => :delete, :alert => alert)

        # Verify trigger has been deleted in Hawkular
        trigger = alerts_client.list_triggers(hawkular_alert_id)
        expect(trigger.count).to be_zero
      end
    end

    it "should fallback to old alerts id format if an alert with the new id does not exist in Hawkular" do
      VCR.use_cassette("#{vcr_cassette_prefix}fallback_to_old_ids_format",
                       :allow_unused_http_interactions => true,
                       :match_requests_on              => [:method, :uri],
                       :decode_compressed_response     => true) do # , :record => :new_episodes) do

        # Temporarily mock construction of id
        allow(alert_manager_class).to receive(:build_hawkular_trigger_id).and_return("MiQ-#{alert.id}")

        # Create alert in Hawkular with old id format
        ems_class.update_alert(:operation => :new, :alert => alert)

        trigger = alerts_client.list_triggers("MiQ-#{alert.id}")
        expect(trigger.count).to eq(1)

        # Remove mock
        allow(alert_manager_class).to receive(:build_hawkular_trigger_id).and_call_original
        expect(alert_manager_class.build_hawkular_trigger_id(:ems => ems, :alert => { :id => 1 })).to include('ems') # just to check mock is removed

        # Delete alert and notify to EMS
        alert.destroy
        ems_class.update_alert(:operation => :delete, :alert => alert)

        # Verify trigger has been deleted in Hawkular
        trigger = alerts_client.list_triggers("MiQ-#{alert.id}")
        expect(trigger.count).to be_zero
      end
    end
  end

  describe "alert profiles" do
    # This context assumes that there is a wildfly server
    # in domain mode (with the shipped sample domain configs)
    # connected to hawkular services. This means that hawkular
    # should have registered the relevant inventory entities.

    let(:profile) { FactoryGirl.create(:miq_alert_set_mw, :id => 202) }
    let(:server_one) do
      s1 = ManageIQ::Providers::Hawkular::MiddlewareManager::
        MiddlewareServer.find_by(:name => 'server-one')
      s1.update_column(:id, 400)
      s1.reload
    end

    it "without assigned servers shouldn't create members in Hawkular when adding alerts" do
      VCR.use_cassette("#{vcr_cassette_prefix}add_alerts_to_profile_with_no_servers",
                       :allow_unused_http_interactions => true,
                       :match_requests_on              => [:method, VCR.request_matchers.uri_without_params(:start)],
                       :record                         => :new_episodes,
                       :decode_compressed_response     => true) do # , :record => :new_episodes) do
        # Setup
        EmsRefresh.refresh(ems)
        ems.reload
        ems_class.update_alert(:operation => :new, :alert => alert)
        alert.reload

        profile.add_member(alert)

        ems_class.update_alert_profile(
          :operation       => :update_alerts,
          :profile_id      => profile.id,
          :old_alerts      => [],
          :new_alerts      => [alert.id],
          :old_assignments => [],
          :new_assignments => nil
        )

        # Verify
        triggers = alerts_client.list_triggers
        expect(triggers.select { |t| t.type == 'MEMBER' }.count).to be_zero

        ems_class.update_alert(:operation => :delete, :alert => alert)
      end
    end

    it "without alerts shouldn't create members in Hawkular when adding servers" do
      VCR.use_cassette("#{vcr_cassette_prefix}add_servers_to_profile_with_no_alerts",
                       :allow_unused_http_interactions => true,
                       :record                         => :new_episodes,
                       :match_requests_on              => [:method, VCR.request_matchers.uri_without_params(:start)],
                       :decode_compressed_response     => true) do # , :record => :new_episodes) do
        # Setup
        EmsRefresh.refresh(ems)
        ems.reload
        ems_class.update_alert(:operation => :new, :alert => alert)
        alert.reload

        profile.assign_to_objects([server_one])

        ems_class.update_alert_profile(
          :operation       => :update_assignments,
          :profile_id      => profile.id,
          :old_alerts      => [],
          :new_alerts      => [],
          :old_assignments => [],
          :new_assignments => {"objects" => [server_one.id], "assign_to" => server_one.class}
        )

        # Verify
        triggers = alerts_client.list_triggers
        expect(triggers.select { |t| t.type == 'MEMBER' }.count).to be_zero

        ems_class.update_alert(:operation => :delete, :alert => alert)
      end
    end

    it "with alerts should update members in Hawkular when assigning and unassigning a server" do
      VCR.use_cassette("#{vcr_cassette_prefix}assign_unassign_server_to_profile_with_alerts",
                       :allow_unused_http_interactions => true,
                       :record                         => :new_episodes,
                       :match_requests_on              => [:method, VCR.request_matchers.uri_without_params(:start)],
                       :decode_compressed_response     => true) do # , :record => :new_episodes) do
        # Setup
        EmsRefresh.refresh(ems)
        ems.reload
        ems_class.update_alert(:operation => :new, :alert => alert)
        alert.reload

        profile.add_member(alert)

        # Add the server
        profile.assign_to_objects([server_one])

        ems_class.update_alert_profile(
          :operation       => :update_assignments,
          :profile_id      => profile.id,
          :old_alerts      => [alert.id],
          :new_alerts      => [],
          :old_assignments => [],
          :new_assignments => {"objects" => [server_one.id], "assign_to" => server_one.class}
        )

        # Verify
        triggers = alerts_client.list_triggers
        expect(triggers.select { |t| t.type == 'MEMBER' }.count).to eq(1)

        # Remove server
        profile.remove_all_assigned_tos

        ems_class.update_alert_profile(
          :operation       => :update_assignments,
          :profile_id      => profile.id,
          :old_alerts      => [alert.id],
          :new_alerts      => [],
          :old_assignments => [server_one],
          :new_assignments => nil
        )

        # Verify
        triggers = alerts_client.list_triggers
        expect(triggers.select { |t| t.type == 'MEMBER' }.count).to be_zero

        ems_class.update_alert(:operation => :delete, :alert => alert)
      end
    end

    it "with servers should update members in Hawkular when assigning and unassigning an alert" do
      VCR.use_cassette("#{vcr_cassette_prefix}assign_unassign_alert_to_profile_with_servers",
                       :allow_unused_http_interactions => true,
                       :record                         => :new_episodes,
                       :match_requests_on              => [:method, VCR.request_matchers.uri_without_params(:start)],
                       :decode_compressed_response     => true) do # , :record => :new_episodes) do
        # Setup
        EmsRefresh.refresh(ems)
        ems.reload
        ems_class.update_alert(:operation => :new, :alert => alert)
        alert.reload

        profile.assign_to_objects([server_one])

        # Add the alert
        profile.add_member(alert)
        ems_class.update_alert_profile(
          :operation       => :update_alerts,
          :profile_id      => profile.id,
          :old_alerts      => [],
          :new_alerts      => [alert.id],
          :old_assignments => [server_one],
          :new_assignments => nil
        )

        # Verify
        triggers = alerts_client.list_triggers
        expect(triggers.select { |t| t.type == 'MEMBER' }.count).to eq(1)

        # Remove the alert
        profile.remove_member(alert)

        ems_class.update_alert_profile(
          :operation       => :update_alerts,
          :profile_id      => profile.id,
          :old_alerts      => [alert.id],
          :new_alerts      => [],
          :old_assignments => [server_one],
          :new_assignments => nil
        )

        # Verify
        triggers = alerts_client.list_triggers
        expect(triggers.select { |t| t.type == 'MEMBER' }.count).to be_zero

        ems_class.update_alert(:operation => :delete, :alert => alert)
      end
    end
  end
end
