# -*- mode: ruby; tab-width: 2; indent-tabs-mode: nil -*-

require 'spec_helper'

# Basic list
describe ZFS do
  # Initially, the test-system has only 'tank', so this is what we're assuming here

  describe ".filesystems" do
    subject { ZFS.filesystems }
    it { should be_an_instance_of Enumerator }
    it "should list all filesystems" do
      subject.to_a.length.should eq 1
      subject.first.name.should eq "tank"
    end
  end

  describe ".mountpoints" do
    subject { ZFS.mountpoints }
    it { should be_an_instance_of Enumerator }
    it "should list all mountpoints" do
      subject.to_a.length.should eq 1
      subject.first[0].should eq "/tank"
      subject.first[1].should eq ZFS.filesystems.first
    end
  end

  it "should be able to fetch filesystems by zpool-path" do
    ZFS['tank'].should be_an_instance_of ZFS::Filesystem
  end

  it "should be able to fetch filesystems by mountpoint" do
    ZFS['/tank'].should eq ZFS['tank']
  end
end

# Basic create/destroy
describe ZFS do
  it "should be able to create filesystems" do
    ZFS.filesystems.to_a.length.should eq 1
    fs = ZFS.create("tank/fs1")
    ZFS.filesystems.to_a.length.should eq 2
    fs.destroy!
    ZFS.filesystems.to_a.length.should eq 1
  end
end

describe ZFS::Filesystem do
  it "should be valid across destroy/re-create" do
    fs = ZFS.create('tank/fs1')
    fs.should be_an_instance_of ZFS::Filesystem
    fs.should be_valid
    fs.destroy!
    fs.should_not be_valid

    fs2 = ZFS.create('tank/fs1')
    fs.should be_valid
    fs.should eq fs2
    fs.destroy!
    fs.should_not be_valid
  end
end

# Basic properties
describe ZFS do
  it "should support getting properties" do
    fs = ZFS['tank']
    fs.type.should eq :filesystem
  end

  it "should support setting properties"
  it "should convert on/off to true/false, and vice-versa" do
    ZFS['tank'].readonly?.should be_false
    ZFS['tank'].canmount?.should be_true
  end

  it "should convert 'creation' to DateTime" do
    ZFS['tank'].creation.should be_an_instance_of DateTime
  end

  it "should support custom properties"

  describe ZFS::Filesystem do
    it "should convert 'mountpoint' to Pathname" do
      ZFS['tank'].mountpoint.should eq Pathname("/tank")
    end

    it "should convert 'origin' to a ZFS::Filesystem on clones"
  end
end

# Tests with more filesystems
describe ZFS::Filesystem do
  include_context "scratch-filesystem"

  it "should be able to find specific filesystems" do
    ZFS['/tank'].to_s.should eq '#<ZFS:tank>'
    ZFS['/tank'].should eq ZFS['tank']

    ZFS['/tank/fs1'].to_s.should eq '#<ZFS:tank/fs1>'
    ZFS['/tank/fs1'].should eq ZFS['tank/fs1']
    ZFS['/tank/fs1'].should_not eq ZFS['/tank/fs2']

    # Find parent
    ZFS['/tank/fs1/dir1', true].should eq ZFS['/tank/fs1']
    ZFS['/tank/fs1/dir1', false].should be_nil
  end
end

describe ZFS::Filesystem do
  subject { ZFS['tank/fs1'] }

  include_context "scratch-filesystem"

  it "should support snapshots" do
    subject.snapshots.should eq []
    snapshot = subject.snapshot!('snap1')
    snapshots = subject.snapshots
    snapshot.should be_valid
    snapshot.destroy!
    snapshots.first.name.should eq 'tank/fs1@snap1'
    snapshot.should_not be_valid

    subject.snapshot!('snap1')
    subject.snapshot!('snap2')
    subject.snapshots.size.should eq 2
    subject.snapshots.each do |snap|
      snap.should be_an_instance_of ZFS::Snapshot
      snap.destroy!
    end
  end

  # FIXME: move to ZFS::Snapshot tests
  it "should support clones" do
    snapshot = subject.snapshot!('test')
    clone = snapshot.clone!('tank/clonefs')
    clone.should be_an_instance_of ZFS::Filesystem
    clone.should eq ZFS['/tank/clonefs']
    clone['origin'].should eq snapshot.name

    clone.destroy!
    ZFS['/tank/clonefs'].should be_nil

    snapshot.destroy!
    subject.snapshots.should eq []
  end

  it "should fail when attempting to create an existing filesystem" do
    expect { ZFS.create('tank/fs1') }.to raise_error("filesystem already exists")
  end
end

describe ZFS::Filesystem do
  it "supports renames" do
    fs = ZFS.create('tank/fs1')
    fs.rename!('tank/fs2')
    fs.should eq ZFS['tank/fs2']
    ZFS['tank/fs1'].should be_nil
    fs.destroy!
    fs.should_not be_valid
    ZFS['tank/fs2'].should be_nil
  end
end

describe ZFS::Snapshot do
  it "supports renames" do
    fs = ZFS.create('tank/fs1')
    snapshot = fs.snapshot!('snap1')
    fs.snapshots.should eq [ZFS['tank/fs1@snap1']]

    snapshot.rename!('snap2')
    fs.snapshots.should eq [ZFS['tank/fs1@snap2']]

    snapshot.destroy!
    fs.snapshots.should eq []

    fs.destroy!
  end

  it "should have a 'parent' property"
  it "should have a 'send_to' method"
end
