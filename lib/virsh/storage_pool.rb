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
          sp.name = name
          sp.uuid = uuid
        end
      end
      def find_by_name(name)
        find($libvirt.lookup_storage_pool_by_name(name).uuid)
      end
      def create_defaults
        begin
          $libvirt.lookup_storage_pool_by_name('virsh-images')
        rescue
          warn "Couldn't find pool virsh-images, will create"
          $libvirt.define_storage_pool_xml(create_pool_xml('virsh-images')).tap do |pool|
            pool.build
            pool.create
            pool.autostart = true
          end
        end
        begin
          $libvirt.lookup_storage_pool_by_name('virsh-isos')
        rescue
          warn "Couldn't find pool virsh-isos, will create"
          $libvirt.define_storage_pool_xml(create_pool_xml('virsh-isos')).tap do |pool|
            pool.build
            pool.create
            pool.autostart = true
          end
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

      def create_pool_xml(name)
        xml = Builder::XmlMarkup.new
        xml.instruct! :xml, :version => '1.1'
        xml.pool type: :dir do |pool|
          pool.name name
          pool.target do |target|
            target.path File.join(VIRSH_POOL_DIR, name)
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
        volume.capacity capacity
      end
    end

    def pool
      $libvirt.lookup_storage_pool_by_uuid(uuid)
    end

  end

end
