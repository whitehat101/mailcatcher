require "mail"
require "midi-smtp-server"

require "mail_catcher/mail"

class MailCatcher::SMTP < MidiSmtpServer::Smtpd
  public :start

  def initialize(host:, port:, logger: nil, **options)
    super(port, host, 256, do_dns_reverse_lookup: false, logger: logger)
  end

  def on_message_data_event(envelope:, message:, **context)
    MailCatcher::Mail.add_message(from: envelope[:from], to: envelope[:to], data: message[:data])

    puts "==> SMTP: Received message from '#{envelope[:from]}' (#{message[:data].bytesize} bytes)"
  rescue
    puts "*** Error receiving message"
    puts "    MailCatcher v#{MailCatcher::VERSION}"
    puts "    From: #{envelope[:from].inspect}"
    puts "    To: #{envelope[:to].inspect}"
    puts "    Data: #{message[:data].inspect}"
    puts "    Exception: #{$!}"
    puts "    Backtrace:"
    $!.backtrace.each do |line|
      puts "       #{line}"
    end
    puts "    Please submit this as an issue at http://github.com/sj26/mailcatcher/issues"

    raise MidiSmtpServer::Smtpd451Exception.new("Error receiving message, see MailCatcher log for details")
  end
end
