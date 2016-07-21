require "logger"
require "open3"
require "optparse"
require "rbconfig"

require "mail_catcher/smtp"
require "mail_catcher/http"
require "mail_catcher/version"

module MailCatcher extend self
  def which?(command)
    ENV["PATH"].split(File::PATH_SEPARATOR).any? do |directory|
      File.executable?(File.join(directory, command.to_s))
    end
  end

  def mac?
    RbConfig::CONFIG['host_os'] =~ /darwin/
  end

  def windows?
    RbConfig::CONFIG['host_os'] =~ /mswin|mingw/
  end

  def macruby?
    mac? and const_defined? :MACRUBY_VERSION
  end

  def browseable?
    windows? or which? "open"
  end

  def browse url
    if windows?
      system "start", "/b", url
    elsif which? "open"
      system "open", url
    end
  end

  @@defaults = {
    :smtp_ip => '127.0.0.1',
    :smtp_port => '1025',
    :http_ip => '127.0.0.1',
    :http_port => '1080',
    :verbose => false,
    :daemon => !windows?,
    :browse => false,
    :quit => true,
  }

  def options
    @@options
  end

  def quittable?
    options[:quit]
  end

  def parse! arguments=ARGV, defaults=@defaults
    @@defaults.dup.tap do |options|
      OptionParser.new do |parser|
        parser.banner = "Usage: mailcatcher [options]"
        parser.version = VERSION

        parser.on("--ip IP", "Set the ip address of both servers") do |ip|
          options[:smtp_ip] = options[:http_ip] = ip
        end

        parser.on("--smtp-ip IP", "Set the ip address of the smtp server") do |ip|
          options[:smtp_ip] = ip
        end

        parser.on("--smtp-port PORT", Integer, "Set the port of the smtp server") do |port|
          options[:smtp_port] = port
        end

        parser.on("--http-ip IP", "Set the ip address of the http server") do |ip|
          options[:http_ip] = ip
        end

        parser.on("--http-port PORT", Integer, "Set the port address of the http server") do |port|
          options[:http_port] = port
        end

        parser.on("--no-quit", "Don't allow quitting the process") do
          options[:quit] = false
        end

        if mac?
          parser.on("--[no-]growl") do |growl|
            puts "Growl is no longer supported"
            exit -2
          end
        end

        unless windows?
          parser.on('-f', '--foreground', 'Run in the foreground') do
            options[:daemon] = false
          end
        end

        if browseable?
          parser.on('-b', '--browse', 'Open web browser') do
            options[:browse] = true
          end
        end

        parser.on('-v', '--verbose', 'Be more verbose') do
          options[:verbose] = true
        end

        parser.on('-h', '--help', 'Display this help information') do
          puts parser
          exit
        end
      end.parse!
    end
  end

  def logger
    @logger ||= Logger.new(STDOUT).tap do |logger|
      logger.level = Logger::INFO
    end
  end

  def run! options=nil
    # If we are passed options, fill in the blanks
    options &&= options.reverse_merge @@defaults
    # Otherwise, parse them from ARGV
    options ||= parse!

    # Stash them away for later
    @@options = options

    # If we're running in the foreground sync the output.
    unless options[:daemon]
      $stdout.sync = $stderr.sync = true
    end

    puts "Starting MailCatcher"

    # Start up an SMTP server
    @smtp_server = MailCatcher::SMTP.new(host: options[:smtp_ip], port: options[:smtp_port], logger: logger)
    @smtp_server.start

    # Start up an HTTP server
    @http_server = MailCatcher::HTTP.new(host: options[:http_ip], port: options[:http_port], logger: logger)
    @http_server.start

    # Set up some signal traps to gracefully quit
    #Signal.trap("INT") { quit! }
    #Signal.trap("TERM") { quit! }

    # Tell her about it
    puts "==> #{smtp_url}"
    puts "==> #{http_url}"

    # Open a browser if we were asked to
    if options[:browse]
      browse http_url
    end

    # Daemonize, if we should, but only after the servers have started.
    if options[:daemon]
      if quittable?
        puts "*** MailCatcher runs as a daemon by default. Go to the web interface to quit."
      else
        puts "*** MailCatcher is now running as a daemon that cannot be quit."
      end

      Process.daemon
    end

    # Now wait for shutdown
    @smtp_server.join
    @http_server.join

    logger.info "Bye! 👋"
  end

  def quit!
    unless quitting?
      @smtp_server.stop
      @http_server.stop

      @quitting = true
    end
  end

  def quitting?
    !!@quitting
  end

protected

  def smtp_url
    "smtp://#{@@options[:smtp_ip]}:#{@@options[:smtp_port]}"
  end

  def http_url
    "http://#{@@options[:http_ip]}:#{@@options[:http_port]}"
  end

  def rescue_port port
    begin
      yield

    # XXX: EventMachine only spits out RuntimeError with a string description
    rescue RuntimeError
      if $!.to_s =~ /\bno acceptor\b/
        puts "~~> ERROR: Something's using port #{port}. Are you already running MailCatcher?"
        puts "==> #{smtp_url}"
        puts "==> #{http_url}"
        exit -1
      else
        raise
      end
    end
  end
end
