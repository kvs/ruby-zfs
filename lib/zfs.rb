require 'pathname'
require 'date'

CMD_PREFIX=%w(ssh vagrant-zfs sudo zfs)

class ZFS
	class << self
		# Define an attribute
		def attribute(name, opts={})
			define_method "#{name}_source" do
				# FIXME
			end if opts[:edit]

			define_method "#{name}_inherited?" do
				# FIXME
			end if opts[:inherit]

			define_method "#{name}_inherit!" do
				# FIXME
			end if opts[:inherit]

			case opts[:type]
			when :size, :integer
				# FIXME: when type==:size, also accept Strings with standard units, which can get passed down through to ZFS
				# FIXME: also takes :values. if :values is all-Integers, these are the only options. if there are non-ints, then :values is a supplement

				define_method name do
					get(name)
				end
				define_method "#{name}=" do |value|
					set(name, value)
				end if opts[:edit]

			when :boolean
				# FIXME: booleans can take extra values, so there are on/true, off/false, plus what amounts to an enum
				# FIXME: if options[:values] is defined, also create a 'name' method, since 'name?' might not ring true
				# FIXME: replace '_' by '-' in opts[:values]
				define_method "#{name}?" do
					get(name) == 'on'
				end
				define_method "#{name}=" do |value|
					set(name, value ? 'on' : 'off')
				end if opts[:edit]

			when :enum
				define_method name do
					sym = (get(name) || "").gsub('-', '_').to_sym
					if opts[:values].grep(sym)
						return sym
					else
						raise "#{name} has value #{sym}, which is not in enum-list"
					end
				end
				define_method "#{name}=" do |value|
					set(name, value.to_s.gsub('_', '-'))
				end if opts[:edit]

			when :snapshot
				define_method name do
					val = get(name)
					val.nil? ? nil : ZFS[val]
				end

			when :float
				define_method name do
					Float(get(name))
				end
				define_method "#{name}=" do |value|
					set(name, value)
				end if opts[:edit]

			when :string
				define_method name do
					get(name)
				end
				define_method "#{name}=" do |value|
					set(name, value)
				end if opts[:edit]

			when :date
				define_method name do
					DateTime.strptime(get(name), '%s')
				end

			when :pathname
				define_method name do
					Pathname(get(name))
				end
				define_method "#{name}=" do |value|
					set(name, value.to_s)
				end if opts[:edit]

			else
				puts "Unknown type '#{opts[:type]}'"
			end
		end
		private :attribute

		# Load/reload properties for all or a specific filesystem
		def properties(path=nil)
			@properties ||= {}

			cmd = [*CMD_PREFIX, "get", "-oname,property,value", "-Hpr", "all"]
			cmd << path unless path.nil?
			cmd << { err: [:child, :out] }

			IO.popen(cmd) do |pipe|
				pipe.lines.each do |attrs|
					if attrs.match(/dataset does not exist$/) and !path.nil?
						@properties.delete_if { |name, props| name.match(/^#{path}(\/|$|@)/) }
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
				ZFS.properties(path)
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
				props = self.properties(path)

				return nil if props.nil?

				case props['type']
				when 'filesystem';
					ZFS::Filesystem.new(path)
				when 'snapshot';
					ZFS::Snapshot.new(path)
				when 'volume';
					ZFS::Volume.new(path)
				else
					raise Exception, "Unknown filesystem type '#{props['type']}'"
				end
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

	attr_reader :name
	attr_reader :pool
	attr_reader :path

	attribute :available,            type: :size
	attribute :compressratio,        type: :float
	attribute :creation,             type: :date
	attribute :defer_destroy,        type: :boolean
	attribute :mounted,              type: :boolean
	attribute :origin,               type: :snapshot
	attribute :refcompressratio,     type: :float
	attribute :referenced,           type: :size
	attribute :type,                 type: :enum, values: [:filesystem, :snapshot, :volume] # FIXME: move to subclasses as a statically-defined prop?
	attribute :used,                 type: :size
	attribute :usedbychildren,       type: :size
	attribute :usedbydataset,        type: :size
	attribute :usedbyrefreservation, type: :size
	attribute :usedbysnapshots,      type: :size
	attribute :userrefs,             type: :integer

	attribute :aclinherit,           type: :enum,    edit: true, inherit: true, values: [:discard, :noallow, :restricted, :passthrough, :passthrough_x]
	attribute :atime,                type: :boolean, edit: true, inherit: true
	attribute :canmount,             type: :boolean, edit: true,                values: [:noauto]
	attribute :checksum,             type: :boolean, edit: true, inherit: true, values: [:fletcher2, :fletcher4, :sha256]
	attribute :compression,          type: :boolean, edit: true, inherit: true, values: [:lzjb, :gzip, :gzip_1, :gzip_2, :gzip_3, :gzip_4, :gzip_5, :gzip_6, :gzip_7, :gzip_8, :gzip_9, :zle]
	attribute :copies,               type: :integer, edit: true, inherit: true, values: [1, 2, 3]
	attribute :dedup,                type: :boolean, edit: true, inherit: true, values: [:verify, :sha256, 'sha256,verify']
	attribute :devices,              type: :boolean, edit: true, inherit: true
	attribute :exec,                 type: :boolean, edit: true, inherit: true
	attribute :logbias,              type: :enum,    edit: true, inherit: true, values: [:latency, :throughput]
	attribute :mlslabel,             type: :string,  edit: true, inherit: true
	attribute :mountpoint,           type: :pathname,edit: true, inherit: true
	attribute :nbmand,               type: :boolean, edit: true, inherit: true
	attribute :primarycache,         type: :enum,    edit: true, inherit: true, values: [:all, :none, :metadata]
	attribute :quota,                type: :size,    edit: true,                values: [:none]
	attribute :readonly,             type: :boolean, edit: true, inherit: true
	attribute :recordsize,           type: :integer, edit: true, inherit: true, values: [512, 1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072]
	attribute :refquota,             type: :size,    edit: true,                values: [:none]
	attribute :refreservation,       type: :size,    edit: true,                values: [:none]
	attribute :reservation,          type: :size,    edit: true,                values: [:none]
	attribute :secondarycache,       type: :enum,    edit: true, inherit: true, values: [:all, :none, :metadata]
	attribute :setuid,               type: :boolean, edit: true, inherit: true
	attribute :sharenfs,             type: :boolean, edit: true, inherit: true # FIXME: also takes 'share(1M) options'
	attribute :sharesmb,             type: :boolean, edit: true, inherit: true # FIXME: also takes 'sharemgr(1M) options'
	attribute :snapdir,              type: :enum,    edit: true, inherit: true, values: [:hidden, :visible]
	attribute :sync,                 type: :enum,    edit: true, inherit: true, values: [:standard, :always, :disabled]
	attribute :version,              type: :integer, edit: true,                values: [1, 2, 3, 4, :current]
	attribute :vscan,                type: :boolean, edit: true, inherit: true
	attribute :xattr,                type: :boolean, edit: true, inherit: true
	attribute :zoned,                type: :boolean, edit: true, inherit: true
	attribute :jailed,               type: :boolean, edit: true, inherit: true

	attribute :casesensitivity,      type: :enum,    create_only: true, values: [:sensitive, :insensitive, :mixed]
	attribute :normalization,        type: :enum,    create_only: true, values: [:none, :formC, :formD, :formKC, :formKD]
	attribute :utf8only,             type: :boolean, create_only: true

	# Set a variable
	def set(key, value)
		# FIXME: remember to invalidate or refresh ZFS.properties
	end

	# Get a variable
	def get(key)
		ZFS.properties(name)[key.to_s]
	end

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

	def rename!(newname)
		raise Exception, "target already exists" if ZFS[newname]
		system(*CMD_PREFIX, "rename", name, newname)
		ZFS.invalidate(name)
		initialize(newname)
	end

	# FIXME: better exception
	# FIXME: fails if there are snapshots or children - -r/-R?
	def destroy!
		raise Exception, "filesystem has already been deleted" if !valid?
		system(*CMD_PREFIX, "destroy", name)
		ZFS.invalidate(name)
	end

	def ==(other)
		other.class == self.class && other.name == self.name
	end

	# set/get/inherit - []?
	# mount!/unmount!
	# share/unshare
	# receive - might only be possible with '-d', unless defined as a class-method on ZFS
end



module ZFS::Snapshots
	def snapshot!(snapname)
		raise Exception, "filesystem has been deleted" if !valid?
		raise Exception, "snapshot already exists" unless snapshots.grep(snapname).empty?

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

	def rename!(newname)
		raise Exception, "invalid new name" if newname.match('/')
		super(name.gsub(/@.+$/, "@#{newname}"))
	end

	# FIXME: walk through all filesystems (ZFS.properties), and find the ones where the 'origin' property
	#        matches +name+.
	# def clones
	# end

	# send

	def send_to(dest, opts={})
		cmd = []
		incr_snap = nil

		if opts[:incremental] and opts[:intermediary]
			raise Exception, "can't specify both :incremental and :intermediary"
		end

		incr_snap = opts[:incremental] || opts[:intermediary]
		if incr_snap
			# FIXME (missing 'origin') raise Exception, "snapshot '#{incr_snap} must exist at #{name}" unless origin.snapshots.grep(incr_snap)
			raise Exception, "snapshot '#{incr_snap} must exist at #{dest}" unless dest.snapshots.grep(incr_snap)
			# FIXME: must verify that incr_snap is the latest snapshot at +dest+
		end

		cmd.concat ['-i', incr_snap] if opts[:incremental]
		cmd.concat ['-I', incr_snap] if opts[:intermediary]
		cmd << '-R' if opts[:replication]
		cmd << '-D' if opts[:dedup]
		cmd << name

		dest = dest.name unless dest.is_a? String

		system([*CMD_PREFIX, "send", *cmd, "|", *CMD_PREFIX, "receive", dest].join(' '))

		ZFS.invalidate(dest)
	end
end

class ZFS::Volume < ZFS
	include ZFS::Snapshots

	attribute :volblocksize,         type: :integer, create_only: true, values: [512, 1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072]
	attribute :volsize,              type: :size,    edit: true

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

	def rename!(newname)
		raise Exception, "invalid new name" if newname.match('@')
		raise Exception, "must be in same pool" unless newname.match(/^#{pool}\//)
		super(newname)
	end
end
