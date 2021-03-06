require_relative 'common'
module Kontena
  module Machine
    module Vagrant
      class NodeProvisioner
        include RandomName
        include Kontena::Machine::Vagrant::Common
        include Kontena::Cli::ShellSpinner

        attr_reader :client, :api_client

        # @param [Kontena::Client] api_client Kontena api client
        def initialize(api_client)
          @api_client = api_client
        end

        def run!(opts)
          grid = opts[:grid]
          if opts[:name]
            name = "#{opts[:name]}-#{opts[:instance_number]}"
          else
            name = generate_name
          end
          version = opts[:version]
          vagrant_path = "#{Dir.home}/.kontena/#{grid}/#{name}"
          FileUtils.mkdir_p(vagrant_path)

          template = File.join(__dir__ , '/Vagrantfile.node.rb.erb')
          cloudinit_template = File.join(__dir__ , '/cloudinit.yml')
          vars = {
            name: name,
            version: version,
            cpus: opts[:cpus] || 1,
            memory: opts[:memory] || 1024,
            network_address: opts[:network_address],
            master_uri: opts[:master_uri],
            grid_token: opts[:grid_token],
            coreos_channel: opts[:coreos_channel],
            cloudinit: "#{vagrant_path}/cloudinit.yml"
          }
          spinner "Generating Vagrant config" do
            vagrant_data = erb(File.read(template), vars)
            cloudinit = erb(File.read(cloudinit_template), vars)
            File.write("#{vagrant_path}/Vagrantfile", vagrant_data)
            File.write("#{vagrant_path}/cloudinit.yml", cloudinit)
          end

          node = nil
          Dir.chdir(vagrant_path) do
            spinner "Triggering CoreOS Container Linux box update"
            system('vagrant box update')
            spinner "Executing 'vagrant up'"
            run_command('vagrant up')
            spinner "'vagrant up' executed successfully"
            spinner "Waiting for node #{name.colorize(:cyan)} to join grid #{grid.colorize(:cyan)} " do
              sleep 1 until node = node_exists_in_grid?(grid, name)
            end
          end
          set_labels(
            node,
            [
              "provider=vagrant"
            ]
          )
        end

        def generate_name
          "#{super}-#{rand(1..99)}"
        end

        def node_exists_in_grid?(grid, name)
          api_client.get("grids/#{grid}/nodes")['nodes'].find{|n| n['name'] == name}
        end

        def set_labels(node, labels)
          data = {labels: labels}
          api_client.put("nodes/#{node['id']}", data, {}, {'Kontena-Grid-Token' => node['grid']['token']})
        end
      end
    end
  end
end
