#
#  Copyright 2009 10gen, Inc.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

package MongoDB::Connection;
our $VERSION = '0.22';

# ABSTRACT: A connection to a Mongo server

use MongoDB;
use Any::Moose;
use Digest::MD5;
use Tie::IxHash;

=attr host

Hostname to connect to. Defaults to C<localhost>.

=cut

has host => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
    default  => 'localhost',
);

=attr port

Port to use when connecting. Defaults to C<27017>.

=cut

has port => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
    default  => 27017,
);

=attr left_host

Paired connection host to connect to. Can be master or slave.

=cut

has left_host => (
    is       => 'ro',
    isa      => 'Str',
);

=attr left_port

Port to use when connecting to left_host. Defaults to C<27017>.

=cut

has left_port => (
    is       => 'ro',
    isa      => 'Int',
    default  => 27017,
);

=attr right_host

Paired connection host to connect to. Can be master or slave.

=cut

has right_host => (
    is       => 'ro',
    isa      => 'Str',
);

=attr right_port

Port to use when connecting to right_host. Defaults to C<27017>.

=cut

has right_port => (
    is       => 'ro',
    isa      => 'Int',
    default  => 27017,
);

has _server => (
    is       => 'ro',
    isa      => 'Str',
    lazy     => 1,
    builder  => '_build__server',
);

=attr auto_reconnect

Boolean indicating whether or not to reconnect if the connection is
interrupted. Defaults to C<1>.

=cut

has auto_reconnect => (
    is       => 'ro',
    isa      => 'Bool',
    required => 1,
    default  => 1,
);

=attr auto_connect

Boolean indication whether or not to connect automatically on object
construction. Defaults to C<1>.

=cut

has auto_connect => (
    is       => 'ro',
    isa      => 'Bool',
    required => 1,
    default  => 1,
);


sub _build__server {
    my ($self) = @_;
    my ($host, $port) = map { $self->$_ } qw/host port/;
    return "${host}:${port}";
}

sub BUILD {
    my ($self) = @_;
    eval "use ${_}" # no Any::Moose::load_class becase the namespaces already have symbols from the xs bootstrap
        for qw/MongoDB::Database MongoDB::Cursor MongoDB::OID/;
    $self->connect if $self->auto_connect;
}

=method connect

    $connection->connect;

Connects to the mongo server. Called automatically on object construction if
C<auto_connect> is true.

=cut

sub find_one {
    my ($self, $ns, $query) = @_;
    $query ||= {};
    return $self->_find_one($ns, $query);
}

sub query {
    my ($self, $ns, $query, $attrs) = @_;
    my ($limit, $skip, $sort_by) = @{ $attrs || {} }{qw/limit skip sort_by/};
    $limit   ||= 0;
    $skip    ||= 0;
    return $self->_query($ns, $query, $limit, $skip, $sort_by);
}

sub insert {
    my ($self, $ns, $object) = @_;
    confess 'not a hash reference' unless ref $object eq 'HASH';
    my %copy = %{ $object }; # a shallow copy is good enough. we won't modify anything deep down in the structure.
    $copy{_id} = MongoDB::OID->new unless exists $copy{_id};
    $self->_insert($ns, [\%copy]);
    return $copy{'_id'};
}

sub batch_insert {
    my ($self, $ns, $object) = @_;
    confess 'not an array reference' unless ref $object eq 'ARRAY';

    my @copies;
    my @ids;

    foreach my $obj (@{$object}) {
        confess 'not a hash reference' unless ref $obj eq 'HASH';

        my %copy = %{ $obj };
        $copy{'_id'} = MongoDB::OID->new unless exists $copy{'_id'};

        push @copies, \%copy;
        push @ids, $copy{'_id'};
    } 

    $self->_insert($ns, \@copies);
    return @ids;
}

sub update {
    my ($self, $ns, $query, $object, $upsert) = @_;
    $upsert = 0 unless defined $upsert;
    $self->_update($ns, $query, $object, $upsert);
    return;
}

sub remove {
    my ($self, $ns, $query) = @_;
    $self->_remove($ns, $query, 0);
    return;
}

