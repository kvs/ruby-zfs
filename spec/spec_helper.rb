# -*- mode: ruby; tab-width: 4; indent-tabs-mode: t -*-
$LOAD_PATH.push(File.expand_path('../lib/zfs'))

require 'zfs'
require 'open3'

shared_context "vagrant" do
	before(:all) do
		ZFS.zfs_path   = %w(sudo zfs)
		ZFS.zpool_path = %w(sudo zpool)
	end

	after(:all) do
		Open3.capture2e(*(ZFS.zfs_path+%w('destroy -r tank/foo'])))
		Open3.capture2e(*(ZFS.zfs_path+%w('destroy -r tank/bar')))

		ZFS.zfs_path   = 'zfs'
		ZFS.zpool_path = 'zpool'
	end
end
