require 'rexml/document'
require 'builder'
require 'sinatra/base'
require 'sinatra/content_for'
require 'sinatra/i18n'

VIRSH_URI = "qemu:///system?socket=/var/run/libvirt/libvirt-sock"
VIRSH_POOL_DIR = "/var/lib/libvirt/images"

VMS_DIR        = File.expand_path(File.join(File.dirname(__FILE__), '../vms/'))
ISOS_DIR       = File.expand_path(File.join(File.dirname(__FILE__), '../isos/'))

ISO = Struct.new(:basename, :mtime, :size)

$libvirt = Libvirt::open(VIRSH_URI)

module Virsh

  class StoragePool

    attr_accessor :name, :uuid

    def num_of_volumes
      pool.num_of_volumes
    end

    def volumes
      pool.list_volumes.collect do |volume_name|
        pool.lookup_volume_by_name(volume_name)
      end
    end

    def create_volume(name, capacity)
      pool.create_volume_xml(create_volume_xml_string(name, capacity))
    end

    class << self
      def find(uuid)
        pool = $libvirt.lookup_storage_pool_by_uuid(uuid)
        StoragePool.new.tap do |sp|
          sp.uuid = uuid
        end
      end
      def create_default
        $libvirt.define_storage_pool_xml(create_pool_xml).tap do |pool|
          pool.build
          pool.create
          pool.autostart = true
        end
      end
      def all
        $libvirt.list_storage_pools.collect do |pool_name|
          pool = $libvirt.lookup_storage_pool_by_name(pool_name)
          StoragePool.new.tap do |sp|
            sp.name = pool.name
            sp.uuid = pool.uuid
          end
        end
      end

      private

      def create_pool_xml
        xml = Builder::XmlMarkup.new
        xml.instruct! :xml, :version => '1.1'
        xml.pool type: :dir do |pool|
          pool.name "virsh-images"
          pool.target do |target|
            target.path VIRSH_POOL_DIR
          end
        end
        warn xml.target!
        xml.target!
      end
    end

    def create_volume_xml_string(name, capacity)
      xml = Builder::XmlMarkup.new
      xml.instruct! :xml, :version => '1.1'
      xml.volume do |volume|
        volume.name "#{name}.img"
        volume.capacity capacity, unit: :G
      end
    end

    def pool
      $libvirt.lookup_storage_pool_by_uuid(uuid)
    end

  end

end

class VM

  attr_accessor :id, :uuid, :name

  def running?
    domain.active?
  end

  def start
    domain.create
  end

  def destroy
    domain.destroy
  end

  def undefine
    domain.undefine
  end

  def shutdown
    domain.shutdown
  end

  def state
    domain.state
  end

  def vnc_port
    doc      = REXML::Document.new(domain.xml_desc)
    elements = doc.elements.to_a('/domain/devices/graphics')
    ports    = elements.collect { |e| e.attribute(:port).value }
    ports.first
  end

  class << self

    def all
      defined + running
    end

    def defined
     $libvirt.list_defined_domains.collect do |domain_name|
        domain = $libvirt.lookup_domain_by_name(domain_name)
        VM.new.tap do |vm|
          vm.id   = domain.id rescue nil
          vm.uuid = domain.uuid
          vm.name = domain_name
        end
      end
    end

    def running
      $libvirt.list_domains.collect do |domain_id|
        domain = $libvirt.lookup_domain_by_id(domain_id)
        VM.new.tap do |vm|
          vm.id   = domain_id
          vm.uuid = domain.uuid
          vm.name = domain.name
        end
      end
    end

    def create(name, cdiso_paths, volume_paths)
      domain = $libvirt.define_domain_xml(create_xml(name, cdiso_paths, volume_paths))
      domain.tap do |d|
        domain.autostart = true
        domain.create
      end
    end

    def create_xml(name, cdisos, volume_paths)

      xml = Builder::XmlMarkup.new
      xml.instruct! :xml, :version => '1.1'

      bus  = -1
      devs = ('hda'...'hde').to_a
      vdas = ('vda'...'vde').to_a

      xml.domain type: :kvm do |domain|

        # Hardware clock in local time
        domain.clock sync: :localtime

        domain.name name

        domain.memory         262144
        domain.current_memory 262144

        domain.vcpu 2

        domain.os do |os|
          os.type "hvm", arch: :i686, machine: :pc
          os.boot dev: :cdrom
        end

        domain.devices do |devices|

          devices.emulator "/usr/bin/kvm"

          cdisos.each do |cdiso|
            devices.disk type: :file, device: :cdrom do |disk|
              disk.driver name: :qemu, type: :raw
              disk.source file: cdiso
              disk.target dev: devs.shift, bus: :ide
              disk.readonly
              disk.address type: :drive, controller: 0, bus: (bus += 1), unit: 0
            end
          end

          volume_paths.each do |volume_path|
            devices.disk do |disk|
              disk.driver name: :qemu, type: :raw, cache: :none
              disk.source file: volume_path
              disk.target dev: vdas.shift, bus: :virtio
              disk.address type:      :pci,
                           domain:    '0x0000',
                           bus:       '0x0000',
                           slot:      '0x04',
                           function:  '0x00'
            end
          end

          devices.controller type: :ide, index: 0 do |controller|
            controller.address type:      :pci,
                               domain:    '0x0000',
                               bus:       '0x0000',
                               slot:      '0x01',
                               function:  '0x01'
          end

          devices.interface type: :network do |interface|
            interface.source network: :default
          end

          devices.video do |video|
            video.model   type: :vga, vram: 262144, heads: 1
            video.address type: :pci, domain: '0x0000', bus: '0x00', slot: '0x02', function: '0x0'
          end

          devices.graphics type: :vnc, autostart: :no, listen: '0.0.0.0' do |graphics|
            graphics.listen type: :address, address: '0.0.0.0'
          end

        end

      end
      xml.target!
    end

  end

  private

  def domain
    $libvirt.lookup_domain_by_uuid(uuid)
  end

end

class Mvmc < Sinatra::Base

  set :root,     File.join(File.dirname(__FILE__), '../')
  set :locales,  File.join(File.dirname(__FILE__), '../', 'config/locales/en.yml')

  helpers Sinatra::ContentFor
  register Sinatra::I18n

  before do
    Virsh::StoragePool.create_default if Virsh::StoragePool.all.empty?
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
      File.open(File.join(ISOS_DIR, params['file'][:filename]), 'wb') do |f|
        f.write(params['file'][:tempfile].read)
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
    Dir.glob(File.join(ISOS_DIR, '*.iso')).collect do |file|
      ISO.new(
        File.basename(file),
        File.mtime(file),
        File.size(file) / 1024 / 1024
      )
    end
  end

end
