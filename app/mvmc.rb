require 'open3'
require 'ostruct'
require 'sinatra/base'
require 'sinatra/i18n'
require 'sinatra/content_for'

VMS_DIR  = File.expand_path(File.dirname(__FILE__), '../vms')
ISOS_DIR = File.expand_path(File.dirname(__FILE__), '../isos')

ISO = Struct.new(:basename, :mtime, :size)

class Runner

  Result = Struct.new(:output, :status) do
    def success?
      status.success?
    end
    def lines
      output.lines.to_a.map(&:strip).reject(&:empty?)
    end
  end

  def self.wrap_with
    if ENV["RACK_ENV"].to_sym == :development
      'ssh -o "ProxyCommand nc -X connect -x ssh.protonet.info:8022 %%h %%p" -o "User protonet" cebit %s'
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
    5900 + number.to_i
  end

  def self.all
    if r = Runner.command('virsh list --inactive --all')
      if r.success?
        r.lines[2..-1].collect do |line|
          res = line.split("\s").map(&:strip)
          new(*res)
        end
      end
    else
      []
    end
  end

  def self.create(name, bootiso)
    command(create_command(name, bootiso)).success?
  end

  private

  def self.create_command(name, bootiso, cdiso)
    cc = <<-EOCREATECOMMAND.unindent
      sudo virt-install                                                   \
        --force                                                           \
        --graphics vnc,listen=0.0.0.0 --noautoconsole                     \
        --arch=x86_64                                                     \
        --connect "#{opts.libvirt_domain}"                                \
        --disk="#{opts.vm_hdd_image % name}",bus=virtio,cache=none        \
        --network bridge:virbr0,model=e1000                               \
        --vcpus="#{opts.vm_num_cpus}"                                     \
        -c "#{File.join(VMS_DIR + bootiso)}"                              \
        -n "#{name}"                                                      \
        -r "#{opts.vm_ram}"
    EOCREATECOMMAND
    if cdiso
      cc.lines.insert(6, "--disk path=\"#{File.join(VMS_DIR + cdiso)}\",device=cdrom,perms=ro \\")
    end
    cc
  end

  def self.opts
    OpenStruct.new(options_hash)
  end

  def self.options_hash
    {
      :vm_hdd_image      => '~/vms/%s/hdd.img',
      :vm_hdd_image_size => '50G',
      :vm_num_cpus       => '2',
      :vm_ram            => 4069,
      :libvirt_domain    => 'qemu:///system'
    }
  end

end

class Mvmc < Sinatra::Base

  set :root,     File.join(File.dirname(__FILE__), '../')
  set :locales,  File.join(File.dirname(__FILE__), '../', 'config/locales/en.yml')

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
    @isos = Dir.glob(File.join(ISOS_DIR, '*.iso')).collect do |file|
      ISO.new(
        File.basename(file),
        File.mtime(file),
        File.size(file) / 1024 / 1024
      )
    end
    haml :'isos/index'
  end

  post '/vms' do
    params.inspect
    VM.send(:create_command, params[:name], params["bootiso"])
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
