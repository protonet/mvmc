require 'open3'
require 'ostruct'
require 'sinatra/base'
require 'sinatra/i18n'
require 'sinatra/content_for'

ISO = Struct.new(:basename, :mtime, :size)

class Runner

  Result = Struct.new(:output, :status) do
    def success?
      status.success?
    end
    def lines
      output.lines.to_a
    end
  end

  def self.wrap_with
    if ENV["RACK_ENV"].to_sym == :development
      'ssh cebit "%s"'
    else
      'env -i %s'
    end
  end

  def self.command(c)
    c    = wrap_with % c
    o, s = Open3.capture2e(c)
    Result.new(o, s)
  end

end

class VM


  attr_reader :number, :name, :state

  def initialize(number, name, state)
    @number, @name, @state = number, name, state
  end

  def vnc_port
    5900 + number
  end

  def self.all
    if r = Runner.command('virsh list --inactive --all')
      if r.success?
        debugger
        return r.lines[2..-1].collect do |line|
          new(*line.split("\s").map(&:strip))
        end
      end
      []
    else
      []
    end
  end

  def create(name, bootiso)
    command(create_command(name, bootiso)).status.success?
  end

  private

  def create_command(name, bootiso)
    <<-EOCREATECOMMAND.unindent
      sudo virt-install                                                           \
        --force                                                                   \
        --graphics vnc,listen=0.0.0.0 --noautoconsole                             \
        --arch=x86_64                                                             \
        --connect "#{opts.libvirt_domain}"                                        \
        --disk path="#{opts.vm_cd_image}",device=cdrom,perms=ro                   \
        --disk="#{opts.vm_hdd_image % boot_options[:name]}",bus=virtio,cache=none \
        --network bridge:virbr0,model=e1000                                       \
        --vcpus="#{opts.vm_num_cpus}"                                             \
        -c "#{opts[:vm_boot_image] % File.join(settings.isos_dir + bootiso)}"     \
        -n "#{name}"                                                              \
        -r "#{opts.vm_ram}"
    EOCREATECOMMAND
  end

  def opts
    OpenStruct.new(options_hash)
  end

  def options_hash
    {
      :vm_hdd_image      => '~/vms/%s/hdd.img',
      :vm_hdd_image_size => '50G',
      :vm_cd_image       => '~/isos/virtio-win-0.1-52.iso',
      :vm_boot_image     => '~/isos/%s',
      :vm_num_cpus       => '2',
      :vm_ram            => 4069,
      :libvirt_domain    => 'qemu:///system'
    }
  end

end

class Mvmc < Sinatra::Base

  set :root,     File.join(File.dirname(__FILE__), '../')
  set :locales,  File.join(File.dirname(__FILE__), '../', 'config/locales/en.yml')
  set :isos_dir, File.join(File.dirname(__FILE__), '../', 'isos')
  set :vms_dir,  File.join(File.dirname(__FILE__), '../', 'vms')

  helpers Sinatra::ContentFor
  register Sinatra::I18n

  get '/' do
    redirect to('/dashboard'), 303
  end

  get '/dashboard' do
    haml :'dashboard/index'
  end

  get '/vms' do
    @vms = VM.all
    haml :'vms/index'
  end

  get '/isos' do
    @isos = Dir.glob(File.join(settings.isos_dir, '*.iso')).collect do |file|
      ISO.new(
        File.basename(file),
        File.mtime(file),
        File.size(file) / 1024 / 1024
      )
    end
    haml :'isos/index'
  end

  get '/isos/:basename' do |basename|
    send_file File.join(settings.isos_dir, basename)
  end

  post '/isos' do
    if params['file']
      File.open(File.join(settings.isos_dir, params['file'][:filename]), 'wb') do |f|
        f.write(params['file'][:tempfile].read)
      end
    end
    status 200
  end

end
