require 'rhc/commands/base'
require 'uri'

module RHC::Commands
  class PortForward < Base

    IP_AND_PORT = /[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\:[0-9]{1,5}/

    summary "Forward remote ports to the workstation"
    option ["-n", "--namespace namespace"], "Namespace of the application you are port forwarding to", :context => :namespace_context, :required => true
    option ["-a", "--app app"], "Application you are port forwarding to (required)", :context => :app_context, :required => true
    option ["--timeout timeout"], "Timeout, in seconds, for the session"
    def run

      domain = rest_client.find_domain options.namespace
      app = domain.find_application options.app

      raise RHC::ScaledApplicationsNotSupportedException.new "This utility does not currently support scaled applications. You will need to set up port forwarding manually." if (app.embedded.keys.any?{ |k| k =~ /\Ahaproxy/ })

      ssh_uri = URI.parse(app.ssh_url)
      say "Using #{app.ssh_url}..." if options.debug

      hosts_and_ports = []
      hosts_and_ports_descriptions = []

      begin

        say "Checking available ports..."

        Net::SSH.start(ssh_uri.host, ssh_uri.user) do |ssh|

          ssh.exec! "rhc-list-ports" do |channel, stream, data|
            if stream == :stderr
              data.each_line do |line|
                line.chomp!
                raise RHC::PermissionDeniedException.new "Permission denied." if line =~ /permission denied/i
                hosts_and_ports_descriptions << line if line.index(IP_AND_PORT)
              end
            else
              data.each_line do |line|
                line.chomp!
                hosts_and_ports << line if ((not line =~ /scale/i) and IP_AND_PORT.match(line))
              end
            end
          end

          raise RHC::NoPortsToForwardException.new "There are no available ports to forward for this application. Your application may be stopped." if hosts_and_ports.length == 0

          hosts_and_ports_descriptions.each { |description| say "Binding #{description}..." }

          begin
            Net::SSH.start(ssh_uri.host, ssh_uri.user) do |ssh|
              say "Forwarding ports, use ctl + c to stop"
              hosts_and_ports.each do |host_and_port|
                host, port = host_and_port.split(/:/)
                ssh.forward.local(host, port.to_i, host, port.to_i)
              end
              ssh.loop { true }
            end
          rescue Interrupt
            results { say "Ending port forward" }
            return 0
          end

        end

      rescue Timeout::Error, Errno::EHOSTUNREACH, Errno::ECONNREFUSED, Net::SSH::AuthenticationFailed => e
        ssh_cmd = "ssh -N "
        hosts_and_ports.each { |port| ssh_cmd << "-L #{port}:#{port} " }
        ssh_cmd << "#{ssh_uri.user}@#{ssh_uri.host}"
        raise RHC::PortForwardFailedException.new("#{e.message if options.debug}\nError trying to forward ports. You can try to forward manually by running:\n" + ssh_cmd)
      end

      return 0
    end
  end
end

# mock for windows
if defined?(UNIXServer) != 'constant' or UNIXServer.class != Class then class UNIXServer; end; end

