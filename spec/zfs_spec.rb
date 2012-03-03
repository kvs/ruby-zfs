# -*- mode: ruby; tab-width: 4; indent-tabs-mode: t -*-
require 'spec_helper'

# NOTE! The ordering of the tests may be important, or at least significant.
# Example: we test create+snapshot, then destroy - in between, there is state left behind
# since we don't want to assume something works before it's been tested, to avoid very
# confusing errors in stuff other than what is being tested.
#
# We also test clones after snapshots, and promote! after clones and properties.


# Helper-method to return ZFS-instances
describe "ZFS()" do
	it "returns the correct instance" do
		ZFS('tank').should be_an_instance_of ZFS::Filesystem
		ZFS('tank@foo').should be_an_instance_of ZFS::Snapshot
	end

	it "supports Pathname's" do
		ZFS('tank').should eq ZFS(Pathname('tank'))
	end

	it "passes a ZFS as argument through untouched" do
		fs = ZFS('tank')
		ZFS(fs).should eq fs
	end
end


# Methods that don't require a live filesystem
describe ZFS do
	describe "#parent" do
		it "returns the correct parent" do
			ZFS('tank/foo/bar').parent.should eq ZFS('tank/foo')
			ZFS('tank/foo/bar@snap').parent.should eq ZFS('tank/foo/bar')
			ZFS('tank/foo/bar@snap').parent.parent.should eq ZFS('tank/foo')
		end
	end

	describe "#+" do
		it "returns an appended path" do
			(ZFS('tank/foo') + 'bar').should eq ZFS('tank/foo/bar')
			(ZFS('tank/foo') + '@bar').should eq ZFS('tank/foo@bar')
			(ZFS('tank/foo@baz') + 'bar').should eq ZFS('tank/foo/bar@baz')
			expect { (ZFS('tank/foo@baz') + '@bar') }.to raise_exception ZFS::InvalidName
		end
	end
end


