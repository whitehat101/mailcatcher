require "net/http/server"
require "rack/handler/http"

require "mail_catcher/web"

class MailCatcher::HTTP < Net::HTTP::Server::Daemon
  def initialize(logger: nil, **options)
    super(handler: Rack::Handler::HTTP.new(MailCatcher::Web::Application.new), log: logger, **options)
  end
end
