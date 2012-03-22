# ruby-zfs

A library for interacting with ZFS, made in the spirit of Pathname.

Just like Pathname, it does not represent the filesystem itself, until you try to reference
it by calling methods on it. It can not, however, be relative - it is always an absolute reference
to a specific pool and path.

The only exception is when trying to reference a mountpoint by using a filesystem-path. In this
case, a ZFS object is only returned if the mountpoint exists. (eg. `ZFS('/tank/foo')`)

ZFS is mutable, and contains potentially very destructive methods.

## Usage

```ruby
	ZFS.pools                   # => [<ZFS:tank>]

	fs = ZFS('tank/foo')        # => <ZFS:tank/foo>
	fs.create                   # creates the filesystem
	fs.exist?                   # => true
	fs.name                     # => 'tank/foo'
	fs.mountpoint               # => '/tank/foo'

	ZFS('/tank/foo')            # => <ZFS:tank/foo>

	fs.parent                   # => <ZFS:tank>
	fs.parent.parent            # => nil

	fs.available                # returns bytes available in the filesystem
	fs.type                     # => :filesystem
	fs.checksum = :fletcher4
	fs.readonly = true
	fs.readonly?                # => true
	# plus all other properties defined in (currently) ZFS v28

	fs['org.freebsd:swap'] = 1  # sets the custom property 'org.freebsd:swap' to 1
	fs['org.freebsd:swap']      # => 1

	(fs + 'bar').create         # => <ZFS:tank/foo/bar>
	(fs + 'bar/baz').create     # => <ZFS:tank/foo/bar/baz>
	fs.children                 # => [<ZFS:tank/foo/bar]
	fs.children(recursive: true)# => [<ZFS:tank/foo/bar>, <ZFS:tank/foo/bar/baz>]

	s = fs.snapshot('snapname') # => <ZFS:tank/foo@snapname>
	s.parent                    # => <ZFS:tank/foo>
	fs.snapshots                # => [<ZFS:tank/foo@snapname>]
	s.destroy!                  # destroys snapshot

	# Take a recursive snapshot ('zfs snapshot -r')
	fs.snapshot('snapname', children: true)
	# => [<ZFS:tank/foo@snapname>, <ZFS:tank/foo/bar@snapname, ...]

	# Destroy a snapshot recursively
	ZFS('tank/foo@snapname').destroy!(children: true)

	s = fs.snapshot('snapname') # => <ZFS:tank/foo@snapname>
	fs2 = s.clone('tank/bar')   # => <ZFS:tank/bar>
	fs2.promote!

	fs2.rename('tank/baz')

	snapshot.send_to(fs)        # ZFS send/receive rolled into one - needs long description

	Still missing inherit, mount/unmount, share/unshare, and maybe send/receive

	# Shell out to `ssh`, and assume `zfs` and `zpool` is in path on remote host
	ZFS('tank/foo', hostname: 'foo.example.com')

	# Can be set to either a String or an Array
	ZFS.zfs_path                # => '/sbin/zfs'
	ZFS.zpool_path              # => '/sbin/zpool'
```

## Development

Uses a Vagrant VM with a custom Ubuntu + ZFS-on-Linux to do all the practical tests, to avoid thrashing any local ZFS-installations.

To get up and running, do the following:

* Install Vagrant (`gem install vagrant`, download a package, or add it to the Gemfile - your choice)
* Install [vagrant-proxyssh](https://github.com/kvs/vagrant-proxyssh)
* Run `rake bundle` to install gems inside the Vagrant VM
* Run `rake guard` to fire up [guard](https://github.com/guard/guard), and run tests inside the Vagrant VM.

Optional: add custom notification options to `.guardfile_private`.


## Bugs

* Currently, ZFS-objects aren't cached, so two instances can refer to the same filesystem. If mutable actions are called, only one is updated to reflect. (eg. rename!)
* Many commands take options, but do not warn/error if given invalid options
