#!/usr/bin/env ruby
# frozen_string_literal: true

# Revokes the Apple Development certificate this CI run created.
#
# `xcodebuild archive` signs with a development identity, and -allowProvisioningUpdates mints a
# brand new one through the API key on every runner, because a fresh runner keychain has none.
# Apple caps the number of certificates per account, so after a handful of uploads every archive
# fails with "Your account has reached the maximum number of certificates". Distribution signing is
# unaffected: that certificate is cloud managed and its key comes back from Apple on every run.
#
# Only certificates that are in *this* runner's keychain are revoked (matched on the certificate
# itself, not on a name), so a certificate someone uses on their own Mac can never be hit. Failures
# are warnings, not errors: the build is already archived and uploaded by the time this runs.
#
# Environment: ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID (same values the xcodebuild steps use).

require 'base64'
require 'json'
require 'net/http'
require 'openssl'
require 'uri'

API = 'https://api.appstoreconnect.apple.com'
DEVELOPMENT_CN = 'Apple Development:'

# The whole point is to clean up throwaway runners. On a real Mac the certificate in the keychain
# is the one the person develops with.
unless ENV['CI'] == 'true' || ENV['ALLOW_LOCAL_REVOKE'] == '1'
  abort 'Refusing to revoke certificates outside CI. Set ALLOW_LOCAL_REVOKE=1 to override.'
end

def warn_off(message)
  puts "::warning::#{message}"
end

def stripped(serial)
  serial.to_s.gsub(/[\s:]/, '').upcase.sub(/\A0+(?=.)/, '')
end

# The Apple Development certificates in the runner's keychains.
def local_development_certificates
  pem = `security find-certificate -a -p 2>/dev/null`
  pem.scan(/-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----/m).each_with_object([]) do |block, found|
    begin
      certificate = OpenSSL::X509::Certificate.new(block)
    rescue OpenSSL::X509::CertificateError
      next
    end
    common_name = certificate.subject.to_a.find { |name, _, _| name == 'CN' }
    common_name = common_name && common_name[1].to_s
    next unless common_name && common_name.start_with?(DEVELOPMENT_CN)

    found << certificate
  end
end

# The account's copy of a certificate the runner holds. Matched on the DER, with the serial number
# as a fallback in case Apple ever stops handing out certificateContent.
def account_copy(listed, certificate)
  listed.find do |candidate|
    attributes = candidate['attributes'] || {}
    next false unless attributes['certificateType'].to_s.include?('DEVELOPMENT')

    content = attributes['certificateContent'].to_s
    if content.empty?
      serial = stripped(attributes['serialNumber'])
      serial == stripped(certificate.serial.to_s(16)) || serial == certificate.serial.to_s(10)
    else
      Base64.decode64(content) == certificate.to_der
    end
  end
end

def bearer_token
  key_path = ENV.fetch('ASC_KEY_PATH')
  key_id = ENV.fetch('ASC_KEY_ID')
  issuer_id = ENV.fetch('ASC_ISSUER_ID')
  now = Time.now.to_i
  segments = [
    { alg: 'ES256', kid: key_id, typ: 'JWT' },
    { iss: issuer_id, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' }
  ].map { |segment| Base64.urlsafe_encode64(JSON.generate(segment), padding: false) }
  signing_input = segments.join('.')

  key = OpenSSL::PKey::EC.new(File.read(key_path))
  der = key.sign(OpenSSL::Digest.new('SHA256'), signing_input)
  # ES256 wants the raw r||s pair, OpenSSL signs to a DER sequence of two integers.
  raw = OpenSSL::ASN1.decode(der).value.map { |value| value.value.to_s(16).rjust(64, '0') }.join
  "#{signing_input}.#{Base64.urlsafe_encode64([raw].pack('H*'), padding: false)}"
end

def request(verb, url, token)
  uri = URI(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = 15
  http.read_timeout = 30
  http.request(verb.new(uri).tap { |req| req['Authorization'] = "Bearer #{token}" })
end

def certificates(token)
  url = "#{API}/v1/certificates?limit=200"
  all = []
  while url
    response = request(Net::HTTP::Get, url, token)
    unless response.is_a?(Net::HTTPSuccess)
      warn_off("Could not list certificates (HTTP #{response.code}): #{response.body.to_s[0, 300]}")
      return nil
    end
    body = JSON.parse(response.body)
    all.concat(body['data'] || [])
    url = body.fetch('links', {})['next']
  end
  all
end

mine = local_development_certificates
if mine.empty?
  puts 'No Apple Development certificate in the runner keychain, nothing to revoke.'
  exit 0
end

token = begin
  bearer_token
rescue StandardError => e
  warn_off("Could not build an App Store Connect token: #{e.class}: #{e.message}")
  exit 0
end

listed = certificates(token)
exit 0 if listed.nil?

revoked = 0
mine.each do |certificate|
  serial = stripped(certificate.serial.to_s(16))
  match = account_copy(listed, certificate)
  unless match
    puts "Certificate #{serial} is not in the account any more, skipping."
    next
  end

  response = request(Net::HTTP::Delete, "#{API}/v1/certificates/#{match['id']}", token)
  if response.is_a?(Net::HTTPSuccess)
    revoked += 1
    puts "Revoked development certificate #{serial}."
  else
    warn_off("Could not revoke certificate #{serial} (HTTP #{response.code}): #{response.body.to_s[0, 300]}")
  end
end

development = listed.count { |c| (c['attributes'] || {})['certificateType'].to_s.include?('DEVELOPMENT') }
remaining = development - revoked
puts "Revoked #{revoked} certificate(s); #{remaining} development certificate(s) left in the account."
