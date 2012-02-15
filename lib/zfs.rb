require 'pathname'

CMD_PREFIX=%w(ssh vagrant-zfs sudo zfs)

class ZFS
	attr_reader :name
	attr_reader :pool
	attr_reader :path

	def initialize(name)
		@name, @pool, @path = name, *name.split('/', 2)
	end

	def to_s
		"#<ZFS:#{name}>"
	end

	def valid?
		!ZFS.properties(name).nil?
	end

	def [](key)
		ZFS.properties(name)[key]
	end

	def []=(key, value)
		puts "Unimplemented."
	end

	# FIXME: walk through all filesystems (ZFS.properties), and find the ones where the 'origin' property
	#        matches +name+.
	# def clones
	# end

	# FIXME: -p, -r
	# FIXME: rename this instance, and make sure it is renamed in ZFS.properties, too.
	# FIXME: check that +newname+ doesn't exist.
	# def rename!(newname)
	# end

	# FIXME: better exception
	# FIXME: fails if there are snapshots or children - -r/-R?
	def destroy!
		raise Exception, "filesystem has already been deleted" if !valid?
		system(*CMD_PREFIX, "destroy", name)
		ZFS.invalidate(name)
	end

	# set/get/inherit - []?
	# mount!/unmount!
	# share/unshare
	# send
	# receive
end



module ZFS::Snapshots
	def snapshot!(snapname)
		raise Exception, "filesystem has been deleted" if !valid?

		system(*CMD_PREFIX, "snapshot", "#{name}@#{snapname}")
		ZFS.invalidate(name)
		ZFS["#{name}@#{snapname}"]
	end

	def snapshots
		raise Exception, "filesystem has been deleted" if !valid?

		snaps = ZFS.properties.find_all { |fs, props| fs.match(/^#{name}@/) }
		snaps.collect { |fs, props| ZFS::Snapshot.new(fs) }
	end

	# FIXME: check that self is indeed a clone-fs
	# FIXME: origin-fs loses a snapshot, and gets its own origin altered, so reload properties+snapshots for it, too.
	def promote!
		raise Exception, "filesystem is not a clone" if self['origin'] == '-'
		system(*CMD_PREFIX, "promote", name)
		ZFS.invalidate(name)
		ZFS.invalidate(self['origin'])
	end
end

class ZFS::Snapshot < ZFS
	# FIXME: check for errors in +clone+ (pool must be identical to snapshot, for instance, and fs must not already exist)
	# FIXME: better Exception
	def clone!(clone)
		raise Exception, "snapshot has been deleted" if !valid?

		system(*CMD_PREFIX, "clone", name, clone)
		ZFS.invalidate(name)
		ZFS.invalidate(clone)
		ZFS[clone]
	end
end

class ZFS::Volume < ZFS
	include ZFS::Snapshots

	# FIXME: how do we create?
end

class ZFS::Filesystem < ZFS
	include ZFS::Snapshots

	# Create filesystem
	def create(subname)
		fs = "#{name}/#{subname}"

		raise Exception, "filesystem already exists" if ZFS[fs]

		system(*CMD_PREFIX, "create", fs)
		ZFS.invalidate(name)
		ZFS[fs]
	end
end



class << ZFS
	# Load/reload properties for all or a specific filesystem
	def properties(path=nil)
		@properties ||= {}

		cmd = [*CMD_PREFIX, "get", "-oname,property,value", "-Hpr", "all"]
		cmd << path unless path.nil?
		cmd << { err: [:child, :out] }

		IO.popen(cmd) do |pipe|
			pipe.lines.each do |attrs|
				if attrs.match(/dataset does not exist$/) and !path.nil?
					invalidate(path)
				else
					name, property, value = attrs.split(/\t/, 3)
					@properties[name] ||= {}
					@properties[name][property] = value.chomp
				end
			end
		end unless @properties.has_key?(path)

		path.nil? ? @properties : @properties[path]
	end

	# Invalidate properties for a given pool-path
	def invalidate(path=nil)
		if path.nil? or @properties.nil?
			@properties = {}
		else
			@properties.delete_if { |name, props| name.match(/^#{path}(\/|$|@)/) }
		end
	end

	# Fetch filesystem by pool-path or mountpoint.
	def [](path, find_parent=false)		
		if path[0] == '/'
			# Find by mountpoint - remember to exclude zoned/jailed filesystems
			path = Pathname(path).cleanpath
			fs = mountpoints.find { |m| m[0] == path.to_s }

			if fs.nil? and find_parent
				until path.root? or !fs.nil?
					fs = mountpoints.find { |m| m[0] == path.to_s }
					path = path.parent
				end
			end

			fs.nil? ? nil : fs[1]
		else
			@zfs ||= {}

			props = self.properties(path)
			fs = nil

			return nil if props.nil?
			return @zfs[path] if @zfs.has_key?(path)

			case props['type']
			when 'filesystem';
				fs = ZFS::Filesystem.new(path)
			when 'snapshot';
				fs = ZFS::Snapshot.new(path)
			when 'volume';
				fs = ZFS::Volume.new(path)
			else
				raise Exception, "Unknown filesystem type '#{props['type']}'"
			end

			@zfs[path] = fs unless fs.nil?
			fs
		end
	end

	# Enumerator for all filesystems in all pools.
	def filesystems
		if !block_given?
			enum_for(:filesystems)
		else
			properties.keys.each { |fs| yield self[fs] }
		end
	end

	# Enumerator for all mounted filesystems, excluding those in a jail or zone.
	def mountpoints
		if !block_given?
			enum_for(:mountpoints)
		else
			properties.find_all do |fs, props|
				props['jailed'] != 'on' && props['zoned'] != 'on'
			end.each { |fs, props| yield [ props['mountpoint'], self[fs] ] }
		end
	end

	# Create filesystem
	# FIXME: `opts[:parents] = true` to create sub-filesystems (zfs create -p)
	# FIXME: `opts[:volume] = INT` to create a volume with ref-reservation of INT size
	def create(name, opts={})
		if matches = name.match(/^(.+)\/([^\/]+)$/)
			self[matches[1]].create(matches[2])
		else
			raise Exception, "Invalid path-spec, '#{name}'"
		end
	end
end
