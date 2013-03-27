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
          os.type "hvm", arch: :x86_64, machine: :pc
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
