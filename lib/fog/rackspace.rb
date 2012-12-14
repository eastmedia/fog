require 'fog/core'

module Fog
  module Rackspace
    extend Fog::Provider

    module Errors
      class ServiceError < Fog::Errors::Error
        attr_reader :response_data, :status_code

        def to_s
          status_code ? "[HTTP #{status_code}] #{super}" : super
        end

        def self.slurp(error)
          data = nil
          message = nil
          status_code = nil

          if error.response
            status_code = error.response.status
            unless error.response.body.empty?
              data = Fog::JSON.decode(error.response.body)
              message = data.values.first ? data.values.first['message'] : data['message']
            end
          end

          new_error = super(error, message)
          new_error.instance_variable_set(:@response_data, data)
          new_error.instance_variable_set(:@status_code, status_code)
          new_error
        end
      end

      class InternalServerError < ServiceError; end
      class Conflict < ServiceError; end
      class NotFound < ServiceError; end
      class ServiceUnavailable < ServiceError; end

      class BadRequest < ServiceError
        #TODO - Need to find a better way to print out these validation errors when they are thrown
        attr_reader :validation_errors

        def self.slurp(error)
          new_error = super(error)
          unless new_error.response_data.nil? or new_error.response_data['badRequest'].nil?
            new_error.instance_variable_set(:@validation_errors, new_error.response_data['badRequest']['validationErrors'])
          end
          new_error
        end
      end
    end

    service(:block_storage,    'rackspace/block_storage',     'BlockStorage')
    service(:cdn,              'rackspace/cdn',               'CDN')
    service(:compute,          'rackspace/compute',           'Compute')
    service(:compute_v2,       'rackspace/compute_v2',        'Compute v2')
    service(:dns,              'rackspace/dns',               'DNS')
    service(:storage,          'rackspace/storage',           'Storage')
    service(:load_balancers,   'rackspace/load_balancers',    'LoadBalancers')
    service(:identity,         'rackspace/identity',          'Identity')
    service(:databases,        'rackspace/databases',         'Databases')

    def self.authenticate(options, connection_options = {})
      rackspace_auth_url = options[:rackspace_auth_url] || "identity.api.rackspacecloud.com"

      url = rackspace_auth_url.match(/^https?:/) ? rackspace_auth_url : 'https://' + rackspace_auth_url
      uri = URI.parse(url)

      connection = Fog::Connection.new(url, false, connection_options)
      @rackspace_password  = options[:rackspace_password]
      @rackspace_username = options[:rackspace_username]

      response = connection.request({
        :expects  => [200, 204],
        :body     => "{\"auth\":{\"passwordCredentials\":{\"username\":\"#{@rackspace_username}\",\"password\":\"#{@rackspace_password}\"}}}",
        :headers  => {
          'Content-type'  => "application/json"
        },
        :host     => uri.host,
        :method   => 'GET',
        :path     =>  (uri.path and not uri.path.empty?) ? uri.path : 'v2.0/tokens'
      })

      json_response = JSON.decode(response.body)["access"]
      endpoints     = json_response["serviceCatalog"].detect { |x| x["name"] == "cloudFiles"}["endpoints"]
      storage_url   = endpoints.detect { |endpoint| endpoint["region"] == "ORD" }["publicURL"]

      {"X-Auth-Token" => json_response["token"]["id"], "X-Storage-Url" => storage_url}
    end

    # CGI.escape, but without special treatment on spaces
    def self.escape(str,extra_exclude_chars = '')
      str.gsub(/([^a-zA-Z0-9_.-#{extra_exclude_chars}]+)/) do
        '%' + $1.unpack('H2' * $1.bytesize).join('%').upcase
      end
    end
  end
end
