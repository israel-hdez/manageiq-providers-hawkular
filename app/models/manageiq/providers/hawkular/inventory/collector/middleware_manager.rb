require 'hawkular/hawkular_client'

module ManageIQ::Providers
  class Hawkular::Inventory::Collector::MiddlewareManager < ManagerRefresh::Inventory::Collector
    include ::Hawkular::ClientUtils

    def connection
      @connection ||= manager.connect
    end

    def resource_tree(resource_id)
      connection.inventory.resource_tree(resource_id)
    end

    def oss
      oss = []
      Hawkular::MiddlewareManager::SUPPORTED_VERSIONS.each do |version|
        oss.concat(resources_for("Platform Operating System #{version}"))
      end
      oss
    end

    def agents
      agents = []
      Hawkular::MiddlewareManager::SUPPORTED_VERSIONS.each do |version|
        agents.concat(resources_for("Hawkular Java Agent #{version}"))
      end
      agents
    end

    def eaps
      targeted? ? target_eaps : all_eaps
    end

    def domain_servers
      domains = []
      Hawkular::MiddlewareManager::SUPPORTED_VERSIONS.each do |version|
        domains.concat(resources_for("Domain WildFly Server #{version}"))
      end
      domains
    end

    def datasources
      return target_datasources if targeted?
      raise 'Not supported'
    end

    def deployments
      targeted? ? target_deployments : all_deployments
    end

    def subdeployments
      targeted? ? target_subdeployments : all_subdeployments
    end

    def messagings
      return target_messagings if targeted?
      raise 'Not supported'
    end

    def host_controllers
      host_controllers = []
      Hawkular::MiddlewareManager::SUPPORTED_VERSIONS.each do |version|
        host_controllers.concat(resources_for("Host Controller #{version}"))
      end
      host_controllers
    end

    def domains
      domains = []
      Hawkular::MiddlewareManager::SUPPORTED_VERSIONS.each do |version|
        domains.concat(resources_for("Domain Host #{version}"))
      end
      domains
    end

    def child_resources(resource_id, recursive = false)
      manager.child_resources(resource_id, recursive)
    end

    def raw_availability_data(metrics, time)
      connection.prometheus.query(:metrics => metrics, :time => time)
    rescue => err
      $mw_log.error(err)
      nil
    end

    def owning_server_for(resource_id)
      ancestor = connection.inventory.parent(resource_id)

      while ancestor && !server_types.include?(ancestor.type.id)
        ancestor = connection.inventory.parent(ancestor.id)
      end

      ancestor
    end

    def targeted?
      target.kind_of?(::ManagerRefresh::TargetCollection)
    end

    private

    def all_eaps
      return @eaps if @eaps

      @eaps = []
      Hawkular::MiddlewareManager::SUPPORTED_VERSIONS.each do |version|
        @eaps.concat(resources_for("WildFly Server #{version}"))
      end

      @eaps
    end

    def all_deployments
      return @deployments if @deployments

      @deployments = []
      Hawkular::MiddlewareManager::SUPPORTED_VERSIONS.each do |version|
        @deployments.concat(resources_for("Deployment #{version}"))
      end

      @deployments
    end

    def all_subdeployments
      return @subdeployments if @subdeployments

      @subdeployments = []
      Hawkular::MiddlewareManager::SUPPORTED_VERSIONS.each do |version|
        @subdeployments.concat(resources_for("SubDeployment #{version}"))
      end

      @subdeployments
    end

    def target_eaps
      @eaps ||= query_target_resources(:middleware_servers)
    end

    def target_datasources
      @datasources ||= query_target_resources(:middleware_datasources)
    end

    def target_deployments
      supported_subdeployments = ManageIQ::Providers::Hawkular::MiddlewareManager::SUPPORTED_VERSIONS.map do |version|
        "Deployment #{version}"
      end

      target_deployments_subdeployments.select { |d| supported_subdeployments.include?(d.type.id) }
    end

    def target_subdeployments
      supported_deployments = ManageIQ::Providers::Hawkular::MiddlewareManager::SUPPORTED_VERSIONS.map do |version|
        "SubDeployment #{version}"
      end

      target_deployments_subdeployments.select { |d| supported_deployments.include?(d.type.id) }
    end

    def target_deployments_subdeployments
      @deployments ||= query_target_resources(:middleware_deployments)
    end

    def target_messagings
      @messagings ||= query_target_resources(:middleware_messagings)
    end

    def query_target_resources(association)
      target.targets
            .select { |t| t.association == association }
            .map { |t| connection.inventory.resource(t.manager_ref) }
            .compact
    end

    def server_types
      return @server_types if @server_types

      types = []
      Hawkular::MiddlewareManager::SUPPORTED_VERSIONS.each do |version|
        types.concat(["Domain WildFly Server #{version}", "WildFly Server #{version}"])
      end

      @server_types = types
    end

    def resources_for(resource_type)
      connection.inventory.resources_for_type(resource_type)
    end
  end
end
