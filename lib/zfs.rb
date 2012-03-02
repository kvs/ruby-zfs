# -*- mode: ruby; tab-width: 4; indent-tabs-mode: t -*-

require 'pathname'
require 'date'
require 'open4'

# Get ZFS object.
def ZFS(path)
	path = Pathname(path).cleanpath.to_s

	if path.match(/^\//)
		ZFS.mounts[path]
	elsif path.match('@')
		ZFS::Snapshot.new(path)
	else
		ZFS::Filesystem.new(path)
	end
end

# Pathname-inspired class to handle ZFS filesystems/snapshots/volumes
class ZFS
	@zfs_path   = "zfs"
	@zpool_path = "zpool"

	attr_reader :name
	attr_reader :pool
	attr_reader :path

	class NotFound < Exception; end
	class AlreadyExists < Exception; end
	class InvalidName < Exception; end

	# Create a new ZFS object (_not_ filesystem).
	def initialize(name)
		@name, @pool, @path = name, *name.split('/', 2)
	end

	# Return the parent of the current filesystem, or nil if there is none.
	def parent
		p = Pathname(name).parent.to_s
		if p == '.'
			nil
		else
			ZFS(p)
		end
	end

	# Returns the children of this filesystem
	def children(opts={})
		raise NotFound if !exist?

		stdout, stderr = [], []
		cmd = [ZFS.zfs_path].flatten + %w(list -H -r -oname -tfilesystem)
		cmd << '-d1' unless opts[:recursive]
		cmd << name

		Open4::spawn(cmd, stdout: stdout, stderr: stderr)

		stdout.shift # self
		stdout.collect do |filesystem|
			ZFS(filesystem.chomp)
		end
	end

	# Does the filesystem exist?
	def exist?
		stdout, stderr = [], []
		cmd = [ZFS.zfs_path].flatten + %w(list -H -oname) + [name]

		Open4::spawn(cmd, stdout: stdout, stderr: stderr, ignore_exit_failure: true)

		if stdout == ["#{name}\n"]
			true
		else
			false
		end
	end

	# Create filesystem
	def create(opts={})
		return nil if exist?

		stdout, stderr = [], []
		cmd = [ZFS.zfs_path].flatten + ['create']
		cmd << '-p' if opts[:parents]
		cmd += ['-V', opts[:volume]] if opts[:volume]
		cmd << name

		Open4::spawn(cmd, stdout: stdout, stderr: stderr)

		if stdout.empty? and stderr.empty?
			return self
		else
			raise Exception, "something went wrong"
		end
	end

	# Destroy filesystem
	def destroy!(opts={})
		raise NotFound if !exist?

		stdout, stderr = [], []
		cmd = [ZFS.zfs_path].flatten + ['destroy']
		cmd << '-r' if opts[:children]
		cmd << name

		Open4::spawn(cmd, stdout: stdout, stderr: stderr)

		if stdout.empty? and stderr.empty?
			return true
		else
			raise Exception, "something went wrong"
		end
	end

	# Stringify
	def to_s
		"#<ZFS:#{name}>"
	end

	# ZFS's are considered equal if they are the same class and name
	def ==(other)
		other.class == self.class && other.name == self.name
	end

	def [](key)
		stdout, stderr = [], []
		cmd = [ZFS.zfs_path].flatten + %w(get -ovalue -Hp) + [key.to_s, name]

		Open4::spawn(cmd, stdout: stdout, stderr: stderr)

		if stderr.empty? and stdout.size == 1
			return stdout.first.chomp
		else
			raise Exception, "something went wrong"
		end
	end

	def []=(key, value)
		stdout, stderr = [], []
		cmd = [ZFS.zfs_path].flatten + ['set', "#{key.to_s}=#{value}", name]

		Open4::spawn(cmd, stdout: stdout, stderr: stderr)

		if stderr.empty? and stdout.empty?
			return value
		else
			raise Exception, "something went wrong"
		end
	end

	class << self
		attr_accessor :zfs_path
		attr_accessor :zpool_path

		# Get an Array of all pools
		def pools
			stdout, stderr = [], []
			cmd = [ZFS.zpool_path].flatten + %w(list -Honame)

			Open4::spawn(cmd, stdout: stdout, stderr: stderr)

			stdout.collect do |pool|
				ZFS(pool.chomp)
			end
		end

		# Get a Hash of all mountpoints and their filesystems
		def mounts
			stdout, stderr = [], []
			cmd = [ZFS.zfs_path].flatten + %w(get -rHp -oname,value mountpoint)

			Open4::spawn(cmd, stdout: stdout, stderr: stderr)

			mounts = stdout.collect do |line|
				fs, path = line.chomp.split(/\t/, 2)
				[path, ZFS(fs)]
			end
			Hash[mounts]
		end

		# Define an attribute
		def property(name, opts={})

			case opts[:type]
			when :size, :integer
				# FIXME: also takes :values. if :values is all-Integers, these are the only options. if there are non-ints, then :values is a supplement

				define_method name do
					Integer(self[name])
				end
				define_method "#{name}=" do |value|
					self[name] = value.to_s
				end if opts[:edit]

			when :boolean
				# FIXME: booleans can take extra values, so there are on/true, off/false, plus what amounts to an enum
				# FIXME: if options[:values] is defined, also create a 'name' method, since 'name?' might not ring true
				# FIXME: replace '_' by '-' in opts[:values]
				define_method "#{name}?" do
					self[name] == 'on'
				end
				define_method "#{name}=" do |value|
					self[name] = value ? 'on' : 'off'
				end if opts[:edit]

			when :enum
				define_method name do
					sym = (self[name] || "").gsub('-', '_').to_sym
					if opts[:values].grep(sym)
						return sym
					else
						raise "#{name} has value #{sym}, which is not in enum-list"
					end
				end
				define_method "#{name}=" do |value|
					self[name] = value.to_s.gsub('_', '-')
				end if opts[:edit]

			when :snapshot
				define_method name do
					val = self[name]
					if val.nil? or val == '-'
						nil
					else
						ZFS(val)
					end
				end

			when :float
				define_method name do
					Float(self[name])
				end
				define_method "#{name}=" do |value|
					self[name] = value
				end if opts[:edit]

			when :string
				define_method name do
					self[name]
				end
				define_method "#{name}=" do |value|
					self[name] = value
				end if opts[:edit]

			when :date
				define_method name do
					DateTime.strptime(self[name], '%s')
				end

			when :pathname
				define_method name do
					Pathname(self[name])
				end
				define_method "#{name}=" do |value|
					self[name] = value.to_s
				end if opts[:edit]

			else
				puts "Unknown type '#{opts[:type]}'"
			end
		end
		private :property
	end

	property :available,            type: :size
	property :compressratio,        type: :float
	property :creation,             type: :date
	property :defer_destroy,        type: :boolean
	property :mounted,              type: :boolean
	property :origin,               type: :snapshot
	property :refcompressratio,     type: :float
	property :referenced,           type: :size
	property :type,                 type: :enum, values: [:filesystem, :snapshot, :volume]
	property :used,                 type: :size
	property :usedbychildren,       type: :size
	property :usedbydataset,        type: :size
	property :usedbyrefreservation, type: :size
	property :usedbysnapshots,      type: :size
	property :userrefs,             type: :integer

	property :aclinherit,           type: :enum,    edit: true, inherit: true, values: [:discard, :noallow, :restricted, :passthrough, :passthrough_x]
	property :atime,                type: :boolean, edit: true, inherit: true
	property :canmount,             type: :boolean, edit: true,                values: [:noauto]
	property :checksum,             type: :boolean, edit: true, inherit: true, values: [:fletcher2, :fletcher4, :sha256]
	property :compression,          type: :boolean, edit: true, inherit: true, values: [:lzjb, :gzip, :gzip_1, :gzip_2, :gzip_3, :gzip_4, :gzip_5, :gzip_6, :gzip_7, :gzip_8, :gzip_9, :zle]
	property :copies,               type: :integer, edit: true, inherit: true, values: [1, 2, 3]
	property :dedup,                type: :boolean, edit: true, inherit: true, values: [:verify, :sha256, 'sha256,verify']
	property :devices,              type: :boolean, edit: true, inherit: true
	property :exec,                 type: :boolean, edit: true, inherit: true
	property :logbias,              type: :enum,    edit: true, inherit: true, values: [:latency, :throughput]
	property :mlslabel,             type: :string,  edit: true, inherit: true
	property :mountpoint,           type: :pathname,edit: true, inherit: true
	property :nbmand,               type: :boolean, edit: true, inherit: true
	property :primarycache,         type: :enum,    edit: true, inherit: true, values: [:all, :none, :metadata]
	property :quota,                type: :size,    edit: true,                values: [:none]
	property :readonly,             type: :boolean, edit: true, inherit: true
	property :recordsize,           type: :integer, edit: true, inherit: true, values: [512, 1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072]
	property :refquota,             type: :size,    edit: true,                values: [:none]
	property :refreservation,       type: :size,    edit: true,                values: [:none]
	property :reservation,          type: :size,    edit: true,                values: [:none]
	property :secondarycache,       type: :enum,    edit: true, inherit: true, values: [:all, :none, :metadata]
	property :setuid,               type: :boolean, edit: true, inherit: true
	property :sharenfs,             type: :boolean, edit: true, inherit: true # FIXME: also takes 'share(1M) options'
	property :sharesmb,             type: :boolean, edit: true, inherit: true # FIXME: also takes 'sharemgr(1M) options'
	property :snapdir,              type: :enum,    edit: true, inherit: true, values: [:hidden, :visible]
	property :sync,                 type: :enum,    edit: true, inherit: true, values: [:standard, :always, :disabled]
	property :version,              type: :integer, edit: true,                values: [1, 2, 3, 4, :current]
	property :vscan,                type: :boolean, edit: true, inherit: true
	property :xattr,                type: :boolean, edit: true, inherit: true
	property :zoned,                type: :boolean, edit: true, inherit: true
	property :jailed,               type: :boolean, edit: true, inherit: true
	property :volsize,              type: :size,    edit: true

	property :casesensitivity,      type: :enum,    create_only: true, values: [:sensitive, :insensitive, :mixed]
	property :normalization,        type: :enum,    create_only: true, values: [:none, :formC, :formD, :formKC, :formKD]
	property :utf8only,             type: :boolean, create_only: true
	property :volblocksize,         type: :integer, create_only: true, values: [512, 1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072]
end


class ZFS::Snapshot < ZFS
	# Return sub-filesystem
	def +(path)
		raise InvalidName if path.match(/@/)

		parent + path + name.sub(/^.+@/, '@')
	end

	# Just remove the snapshot-name
	def parent
		ZFS(name.sub(/@.+/, ''))
	end

	# Rename snapshot
	def rename!(newname, opts={})
		raise AlreadyExists if (parent + "@#{newname}").exist?

		newname = (parent + "@#{newname}").name

		stdout, stderr = [], []
		cmd = [ZFS.zfs_path].flatten + ['rename']
		cmd << '-r' if opts[:children]
		cmd << name
		cmd << newname

		Open4::spawn(cmd, stdout: stdout, stderr: stderr)

		if stdout.empty? and stderr.empty?
			initialize(newname)
			return self
		else
			raise Exception, "something went wrong"
		end
	end

	# Clone snapshot
	def clone!(clone, opts={})
		clone = clone.name if clone.is_a? ZFS

		raise AlreadyExists if ZFS(clone).exist?

		stdout, stderr = [], []
		cmd = [ZFS.zfs_path].flatten + ['clone']
		cmd << '-p' if opts[:parents]
		cmd << name
		cmd << clone

		Open4::spawn(cmd, stdout: stdout, stderr: stderr)

		if stdout.empty? and stderr.empty?
			return ZFS(clone)
		else
			raise Exception, "something went wrong"
		end
	end

	def send_to(dest, opts={})
		incr_snap = nil

		# FIXME: use another exception
		if opts[:incremental] and opts[:intermediary]
			raise Exception, "can't specify both :incremental and :intermediary"
		end

		# FIXME: use another exception
		incr_snap = opts[:incremental] || opts[:intermediary]
		if incr_snap
			# FIXME (missing 'origin') raise Exception, "snapshot '#{incr_snap}' must exist at #{name}" unless origin.snapshots.grep(incr_snap)
			raise Exception, "snapshot '#{incr_snap} must exist at #{dest}" unless dest.snapshots.grep(incr_snap)
			# FIXME: must verify that incr_snap is the latest snapshot at +dest+
		end

		dest = dest.name unless dest.is_a? String

		send_opts = ZFS.zfs_path.flatten + ['send']
		send_opts.concat ['-i', incr_snap] if opts[:incremental]
		send_opts.concat ['-I', incr_snap] if opts[:intermediary]
		send_opts << '-R' if opts[:replication]
		send_opts << '-D' if opts[:dedup]
		send_opts << name

		receive_opts = ZFS.zfs_path.flatten + ['receive']
		receive_opts << '-F' if opts[:force]
		receive_opts << '-d' if opts[:remote_name]
		receive_opts << dest

		Open4::popen4(*receive_opts) do |rpid, rstdin, rstdout, rstderr|
			Open4::popen4(*send_opts) do |spid, sstdin, sstdout, sstderr|
				while !sstdout.eof?
					rstdin.write(sstdout.read(16384))
				end
				raise "stink" unless sstderr.read == ''
			end
		end
	end
end


class ZFS::Filesystem < ZFS
	# Return sub-filesystem.
	def +(path)
		if path.match(/^@/)
			ZFS("#{name.to_s}#{path}")
		else
			path = Pathname(name) + path
			ZFS(path.cleanpath.to_s)
		end
	end

	# Rename filesystem.
	def rename!(newname, opts={})
		raise AlreadyExists if ZFS(newname).exist?

		stdout, stderr = [], []
		cmd = [ZFS.zfs_path].flatten + ['rename']
		cmd << '-p' if opts[:parents]
		cmd << name
		cmd << newname

		Open4::spawn(cmd, stdout: stdout, stderr: stderr)

		if stdout.empty? and stderr.empty?
			initialize(newname)
			return self
		else
			raise Exception, "something went wrong"
		end
	end

	# Create a snapshot.
	def snapshot(snapname, opts={})
		raise NotFound, "no such filesystem" if !exist?
		raise AlreadyExists, "#{snapname} exists" if ZFS("#{name}@#{snapname}").exist?

		stdout, stderr = [], []
		cmd = [ZFS.zfs_path].flatten + ['snapshot']
		cmd << '-r' if opts[:children]
		cmd << "#{name}@#{snapname}"

		Open4::spawn(cmd, stdout: stdout, stderr: stderr)

		if stdout.empty? and stderr.empty?
			return ZFS("#{name}@#{snapname}")
		else
			raise Exception, "something went wrong"
		end
	end

	# Get an Array of all snapshots on this filesystem.
	def snapshots
		raise NotFound, "no such filesystem" if !exist?

		stdout, stderr = [], []
		cmd = [ZFS.zfs_path].flatten + %w(list -H -d1 -r -oname -tsnapshot) + [name]

		Open4::spawn(cmd, stdout: stdout, stderr: stderr)

		stdout.collect do |snap|
			ZFS(snap.chomp)
		end
	end

	# Promote this filesystem.
	def promote!
		raise NotFound, "filesystem is not a clone" if self.origin.nil?

		stdout, stderr = [], []
		cmd = [ZFS.zfs_path].flatten + ['promote', name]

		Open4::spawn(cmd, stdout: stdout, stderr: stderr)

		if stdout.empty? and stderr.empty?
			return self
		else
			raise Exception, "something went wrong"
		end
	end
end