# Methods that require a live filesystem.
describe ZFS do
	include_context "vagrant"

	describe "#create" do
		it "creates a filesystem, and returns the filesystem or nil if it already exists" do
			ZFS('tank/foo').should_not exist
			ZFS('tank/foo').create.should eq ZFS('tank/foo')
			ZFS('tank/foo').create.should be_nil
			ZFS('tank/foo').should exist
		end

		it "creates parents" do
			ZFS('tank/foo/bar/baz').create(parents: true).should exist
		end

		it "raises an error if parent does not exist"

		it "creates volumes" do
			ZFS('tank/foo/volume').create(volume: '10G').should_not be_nil
		end
	end

	describe "#snapshot" do
		it "creates a snapshot" do
			snapshot = ZFS('tank/foo').snapshot('qux')

			snapshot.should be_an_instance_of ZFS::Snapshot
		end

		it "creates a snapshot recursively" do
			ZFS('tank/foo').snapshot('quux', children: true)
			ZFS('tank/foo@quux').should exist
			ZFS('tank/foo/bar@quux').should exist
			ZFS('tank/foo/bar/baz@quux').should exist
		end

		it "should raise an exception if filesystem does not exist" do
			expect { ZFS('tank/none').snapshot('foo') }.to raise_error(ZFS::NotFound)
		end

		it "should raise an exception if snapshot already exists" do
			expect { ZFS('tank/foo').snapshot('quux') }.to raise_error(ZFS::AlreadyExists)
		end
	end

	describe "#destroy" do
		it "destroys snapshots" do
			ZFS('tank/foo/bar/baz@quux').should exist
			ZFS('tank/foo/bar/baz@quux').destroy!
			ZFS('tank/foo/bar/baz@quux').should_not exist
		end

		it "destroys filesystems" do
			ZFS('tank/foo/bar/baz').should exist
			ZFS('tank/foo/bar/baz').destroy!
			ZFS('tank/foo/bar/baz').should_not exist
		end

		it "destroys snapshots recursively" do
			ZFS('tank/foo@quux').should exist
			ZFS('tank/foo/bar@quux').should exist

			ZFS('tank/foo@quux').destroy!(children: true)

			ZFS('tank/foo@quux').should_not exist
			ZFS('tank/foo/bar@quux').should_not exist

			ZFS('tank/foo').should exist
			ZFS('tank/foo/bar').should exist
		end

		it "destroys filesystems recursively" do
			ZFS('tank/foo').destroy!(children: true)
			ZFS('tank/foo').should_not exist
		end

		it "should raise an exception if filesystem does not exist" do
			expect { ZFS('tank/none').destroy! }.to raise_error(ZFS::NotFound)
		end
	end

	describe "#snapshots" do
		it "returns a list of snapshots on a filesystem" do
			snapshot = ZFS('tank/foo').create.snapshot('bar')
			snapshot.should exist

			ZFS('tank/foo').snapshots.should eq [snapshot]

			snapshot2 = ZFS('tank/foo').snapshot('baz')

			ZFS('tank/foo').snapshots.should eq [snapshot, snapshot2]

			# Should only include direct descendants
			ZFS('tank/foo/bar').create.snapshot('baz')
			ZFS('tank/foo').snapshots.should eq [snapshot, snapshot2]

			snapshot.destroy!
			ZFS('tank/foo').snapshots.should eq [snapshot2]

			ZFS('tank/foo').destroy!(children: true)

			ZFS('tank/foo').should_not exist
		end

		it "should raise an exception if filesystem does not exist" do
			expect { ZFS('tank/none').snapshots }.to raise_error(ZFS::NotFound)
		end
	end

	describe "#children" do
		before(:all) do
			%w(tank/l1/ll1/lll1 tank/l1/ll2 tank/l2/ll2/lll2 tank/l3).each { |f| ZFS(f).create(parents: true) }
		end

		after(:all) do
			%w(tank/l1 tank/l2 tank/l3).each { |f| ZFS(f).destroy!(children: true) }
		end

		it "should raise an exception if filesystem does not exist" do
			expect { ZFS('tank/none').children }.to raise_error(ZFS::NotFound)
		end

		it "returns a list of immediate children" do
			ZFS('tank/l1').children.should eq [ZFS('tank/l1/ll1'), ZFS('tank/l1/ll2')]
			ZFS('tank').children.should eq [ZFS('tank/l1'), ZFS('tank/l2'), ZFS('tank/l3')]
		end

		it "returns a list of all children" do
			ZFS('tank/l1').children(recursive: true).should eq [ZFS('tank/l1/ll1'), ZFS('tank/l1/ll1/lll1'), ZFS('tank/l1/ll2')]
		end

		it "does not include snapshots" do
			ZFS('tank/l1').snapshot('test')
			ZFS('tank/l1').children.should eq [ZFS('tank/l1/ll1'), ZFS('tank/l1/ll2')]
		end
	end

	describe "#rename" do
		it "renames filesystems" do
			fs = ZFS('tank/foo').create
			fs.rename!('tank/bar')

			ZFS('tank/foo').should_not exist
			ZFS('tank/bar').should exist
			fs.should exist

			fs.name.should eq "tank/bar"

			fs.destroy!
		end

		it "renames filesystems and creates parents for new name" do
			fs = ZFS('tank/foo').create
			fs.rename!('tank/bar/baz/qux', parents: true)

			ZFS('tank/foo').should_not exist
			ZFS('tank/bar/baz/qux').should exist
			fs.should exist

			ZFS('tank/bar').destroy!(children: true)
		end

		it "renames snapshots" do
			snapshot = ZFS('tank/foo').create.snapshot('foo')
			snapshot.rename!('baz')
			ZFS('tank/foo').snapshots.should eq [ZFS('tank/foo@baz')]
			snapshot.name.should eq "tank/foo@baz"

			ZFS('tank/foo').destroy!(children: true)
		end

		it "renames snapshots recursively" do
			ZFS('tank/foo/bar/baz').create(parents: true)
			ZFS('tank/foo').snapshot('bar', children: true)

			ZFS('tank/foo/bar/baz@bar').should exist

			ZFS('tank/foo@bar').rename!('foo', children: true)

			ZFS('tank/foo/bar/baz@foo').should exist

			ZFS('tank/foo').destroy!(children: true)
		end

		it "throws an exception when new name is already used" do
			ZFS('tank/foo').create

			# Rename filesystem
			expect { ZFS('tank/bar').create.rename!('tank/foo') }.to raise_error ZFS::AlreadyExists

			# Rename snapshot
			snapshot = ZFS('tank/foo').snapshot('foo')
			ZFS('tank/foo').snapshot('bar')
			expect { snapshot.rename!('bar') }.to raise_error ZFS::AlreadyExists

			ZFS('tank/foo').destroy!(children: true)
			ZFS('tank/bar').destroy!
		end
	end

	describe ".pools" do
		it "returns an Array of all pools" do
			ZFS.pools.should eq [ZFS('tank')]

			# and only pools
			ZFS('tank/foo').create
			ZFS.pools.should eq [ZFS('tank')]
			ZFS('tank/foo').destroy!
		end
	end

	describe ".mounts" do
		it "returns a Hash of all mountpoints" do
			ZFS.mounts.should eq "/tank" => ZFS('tank')
		end
	end

	describe "#[]" do
		it "gets raw properties" do
			ZFS('tank')['type'].should eq 'filesystem'
		end
	end

	describe "#[]=" do
		it "sets raw properties" do
			ZFS('tank/foo').create
			ZFS('tank/foo')['exec'].should eq 'on'
			ZFS('tank/foo')['exec'] = 'off'
			ZFS('tank/foo')['exec'].should eq 'off'
			ZFS('tank/foo').destroy!
		end
	end

	describe "properties" do
		it "has helper functions" do
			ZFS('tank').type.should eq :filesystem
		end

		it "gets correct types" do
			ZFS('tank/foo').create
			ZFS('tank/foo').exec?.should be_true
			ZFS('tank/foo').origin.should be_nil
			ZFS('tank/foo').creation.should be_an_instance_of DateTime
			ZFS('tank/foo').referenced.should be_an_instance_of Fixnum
			ZFS('tank/foo').mountpoint.should eq Pathname('/tank/foo')

			ZFS('tank/foo').destroy!
		end

		it "sets correct types" do
			ZFS('tank/foo').create
			ZFS('tank/foo').exec?.should be_true
			ZFS('tank/foo').exec = false
			ZFS('tank/foo').exec?.should be_false

		end
	end
