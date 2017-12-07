module ManageIQ::Providers
  class Hawkular::Inventory::Persister::MiddlewareTargeted < ManagerRefresh::Inventory::Persister
    include ManagerRefresh::Inventory::MiddlewareManager

    alias target_collection target
    delegate :targets, :to => :target_collection

    def initialize_inventory_collections
      add_servers_collection
    end

    private

    def add_servers_collection
      add_inventory_collection(
        :model_class                 => self.class.provider_module::MiddlewareManager::MiddlewareServer,
        :targeted                    => true,
        :manager_uuids               => touched_servers_refs,
        :association                 => :middleware_servers,
        :inventory_object_attributes => %i(type type_path hostname product lives_on_id lives_on_type
                                           middleware_server_group).concat(COMMON_ATTRIBUTES),
        :builder_params              => { :ext_management_system => ->(persister) { persister.manager } }
      )
    end

    def touched_servers_refs
      targets.map(&:manager_ref)
    end
  end
end