{
    my %direction_map = (
        ascending  => 1,
        descending => -1,
    );

    sub ensure_index {
        my ($self, $ns, $keys, $direction, $unique) = @_;
        $direction ||= 'ascending';
        $unique = 0 unless defined $unique;

        my $k;
        my @name;
        if (ref $keys eq 'ARRAY' ||
            ref $keys eq 'HASH' ) {
            my %keys;
            if (ref $keys eq 'ARRAY') {
                %keys = map { ($_ => $direction) } @{ $keys };
            }
            else {
                %keys = %{ $keys };
            }

            $k = { map {
                my $dir = $keys{$_};
                confess "unknown direction '${dir}'"
                    unless exists $direction_map{$dir};
                ($_ => $direction_map{$dir})
            } keys %keys };

            while ((my $idx, my $d) = each(%$k)) {
                push @name, $idx;
                push @name, $d;
            }
        }
        elsif (ref $keys eq 'Tie::IxHash') {
            my @ks = $keys->Keys;
            my @vs = $keys->Values;

            for (my $i=0; $i<$keys->Length; $i++) {
                $keys->Replace($i, $direction_map{$vs[$i]});
            }

            @vs = $keys->Values;
            for (my $i=0; $i<$keys->Length; $i++) {
                push @name, $ks[$i];
                push @name, $vs[$i];
            }
            $k = $keys;
        }
        else {
            confess 'expected hash or array reference for keys';
        }

        my $obj = {"ns" => $ns,
                   "key" => $k,
                   "name" => join("_", @name)};

        $self->_ensure_index(substr($ns, 0, index($ns, ".")).".system.indexes", [$obj], $unique);
        return;
    }
}

=method database_names

    my @dbs = $connection->database_names;

Lists all databases on the mongo server.

=cut

sub database_names {
    my ($self) = @_;
    my $ret = $self->get_database('admin')->run_command({ listDatabases => 1 });
    return map { $_->{name} } @{ $ret->{databases} };
}

=method get_database ($name)

    my $database = $connection->get_database('foo');

Returns a C<MongoDB::Database> instance for database with the given C<$name>.

=cut

sub get_database {
    my ($self, $database_name) = @_;
    return MongoDB::Database->new(
        _connection => $self,
        name        => $database_name,
    );
}

=method find_master

    $connection->find_master

Determines which host of a paired connection is master.  Does nothing for
a non-paired connection.  Called automatically by internal functions.

=cut

sub find_master {
    my ($self) = @_;
    return unless defined $self->left_host && $self->right_host;
    my ($left, $right, $master);

    eval {
        $left = MongoDB::Connection->new("host" => $self->left_host, "port" => $self->left_port);
    };
    if (!($@ =~ m/couldn't connect to server/)) {
        $master = $left->find_one('admin.$cmd', {ismaster => 1});
        if ($master->{'ismaster'}) {    
            return 0;
        }
    }

    eval {
        $right = MongoDB::Connection->new("host" => $self->right_host, "port" => $self->right_port);
    };
    if (!($@ =~ m/couldn't connect to server/)) {
        $master = $right->find_one('admin.$cmd', {ismaster => 1});
        if ($master->{'ismaster'}) {
            return 1;
        }
    }

    # something went wrong
    return -1;
}

=method authenticate ($dbname, $username, $password, $is_digest?)

    $connection->authenticate('foo', 'username', 'secret');

Attempts to authenticate for use of the C<$dbname> database with C<$username>
and C<$password>. Passwords are expected to be cleartext and will be
automatically hashed before sending over the wire, unless C<$is_digest> is
true, which will assume you already did the hashing on yourself.

=cut

sub authenticate {
    my ($self, $dbname, $username, $password, $is_digest) = @_;
    my $hash = $password;
    if (!$is_digest) {
        $hash = Digest::MD5::md5_hex("${username}:mongo:${password}");
    }

    my $db = $self->get_database($dbname);
    my $result = $db->run_command({getnonce => 1});
    if (!$result->{'ok'}) {
        return $result;
    }

    my $nonce = $result->{'nonce'};
    my $digest = Digest::MD5::md5_hex($nonce.$username.$hash);

    my $login = tie(my %hash, 'Tie::IxHash');
    %hash = (authenticate => 1,
             user => $username, 
             nonce => $nonce,
             key => $digest);
    $result = $db->run_command($login);

    return $result;
}

no Any::Moose;
__PACKAGE__->meta->make_immutable;

1;
