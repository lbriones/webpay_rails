module WebpayRails
  module Base
    extend ActiveSupport::Concern

    module ClassMethods
      def webpay_rails(options)
        class_attribute :commerce_code, :webpay_cert, :environment,
                        :soap_normal, :soap_nullify, instance_accessor: false

        self.commerce_code = options[:commerce_code]
        self.webpay_cert = OpenSSL::X509::Certificate.new(options[:webpay_cert])
        self.environment = options[:environment]

        self.soap_normal = WebpayRails::SoapNormal.new(options)
        self.soap_nullify = WebpayRails::SoapNullify.new(options)
      end

      def init_transaction(amount, buy_order, session_id, return_url, final_url)
        begin
          response = soap_normal.init_transaction(commerce_code, amount, buy_order,
                                                  session_id, return_url, final_url)
        rescue StandardError
          raise WebpayRails::FailedInitTransaction
        end

        unless WebpayRails::Verifier.verify(response, webpay_cert)
          raise WebpayRails::InvalidCertificate
        end

        WebpayRails::Transaction.new(Nokogiri::HTML(response.to_s))
      end

      def transaction_result(token)
        begin
          response = soap_normal.get_transaction_result(token)
        rescue StandardError
          raise WebpayRails::FailedGetResult
        end

        raise WebpayRails::InvalidResultResponse if response.blank?

        acknowledge_transaction(token)

        WebpayRails::TransactionResult.new(Nokogiri::HTML(response.to_s))
      end

      def acknowledge_transaction(token)
        begin
          response = soap_normal.acknowledge_transaction(token)
        rescue StandardError
          raise WebpayRails::FailedAcknowledgeTransaction
        end

        raise WebpayRails::InvalidAcknowledgeResponse if response.blank?
      end

      def nullify(authorization_code, authorize_amount, buy_order, nullify_amount)
        begin
          response = soap_nullify.nullify(authorization_code, authorize_amount,
                                          buy_order, commerce_code, nullify_amount)
        rescue StandardError
          raise WebpayRails::FailedNullify
        end

        unless WebpayRails::Verifier.verify(response, webpay_cert)
          raise WebpayRails::InvalidCertificate
        end

        WebpayRails::Nullified.new(Nokogiri::HTML(response.to_s))
      end
    end
  end
end
