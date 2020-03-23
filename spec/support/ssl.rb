# encoding: utf-8
require "stud/temporary"

module RelpTest

  class Certicate
    require 'flores/pki'

    attr_reader :ssl_key, :ssl_cert

    def initialize
      certificate, key = Flores::PKI.generate
      @ssl_cert = Stud::Temporary.pathname("ssl_certificate")
      @ssl_key = Stud::Temporary.pathname("ssl_key")
      IO.write(@ssl_cert, certificate.to_pem)
      IO.write(@ssl_key, key.to_pem)
    end
  end

  class << self
    def certificate
      Certicate.new
    end

    def random_port
      rand(2000..10000)
    end
  end

end
