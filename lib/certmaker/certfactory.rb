module CertMaker
  class CertificateFactory

    def self.ca
      root_key = OpenSSL::PKey::RSA.new 2048
      root_ca = OpenSSL::X509::Certificate.new
      root_ca.version = 2
      root_ca.serial = 1
      root_ca.subject = OpenSSL::X509::Name.parse "C=US, ST=California, L=San Francisco, O=GoatCo, CN=#{CertMaker::CONFIG["commonname"]}"
      root_ca.issuer = root_ca.subject
      root_ca.public_key = root_key.public_key
      root_ca.not_before = Time.now
      root_ca.not_after = root_ca.not_before + 365*24*60*60
      ef = OpenSSL::X509::ExtensionFactory.new
      ef.subject_certificate = root_ca
      ef.issuer_certificate = root_ca
      root_ca.add_extension(ef.create_extension("basicConstraints","CA:TRUE", true))
      root_ca.add_extension(ef.create_extension("keyUsage","keyCertSign, cRLSign", true))
      root_ca.add_extension(ef.create_extension("subjectKeyIdentifier","hash", false))
      root_ca.add_extension(ef.create_extension("authorityKeyIdentifier","keyid:always", false))
      root_ca.sign(root_key, OpenSSL::Digest::SHA256.new)
    end

    attr_accessor :ca, :ca_key
    attr_accessor :subject
    attr_accessor :not_before, :not_after
    attr_accessor :extensions
    attr_accessor :key_type
    attr_accessor :key_size
    attr_accessor :signing_alg

    def initialize
      self.ca = :self
      self.extensions = []
      self.key_type = OpenSSL::PKey::RSA
      self.key_size = 2048
      self.signing_alg = :SHA1
    end

    # Returns an array containing the certificate and associated key with the configured attributes, plus with the
    # overridden attrs.
    def create(args={})

      # Make a key
      nk = self.key_type.new self.key_size

      # Certificate basics
      nc = OpenSSL::X509::Certificate.new
      nc.version = 2
      nc.serial = 1
      nc.subject = OpenSSL::X509::Name.parse(args.fetch(:subject, self.subject))
      nc.public_key = nk.public_key
      nc.not_before = args.fetch(:not_before,self.not_before)
      nc.not_after = args.fetch(:not_after,self.not_after)

      # Prep for extensions
      ef = OpenSSL::X509::ExtensionFactory.new
      ef.subject_certificate = nc

      self.ca = args.fetch(:ca,self.ca)
      # Issuer handling
      if self.ca == :self
        nc.issuer = nc.subject
        ef.issuer_certificate = nc
        signing_key = nk
      else
        nc.issuer = self.ca.subject
        ef.issuer_certificate = self.ca
        signing_key = self.ca_key
      end

      # filter out blocked extension patterns
      exts = self.extensions
      if args.fetch(:blockextension,false)
        args[:blockextension].each do |badext|
          exts = exts.select { |ext| ext.scan(badext).empty? }
        end
      end
      # add any additional extensions
      exts.concat args.fetch(:extensions,[])

      # Add the extensions
      exts.each do |ext|
        nc.add_extension(ef.create_ext_from_string(ext))
      end

      # Look up the signing algorithm. If it is set to a symbol or string,
      # we'll be able to look up a class. Otherwise we assume that the current
      # signing_alg is a class symbol.
      sa = args.fetch(:signing_alg, self.signing_alg)
      begin
        sa = OpenSSL::Digest.const_get(sa)
      rescue TypeError
      end

      nc.sign(signing_key, sa.new)

      return [nc, nk]
    end

  end

end
