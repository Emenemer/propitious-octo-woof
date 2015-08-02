if ENV["CODECLIMATE_REPO_TOKEN"]
  require "codeclimate-test-reporter"
  CodeClimate::TestReporter.start
end

# This file is copied to spec/ when you run 'rails generate rspec:install'
ENV['RAILS_ENV'] = 'test'
require_relative 'spec_helper'
require File.expand_path('../../config/environment', __FILE__)
require 'rspec/rails'
require 'webmock/rspec'
require 'capybara/rspec'
require 'capybara-screenshot/rspec'
require 'capybara/poltergeist'
require 'capybara/email/rspec'
require 'webrick/https'
require 'rack/handler/webrick'

# Add additional requires below this line. Rails is not loaded until this point!

# Requires supporting ruby files with custom matchers and macros, etc, in
# spec/support/ and its subdirectories. Files matching `spec/**/*_spec.rb` are
# run as spec files by default. This means that files in spec/support that end
# in _spec.rb will both be required and run as specs, causing the specs to be
# run twice. It is recommended that you do not name files matching this glob to
# end with _spec.rb. You can configure this pattern with the --pattern
# option on the command line or in ~/.rspec, .rspec or `.rspec-local`.
#
# The following line is provided for convenience purposes. It has the downside
# of increasing the boot-up time by auto-requiring all files in the support
# directory. Alternatively, in the individual `*_spec.rb` files, manually
# require only the support files necessary.
#
Dir[Rails.root.join('spec/support/**/*.rb')].each { |f| require f }

# Checks for pending migrations before tests are run.
# If you are not using ActiveRecord, you can remove this line.
ActiveRecord::Migration.maintain_test_schema!

# module Capybara
#   class Server
#     def responsive?
#       return false if @server_thread && @server_thread.join(0)
#
#       http = Net::HTTP.new(host, @port)
#       http.use_ssl = true
#       http.verify_mode = OpenSSL::SSL::VERIFY_NONE
#       res = http.get('/__identify__')
#
#       if res.is_a?(Net::HTTPSuccess) or res.is_a?(Net::HTTPRedirection)
#         return res.body == @app.object_id.to_s
#       end
#     rescue SystemCallError
#       return false
#     end
#   end
# end

# def run_ssl_server(app, port)
#   options = {
#     Port: port,
#     SSLEnable: true,
#     SSLVerifyClient: OpenSSL::SSL::VERIFY_NONE,
#     SSLPrivateKey: OpenSSL::PKey::RSA.new(File.read(Rails.root.join('config', 'nginx', 'certs', 'dev.catawiki.nl.key').to_s)),
#     SSLCertificate: OpenSSL::X509::Certificate.new(File.read(Rails.root.join('config', 'nginx', 'certs', 'dev.catawiki.nl.crt').to_s)),
#     SSLCertName: [["NL", WEBrick::Utils::getservername]],
#     AccessLog: [],
#     Logger: WEBrick::Log::new(Rails.root.join('log', 'test_ssl.log').to_s)
#   }
#
#   Rack::Handler::WEBrick.run(app, options)
# end

# Capybara.server do |app, port|
#   run_ssl_server(app, port)
# end

# Capybara.server_port = 3001
# Capybara.app_host = "https://localhost:%d" % Capybara.server_port
# Rails.application.default_url_options[:host] = "localhost:%d" % Capybara.server_port

Capybara.register_driver :poltergeist do |app|
  Capybara::Poltergeist::Driver.new(app, inspector: true,
                                         timeout: 120,
                                         window_size: [1024, 1024],
                                         phantomjs_options: ['--ssl-protocol=ANY',
                                                             '--ignore-ssl-errors=yes',
                                                             '--local-to-remote-url-access=yes'],
                                         phantomjs_logger: PhantomjsLogger.new(1),
                                         debug: false)
end

# Set the capybara javascript driver. Defaults to :selenium
Capybara.javascript_driver = :poltergeist

Capybara::Screenshot.register_driver(:poltergeist) do |driver, path|
  driver.render(path)
end
Capybara.save_and_open_page_path = ENV["CIRCLE_ARTIFACTS"] if ENV["CIRCLECI"]

# configure capybara screenshot output
Capybara::Screenshot::RSpec::REPORTERS["Fuubar"] = Capybara::Screenshot::PathReporter

Capybara.default_wait_time = 4 if ENV["CIRCLECI"]

RSpec.configure do |config|
  # RSpec Rails can automatically mix in different behaviours to your tests
  # based on their file location, for example enabling you to call `get` and
  # `post` in specs under `spec/controllers`.
  #
  # You can disable this behaviour by removing the line below, and instead
  # explicitly tag your specs with their type, e.g.:
  #
  #     RSpec.describe UsersController, type: :controller do
  #       # ...
  #     end
  #
  # The different available types are documented in the features, such as in
  # https://relishapp.com/rspec/rspec-rails/docs
  config.infer_spec_type_from_file_location!

  config.include ControllerHelpers, type: :controller
  config.include FeatureHelpers, type: :feature

  config.before(:suite) do
    Fabrication.clear_definitions
    DatabaseCleaner.clean_with(:truncation)
  end

  config.before(:each) do |example|
    if example.metadata[:js]
      # Transactional fixtures do not work with Selenium, Webkit or Phantomjs
      # tests, because Capybara uses a separate server thread, which the
      # transactions would be hidden from. We hence use DatabaseCleaner
      # to truncate our test database.
      DatabaseCleaner.strategy = :truncation
    else
      DatabaseCleaner.strategy = :transaction
    end
    ActionMailer::Base.deliveries.clear
    ResqueSpec.reset!
    # Reset locale
    I18n.default_locale = I18n.locale = Catastatus::Application.config.i18n.default_locale
  end

  config.before(:each) do
    Timecop.return
    DatabaseCleaner.start
  end

  config.before(type: :feature) do
    clear_emails
    # This is so stack traces end up in the screenshots, because for
    # some reason they don't go to log/test.log or the rspec run
    Rails.application.config.action_dispatch.show_exceptions = true
    # Truncate log file
    `>| log/test.log` if ENV['RAILS_SHOW_TEST_LOG'] || ENV['CIRCLECI']
  end

  config.after(type: :feature) do
    Rails.application.config.action_dispatch.show_exceptions = false
  end

  config.append_after(:each) do
    # clear cookiesData before cleaning database!!!
    Capybara.reset_sessions!
    DatabaseCleaner.clean
  end
end
