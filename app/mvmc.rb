require 'uri'

require 'rexml/document'
require 'builder'
require 'sinatra/base'
require 'sinatra/content_for'
require 'sinatra/i18n'

require './lib/virsh/storage_pool'
require './lib/iso'
require './lib/vm'

DEFAULT_HYPERVISOR_URL = "qemu:///system"

VIRSH_URI      = "qemu+ssh://protonet@cebit.local/system?socket=/var/run/libvirt/libvirt-sock"
VIRSH_POOL_DIR = "/var/lib/libvirt/images"

VMS_DIR        = File.expand_path(File.join(File.dirname(__FILE__), '../vms/'))
ISOS_DIR       = File.expand_path(File.join(File.dirname(__FILE__), '../isos/'))

class Mvmc < Sinatra::Base

  set :root,     File.join(File.dirname(__FILE__), '../')
  set :locales,  File.join(File.dirname(__FILE__), '../', 'config/locales/en.yml')

  helpers Sinatra::Cookies
  helpers Sinatra::ContentFor

  register Sinatra::I18n

  helpers do
    def h(text)
      Rack::Utils.escape_html(text)
    end
    def hypervisor_url
      URI.unescape(cookies[:hypervisor_url])
    end
  end

  before do
    #
    # Try and connect to the Hypervisor
    #
    begin
      hvuri = params[:hypervisor_url] || cookies[:hypervisor_url] || DEFAULT_HYPERVISOR_URL
      $libvirt.close if $livbirt
      $libvirt = Libvirt::open(hvuri)
    rescue Libvirt::ConnectionError
      warn "Couldn't access hypervisor at #{hvuri}"
    ensure
      if !$libvirt or $libvirt.closed?
        redirect to('/hypervisor') unless request.path_info == '/hypervisor'
        return
      end
    end
    begin
      Virsh::StoragePool.create_defaults
    rescue
      warn "Couldn't create default storage volumes #{$!}"
    end
  end

  post '/hypervisor' do
    response.set_cookie(
      :hypervisor_url,
      value: params[:hypervisor_url],
      expires: Time.now + 3600*24*7
    )
    haml :'hypervisor/show'
  end

  get '/hypervisor' do
    haml :'hypervisor/show'
  end

  get '/' do
    redirect to('/dashboard'), 303
  end

  get '/dashboard' do
    redirect to('/vms'), 303
  end

  get '/vms' do
    @vms  = VM.all
    @isos = isos
    haml :'vms/index'
  end

  get '/isos' do
    @isos = isos
    haml :'isos/index'
  end

  post '/vms' do
    pool = Virsh::StoragePool.all.first
    hdd_images = params[:vm][:volumes].collect do |i, volume_params|
      pool.create_volume(volume_params[:name], volume_params[:capacity]).path
    end
    VM.create(params[:vm][:name], params[:vm][:cdisos].values, hdd_images)
    redirect '/vms'
  end

  get '/vms/:uuid/start' do |uuid|
    VM.new.tap do |vm|
      vm.uuid = uuid
    end.start
    redirect '/vms'
  end

  get '/storage/volume.xml' do
    builder :'storage/volume'
  end

  get '/vms/:uuid/shutdown' do |uuid|
    VM.new.tap do |vm|
      vm.uuid = uuid
    end.shutdown
    redirect '/vms'
  end

  get '/vms/:uuid/undefine' do |uuid|
    VM.new.tap do |vm|
      vm.uuid = uuid
    end.undefine
    redirect '/vms'
  end

  get '/vms/:uuid/stop' do |uuid|
    VM.new.tap do |vm|
      vm.uuid = uuid
    end.destroy
    redirect '/vms'
  end

  get '/isos/:basename' do |basename|
    send_file File.join(settings.isos_dir, basename)
  end

  post '/isos' do
    if params['file']
      Virsh::StoragePool.find_by_name('virsh-isos').tap do |pool|
        pool.create_volume(
          params[:file][:filename],
          params[:file][:tempfile].size
        ).tap do |volume|
          stream = $libvirt.stream
          volume.upload(
            stream,
            0,
            params[:file][:tempfile].size
          )
          stream.sendall(params[:file][:tempfile]) do |opaque, nbytes|
            [0, opaque.read(nbytes)]
          end
          stream.finish
        end
      end
    end
    status 200
  end

  get '/pools' do
    @pools = Virsh::StoragePool.all
    haml :'pools/index'
  end

  private

  def isos
    pool = $libvirt.lookup_storage_pool_by_name('virsh-isos')
    pool.list_volumes.collect do |volume_name|
      pool.lookup_volume_by_name(volume_name)
    end
  end

end
