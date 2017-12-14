module ManageIQ::Providers
  class Hawkular::Inventory::Persister::MiddlewareTargeted < ManagerRefresh::Inventory::Persister
    include ManagerRefresh::Inventory::MiddlewareManager

    alias target_collection target
    delegate :targets, :to => :target_collection

    def initialize_inventory_collections
      add_domains_collection
      add_server_groups_collection
      add_servers_collection
      add_datasources_collection
      add_deployments_collection
      add_messagings_collection
    end

    private

    def add_domains_collection
      add_inventory_collection(
        :model_class                 => self.class.provider_module::MiddlewareManager::MiddlewareDomain,
        :targeted                    => true,
        :manager_uuids               => touched_refs(:middleware_domains),
        :strategy                    => :local_db_find_missing_references,
        :association                 => :middleware_domains,
        :inventory_object_attributes => %i(type_path).concat(COMMON_ATTRIBUTES),
        :builder_params              => { :ext_management_system => ->(persister) { persister.manager } }
      )
    end

    def add_server_groups_collection
      add_inventory_collection(
        :model_class                  => self.class.provider_module::MiddlewareManager::MiddlewareServerGroup,
        :targeted                     => true,
        :targeted_arel                => lambda do |collection|
          manager_uuids = collection.parent_inventory_collections
                                    .each_with_object(Set.new) { |parent, obj| obj.merge(parent.manager_uuids) }
                                    .to_a
          collection.full_collection_for_comparison.where(:middleware_domains => { :ems_ref => manager_uuids })
        end,
        :association                  => :middleware_server_groups,
        :parent_inventory_collections => [:middleware_domains],
        :inventory_object_attributes  => %i(type_path profile middleware_domain).concat(COMMON_ATTRIBUTES)
      )
    end

    def add_servers_collection
      add_inventory_collection(
        :model_class                 => self.class.provider_module::MiddlewareManager::MiddlewareServer,
        :targeted                    => true,
        :manager_uuids               => touched_refs(:middleware_servers),
        :strategy                    => :local_db_find_missing_references,
        :association                 => :middleware_servers,
        :inventory_object_attributes => %i(type type_path hostname product lives_on_id lives_on_type
                                           middleware_server_group).concat(COMMON_ATTRIBUTES),
        :builder_params              => { :ext_management_system => ->(persister) { persister.manager } }
      )
    end

    def add_datasources_collection
      add_inventory_collection(
        :model_class                 => self.class.provider_module::MiddlewareManager::MiddlewareDatasource,
        :targeted                    => true,
        :manager_uuids               => touched_refs(:middleware_datasources),
        :strategy                    => :local_db_find_missing_references,
        :association                 => :middleware_datasources,
        :inventory_object_attributes => %i(middleware_server).concat(COMMON_ATTRIBUTES),
        :builder_params              => { :ext_management_system => ->(persister) { persister.manager } }
      )
    end

    def add_deployments_collection
      add_inventory_collection(
        :model_class                 => self.class.provider_module::MiddlewareManager::MiddlewareDeployment,
        :targeted                    => true,
        :manager_uuids               => touched_refs(:middleware_deployments),
        :strategy                    => :local_db_find_missing_references,
        :association                 => :middleware_deployments,
        :inventory_object_attributes => %i(middleware_server middleware_server_group status).concat(COMMON_ATTRIBUTES),
        :builder_params              => { :ext_management_system => ->(persister) { persister.manager } }
      )
    end

    def add_messagings_collection
      add_inventory_collection(
        :model_class                 => self.class.provider_module::MiddlewareManager::MiddlewareMessaging,
        :targeted                    => true,
        :manager_uuids               => touched_refs(:middleware_messagings),
        :strategy                    => :local_db_find_missing_references,
        :association                 => :middleware_messagings,
        :inventory_object_attributes => %i(middleware_server messaging_type).concat(COMMON_ATTRIBUTES),
        :builder_params              => { :ext_management_system => ->(persister) { persister.manager } }
      )
    end

    def touched_refs(association)
      targets
        .select { |t| t.association == association }
        .map(&:manager_ref)
    end
  end
end
