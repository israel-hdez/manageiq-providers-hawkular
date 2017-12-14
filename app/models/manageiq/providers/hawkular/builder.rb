module ManageIQ::Providers::Hawkular
  class Builder
    def self.build_inventory(ems, target)
      case target
      when ::ManageIQ::Providers::MiddlewareManager
        collector = Inventory::Collector::MiddlewareManager.new(ems, target)
        persister = Inventory::Persister::MiddlewareManager.new(ems, target)
        parser = [
          Inventory::Parser::MiddlewareServers.new,
          Inventory::Parser::MiddlewareDomains.new,
          Inventory::Parser::MiddlewareDomainServers.new,
          Inventory::Parser::MiddlewareServerEntities.new
        ]
      when ::ManagerRefresh::TargetCollection
        collector = Inventory::Collector::MiddlewareManager.new(ems, target)
        persister = Inventory::Persister::MiddlewareTargeted.new(ems, target)
        parser = []
        parser << Inventory::Parser::MiddlewareServers.new if target.targets.any? { |t| t.association == :middleware_servers }
        parser << Inventory::Parser::MiddlewareDomains.new if target.targets.any? { |t| t.association == :middleware_domains }
        parser << Inventory::Parser::MiddlewareServerEntities.new if target.targets.any? do |t|
          %i(middleware_datasources middleware_deployments middleware_messagings).any? { |e| e == t.association }
        end
      when ::ManageIQ::Providers::Hawkular::Inventory::AvailabilityUpdates
        collector = Inventory::Collector::AvailabilityUpdates.new(ems, target)
        persister = Inventory::Persister::AvailabilityUpdates.new(ems, target)
        parser = Inventory::Parser::AvailabilityUpdates.new
      end

      ManagerRefresh::Inventory.new(persister, collector, parser)
    end
  end
end