end

# Now that we've tested properties, we should be able to test fetching by mountpoint
describe "ZFS()" do
	include_context "vagrant"

	it "takes a mountpoint as argument" do
		ZFS('/tank').should eq ZFS('tank')
		ZFS('/tank').name.should eq 'tank'
		ZFS('tank/foo').create
		ZFS('/tank/foo').should eq ZFS('tank/foo')
		ZFS('tank/foo').destroy!
	end
end

describe ZFS::Snapshot do
	include_context "vagrant"

	describe "#clone" do
		it "raises an error when target already exists" do
			snapshot = ZFS('tank/foo').create.snapshot('foo')
			ZFS('tank/bar').create

			expect { snapshot.clone!('tank/bar') }.to raise_error ZFS::AlreadyExists

			ZFS('tank/foo').destroy!(children: true)
			ZFS('tank/bar').destroy!
		end

		it "clones a snapshot to a filesystem" do
			snapshot = ZFS('tank/foo').create.snapshot('foo')

			fs = snapshot.clone!('tank/bar')
			fs.should be_an_instance_of ZFS::Filesystem
			fs.should exist
			fs.should eq ZFS('tank/bar')

			fs.destroy!
			snapshot.destroy!
			ZFS('tank/foo').destroy!
		end

		it "creates parent-filesystems when requested" do
			snapshot = ZFS('tank/foo').create.snapshot('foo')

			fs = snapshot.clone!('tank/bar/baz', parents: true)
			fs.should be_an_instance_of ZFS::Filesystem
			fs.should exist
			fs.should eq ZFS('tank/bar/baz')

			fs.destroy!
			snapshot.destroy!
			ZFS('tank/foo').destroy!
			ZFS('tank/bar').destroy!(children: true)
		end

		it "returns a filesystem with a valid 'origin' property" do
			snapshot = ZFS('tank/foo').create.snapshot('foo')

			fs = snapshot.clone!('tank/bar')
			fs.should be_an_instance_of ZFS::Filesystem
			fs.origin.should eq snapshot

			fs.destroy!
			snapshot.destroy!
			ZFS('tank/foo').destroy!
		end

		it "accepts a ZFS as a valid destination" do
			snapshot = ZFS('tank/foo').create.snapshot('foo')

			fs = snapshot.clone!(ZFS('tank/bar'))
			fs.should be_an_instance_of ZFS::Filesystem
			fs.origin.should eq snapshot

			fs.destroy!
			snapshot.destroy!
			ZFS('tank/foo').destroy!
		end
	end

	describe "#send_to" do
		before(:all) do
			@source = ZFS('tank/foo').create
			@dest1  = ZFS('tank/bar').create
			@dest2  = ZFS('tank/baz')
			@sourcesnap = @source.snapshot('snapshot')
		end

		after(:all) do
			@source.destroy!(children: true)
			@dest1.destroy!(children: true)
			@dest2.destroy!(children: true) if @dest2.exist?
		end

		it "sends the snapshot to another filesystem" do
			@sourcesnap.send_to(@dest2)
			(@dest2 + '@snapshot').should exist
			@dest2.snapshots.should eq [(@dest2 + '@snapshot')]

			@dest2.destroy!(children: true)
		end

		it "raises an error if the destination filesystem exists when sending a full stream" do
			expect { @sourcesnap.send_to(@dest1) }.to raise_error ZFS::AlreadyExists
		end

		it "supports incremental/intermediary snapshots" do
			@sourcesnap.send_to(@dest2)

			snap2 = @source.snapshot('snapshot2')
			snap2.send_to(@dest2, incremental: @sourcesnap)
			snap2.should exist
			(@dest2 + '@snapshot2').should exist

			snap3 = @source.snapshot('snapshot3')
			snap3.send_to(@dest2, intermediary: @sourcesnap)
			snap3.should exist
			(@dest2 + '@snapshot3').should exist

			snap3.destroy!
			snap2.destroy!
			@dest2.destroy!(children: true)
		end

		it "raises an error when specifying invalid combinations of options" do
			expect { @sourcesnap.send_to(@dest1, incremental: @sourcesnap, intermediary: @sourcesnap) }.to raise_error ArgumentError
		end

		it "supports relative paths (Strings beginning with @) as incremental sources" do
			@sourcesnap.send_to(@dest2)

			snap2 = @source.snapshot('snapshot2')
			snap2.send_to(@dest2, incremental: '@snapshot')
			snap2.should exist
			(@dest2 + '@snapshot2').should exist

			snap3 = @source.snapshot('snapshot3')
			snap3.send_to(@dest2, intermediary: '@snapshot')
			snap3.should exist
			(@dest2 + '@snapshot3').should exist

			snap3.destroy!
			snap2.destroy!
			@dest2.destroy!(children: true)
		end

		it "raises an error if incremental snapshot isn't in the same filesystem as source" do
			s = @dest1.snapshot('foo')
			expect { @sourcesnap.send_to(@dest1, incremental: s) }.to raise_error ArgumentError
			s.destroy!
		end

		it "raises an error when filesystems/snapshots don't exist" do
			expect { @sourcesnap.send_to(@dest1, incremental: ZFS('tank/foo@none')) }.to raise_error ZFS::NotFound
			expect { @sourcesnap.send_to(@dest1, intermediary: ZFS('tank/foo@none')) }.to raise_error ZFS::NotFound
			expect { @sourcesnap.send_to(@dest2, intermediary: @sourcesnap) }.to raise_error ZFS::NotFound
		end

		it "supports replication streams" do
			source2 = (@source + 'sub').create
			source2.snapshot('snapshot')

			@sourcesnap.send_to(@dest2, replication: true)

			@dest2.should exist
			(@dest2 + 'sub@snapshot').should exist

			@dest2.destroy!(children: true)
		end

		it "supports 'receive -d'" do
			@sourcesnap.send_to(@dest1, use_sent_name: true)
			(@dest1 + 'foo').should exist
			(@dest1 + 'foo@snapshot').should exist
			(@dest1 + 'foo').destroy!(children: true)
		end

		it "raises an error when using 'receive -d' and destination is missing" do
			expect { @sourcesnap.send_to(@dest2, use_sent_name: true) }.to raise_error ZFS::NotFound
		end
	end
end

describe ZFS::Filesystem do
	include_context "vagrant"

	describe "#promote!" do
		it "promotes a clone" do
			snapshot = ZFS('tank/foo').create.snapshot('foo')

			fs = snapshot.clone!('tank/bar')
			fs.origin.should eq snapshot

			fs.promote!

			fs.origin.should be_nil
			snapshot.parent.origin.should eq fs + '@foo'

			snapshot.parent.destroy!
			fs.snapshots.first.destroy!
			fs.destroy!
		end

		it "raises an error if filesystem is not a clone" do
			expect { ZFS('tank/foo').create.promote! }.to raise_error ZFS::NotFound
			ZFS('tank/foo').destroy!
		end
	end
end
