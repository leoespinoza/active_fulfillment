require 'cgi'

module ActiveFulfillment

  class DotcomDistributionService < Service

    include ActiveFulfillment::DotcomDistribution

    SIGNATURE_METHOD  = "MD5"

    # TODO: I don't know if this is the correct production endpoint
    BASE_URL = {
      test: 'https://cwa.dotcomdistribution.com/dcd_api_test/DCDAPIService.svc',
      live: 'http://cwa.dotcomdistribution.com/DCDAPIService.svc/dcd_api'
    }

    # Note that some of these endpoints like +fetch_stock_levels+ don't really
    # map all that nicely to their endpoint. We're inheriting these from the base Service class.
    #
    # The hash format here is:
    #   <action>: [<endpoint>, <class>]
    # where:
    #   action: self explanatory I think
    #   endpoint: DotCom's endpoint. for instance -> https://cwa.dotcomdistribution.com/dcd_api_test/DCDAPIService.svc/item
    #   class: The class that will parse our response

    SERVICE_ENDPOINTS = {
      post_item: ["item", PostItem],
      fulfillment: ["order", PostOrder],
      order_status: ["order", GetOrder],
      shipmethod: ["shipmethod", ShipMethod],
      fetch_stock_levels: ["inventory", Inventory],
      returns: ["return", Return],
      fetch_tracking_data: ["shipment", Shipment],
      adjustment: ["adjustment", Adjustment],
      purchase_order: ["purchase_order", PurchaseOrder],
      item_summary: ["item_summary", ItemSummary],
      inventory_by_status: ["inventory_by_status"],
      inventory_snapshot: ["inventory_snapshot", InventorySnapshot],
      stockstatus: ["stockstatus"],
      receipt: ["receipt"],
      nonpo_receipt: ["nonpo_receipt"],
      backorder: ["backorder"],
      billing_summary: ["billingsummary"],
      billing_detail: ["billingdetail"],
      receiving_sla: ["receiving_sla"]
    }

    # Many of these get requests are handled by +method_missing+.
    #
    #  Example:
    #    service = ActiveFulfillment::DotcomDistributionService.new({username: 'test', password: 'test'})
    #    # or      ActiveFulfillment::Base.service('dotcom_distribution').new({username: 'test', password: 'test'})
    #    service.receipt({fromReceiptDate: '2010-10-01', toReceiptDate: '2010-10-02'})
    #
    def method_missing(method_sym, *arguments, &block)
      if SERVICE_ENDPOINTS.keys.include?(method_sym)
        self.send(:commit, method_sym, :get, arguments.first)
      else
        super
      end
    end

    def initialize(options = {})
      requires!(options, :username, :password)
      super
    end

    def sign(uri)
      digest = OpenSSL::Digest.new(SIGNATURE_METHOD)
      hmac = Base64.encode64(OpenSSL::HMAC.digest(digest, @options[:password], uri)).chomp
      @options[:username] + ":" + hmac
    end

    def build_headers(uri)
      {
        'Authorization' => sign(uri),
        'Content-Type' => 'text/xml; charset="utf-8"'
      }
    end

    def fulfill(options = {})
      commit :fulfillment, :post, SERVICE_ENDPOINTS[:fulfillment][1].new(options)
    end

    # Tell Dotcom that stock is being sent to their warehouse.
    def purchase_order(options = {})
      commit :purchase_order, :post, SERVICE_ENDPOINTS[:purchase_order][1].new(options)
    end

    # +post_item+ and +purchase_order+ are used to let Dotcom know
    # about our products / SKUs.  If you attempt to place an order
    # with a SKU that Dotcom is not aware of, "you're gonna have a bad day!"
    def post_item(options = {})
      commit :post_item, :post, SERVICE_ENDPOINTS[:fulfillment][1].new(options)
    end

    def fetch_stock_levels(options = {})
      commit :fetch_stock_levels, options
    end

    # This is a call to /shipment, we're implementing a method
    # from the base class.  Note that the method
    # definition isn't the same. That is, Dotcom's API does not
    # make use of order_ids. Not sure what to do with this yet.
    # TODO: do something with order_ids
    def fetch_tracking_data(order_ids, options = {})
      commit :fetch_tracking_data, options
    end

    def test_mode?
      true
    end

    private

    def commit(action, verb = :get, data = nil)
      url = (test? ? BASE_URL[:test] : BASE_URL[:live]) + "/" + SERVICE_ENDPOINTS[action][0]
      if verb == :get
        if data
          params = data.collect { |k,v| "#{k}=#{CGI.escape(v)}" }
          url += "?#{params.join('&')}"
        end
        response = ssl_get(url, build_headers(url))
      else
        # Because all our classes mixin ActiveModel::Validations
        # we can validate our request in this manner which will
        # add to the errors array
        if data && data.valid?
          response = ssl_post(url, data.to_xml, build_headers(url))
        else
          # TODO: Not sure what to do with the second argument +message+
          #  in this response. The relevant data is in +data+. I don't know if
          #  I would remove it for fear of breaking functionality.
          return Response.new(false, '', {data: data.errors})
        end
      end

      parse_response(action, response)
    end

    def parse_response(action, xml)
      if SERVICE_ENDPOINTS[action].size == 2
        klass = SERVICE_ENDPOINTS[action][1]
        klass.response_from_xml(xml)
      else
        begin
          klass = ("ActiveFulfillment::DotcomDistribution::" + (action.to_s.classify)).constantize
          if klass.respond_to?(:response_from_xml)
            klass.response_from_xml(xml)
          else
            raise "response_from_xml not implemented in #{klass}"
          end
        rescue NameError => e
          raise ArgumentError, "Unknown action #{action}"
        end
      end
    end

  end
end
