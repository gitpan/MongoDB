#
#  Copyright 2009-2013 MongoDB, Inc.
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

package MongoDB::MongoClient;

# ABSTRACT: A connection to a MongoDB server or multi-server deployment

use version;
our $VERSION = 'v0.999.998.1'; # TRIAL

use Moose;
use MongoDB;
use MongoDB::Cursor;
use MongoDB::BSON::Binary;
use MongoDB::BSON::Regexp;
use MongoDB::Error;
use MongoDB::ReadPreference;
use MongoDB::WriteConcern;
use MongoDB::_Topology;
use MongoDB::_Credential;
use MongoDB::_URI;
use Digest::MD5;
use Tie::IxHash;
use Time::HiRes qw/usleep/;
use Carp 'carp', 'croak';
use Safe::Isa;
use Scalar::Util 'reftype';
use boolean;
use Encode;
use Try::Tiny;
use MongoDB::_Types;
use namespace::clean -except => 'meta';

use constant {
    PRIMARY             => 'primary',
    SECONDARY           => 'secondary',
    PRIMARY_PREFERRED   => 'primaryPreferred',
    SECONDARY_PREFERRED => 'secondaryPreferred',
    NEAREST             => 'nearest',
};

with 'MongoDB::Role::_Client';

#--------------------------------------------------------------------------#
# public attributes
#
# XXX too many of these are mutable
#--------------------------------------------------------------------------#

# connection attributes

#pod =attr host
#pod
#pod The C<host> attribute specifies either a single server to connect to (as
#pod C<hostname> or C<hostname:port>), or else a L<connection string URI|/CONNECTION
#pod STRING URI> with a seed list of one or more servers plus connection options.
#pod
#pod Defaults to the connection string URI C<mongodb://localhost:27017>.
#pod
#pod =cut

has host => (
    is      => 'ro',
    isa     => 'Str',
    default => 'mongodb://localhost:27017', # XXX eventually, make this localhost
);

#pod =attr port
#pod
#pod If a network port is not specified as part of the C<host> attribute, this
#pod attribute provides the port to use.  It defaults to 27107.
#pod
#pod =cut

has port => (
    is      => 'ro',
    isa     => 'Int',
    default => 27017,
);

#pod =attr connect_type
#pod
#pod Specifies the expected topology type of servers in the seed list.  The default
#pod is 'none'.
#pod
#pod Valid values include:
#pod
#pod =for :list
#pod * replicaSet – the topology is a replica set (ignore non replica set members
#pod   during discovery)
#pod * direct – the topology is a single server (connect as if the server is a
#pod   standlone, even if it looks like a replica set member)
#pod * none – discover the deployment topology by checking servers in the seed list
#pod   and connect accordingly
#pod
#pod =cut

has connect_type => (
    is      => 'ro',
    isa     => 'ConnectType',
    builder => '_build_connect_type',
    lazy    => 1
);

#pod =attr timeout
#pod
#pod Connection timeout in milliseconds. Defaults to C<20000>.
#pod
#pod =cut

has timeout => (
    is      => 'rw',
    isa     => 'Int',
    default => 20000,
);


#pod =attr query_timeout
#pod
#pod     # set query timeout to 1 second
#pod     my $client = MongoDB::MongoClient->new(query_timeout => 1000);
#pod
#pod     # set query timeout to 6 seconds
#pod     $client->query_timeout(6000);
#pod
#pod This will cause all queries (including C<find_one>s and C<run_command>s) to die
#pod after this period if the database has not responded.
#pod
#pod This value is in milliseconds and defaults to the value of
#pod L<MongoDB::Cursor/timeout>.
#pod
#pod     $MongoDB::Cursor::timeout = 5000;
#pod     # query timeout for $conn will be 5 seconds
#pod     my $client = MongoDB::MongoClient->new;
#pod
#pod A value of -1 will cause the driver to wait forever for responses and 0 will
#pod cause it to die immediately.
#pod
#pod This value overrides L<MongoDB::Cursor/timeout>.
#pod
#pod     $MongoDB::Cursor::timeout = 1000;
#pod     my $client = MongoDB::MongoClient->new(query_timeout => 10);
#pod     # timeout for $conn is 10 milliseconds
#pod
#pod =cut

has query_timeout => (
    is      => 'rw',
    isa     => 'Int',
    default => sub { return $MongoDB::Cursor::timeout; },
);

#pod =attr ssl
#pod
#pod     ssl => 1
#pod     ssl => \%ssl_options
#pod
#pod This tells the driver that you are connecting to an SSL mongodb instance.
#pod
#pod You must have L<IO::Socket::SSL> 1.42+ and L<Net::SSLeay> 1.49+ installed for
#pod SSL support.
#pod
#pod The C<ssl> attribute takes either a boolean value or a hash reference of
#pod options to pass to IO::Socket::SSL.  For example, to set a CA file to validate
#pod the server certificate and set a client certificate for the server to validate,
#pod you could set the attribute like this:
#pod
#pod     ssl => {
#pod         SSL_ca_file   => "/path/to/ca.pem",
#pod         SSL_cert_file => "/path/to/client.pem",
#pod     }
#pod
#pod If C<SSL_ca_file> is not provided, server certificates are verified against a
#pod default list of CAs, either L<Mozilla::CA> or an operating-system-specific
#pod default CA file.  To disable verification, you can use
#pod C<< SSL_verify_mode => 0x00 >>.
#pod
#pod B<You are strongly encouraged to use your own CA file for increased security>.
#pod
#pod Server hostnames are also validated against the CN name in the server
#pod certificate using C<< SSL_verifycn_scheme => 'default' >>.  You can use the
#pod scheme 'none' to disable this check.
#pod
#pod B<Disabling certificate or hostname verification is a security risk and is not
#pod recommended>.
#pod
#pod =cut

has ssl => (
    is      => 'ro',
    isa     => 'Bool|HashRef',
    default => 0,
    writer  => '_set_ssl',
);

# write concern attributes

#pod =attr w
#pod
#pod The client I<write concern>.
#pod
#pod =over 4
#pod
#pod =item * C<-1> Errors ignored. Do not use this.
#pod
#pod =item * C<0> Unacknowledged. MongoClient will B<NOT> wait for an acknowledgment that
#pod the server has received and processed the request. Older documentation may refer
#pod to this as "fire-and-forget" mode. You must call C<getLastError> manually to check
#pod if a request succeeds. This option is not recommended.
#pod
#pod =item * C<1> Acknowledged. This is the default. MongoClient will wait until the
#pod primary MongoDB acknowledges the write.
#pod
#pod =item * C<2> Replica acknowledged. MongoClient will wait until at least two
#pod replicas (primary and one secondary) acknowledge the write. You can set a higher
#pod number for more replicas.
#pod
#pod =item * C<all> All replicas acknowledged.
#pod
#pod =item * C<majority> A majority of replicas acknowledged.
#pod
#pod =back
#pod
#pod In MongoDB v2.0+, you can "tag" replica members. With "tagging" you can specify a
#pod new "getLastErrorMode" where you can create new
#pod rules on how your data is replicated. To used you getLastErrorMode, you pass in the
#pod name of the mode to the C<w> parameter. For more information see:
#pod http://www.mongodb.org/display/DOCS/Data+Center+Awareness
#pod
#pod =cut

has w => (
    is      => 'rw',
    isa     => 'Int|Str',
    default => 1,
    trigger => \&_update_write_concern,
);

#pod =attr wtimeout
#pod
#pod The number of milliseconds an operation should wait for C<w> slaves to replicate
#pod it.
#pod
#pod Defaults to 1000 (1 second).
#pod
#pod See C<w> above for more information.
#pod
#pod =cut

has wtimeout => (
    is      => 'rw',
    isa     => 'Int',
    default => 1000,
    trigger => \&_update_write_concern,
);

#pod =attr j
#pod
#pod If true, the client will block until write operations have been committed to the
#pod server's journal. Prior to MongoDB 2.6, this option was ignored if the server was
#pod running without journaling. Starting with MongoDB 2.6, write operations will fail
#pod if this option is used when the server is running without journaling.
#pod
#pod =cut

has j => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    trigger => \&_update_write_concern,
);

# server selection attributes

#pod =attr server_selection_timeout_ms
#pod
#pod This attribute specifies the amount of time in milliseconds to wait for a
#pod suitable server to be available for a read or write operation.  If no
#pod server is available within this time period, an exception will be thrown.
#pod
#pod The default is 30,000 ms.
#pod
#pod See L</SERVER SELECTION> for more details.
#pod
#pod =cut

has server_selection_timeout_ms => (
    is      => 'ro',
    isa     => 'Num',
    default => 30_000,
);

#pod =attr local_threshold_ms
#pod
#pod The width of the 'latency window': when choosing between multiple suitable
#pod servers for an operation, the acceptable delta in milliseconds between shortest
#pod and longest average round-trip times.  Servers within the latency window are
#pod selected randomly.
#pod
#pod Set this to "0" to always select the server with the shortest average round
#pod trip time.  Set this to a very high value to always randomly choose any known
#pod server.
#pod
#pod Defaults to 15 ms.
#pod
#pod See L</SERVER SELECTION> for more details.
#pod
#pod =cut

has local_threshold_ms => (
    is      => 'ro',
    isa     => 'Num',
    default => 15,
);

#pod =attr read_preference
#pod
#pod A L<MongoDB::ReadPreference> object, or a hash reference of attributes to
#pod construct such an object.  The default is mode 'primary'.
#pod
#pod For core documentation on read preference see
#pod L<http://docs.mongodb.org/manual/core/read-preference/>.
#pod
#pod B<The use of C<read_preference> as a mutator is deprecated.> If given a single
#pod argument that is a L<MongoDB::ReadPreference> object, the read preference is
#pod set to that object.  Otherwise, it takes positional arguments: the read
#pod preference mode and a tag set list, which must be a valid mode and tag set list
#pod as described in the L<MongoDB::ReadPreference> documentation.
#pod
#pod =cut

has read_preference => (
    is        => 'bare', # public reader implemented manually for back-compatibility
    isa       => 'ReadPreference',
    reader    => '_get_read_preference',
    writer    => '_set_read_preference',
    coerce    => 1,
    lazy      => 1,
    builder => '_build__read_preference',
);

sub _build__read_preference {
    my ($self) = @_;
    return MongoDB::ReadPreference->new;
}

sub read_preference {
    my $self = shift;

    if ( @_ ) {
        my $type = ref $_[0];
        if ( $type eq 'MongoDB::ReadPreference' ) {
            $self->_set_read_preference( $_[0] );
        }
        else {
            my $mode     = shift || 'primary';
            my $tag_sets = shift;
            my $rp       = MongoDB::ReadPreference->new(
                mode => $mode,
                ( $tag_sets ? ( tag_sets => $tag_sets ) : () )
            );
            $self->_set_read_preference($rp);
        }
    }

    return $self->_get_read_preference;
}

# server monitoring

#pod =attr heartbeat_frequency_ms
#pod
#pod The time in milliseconds between scans of all servers to check if they
#pod are up and update their latency.  Defaults to 60,000 ms.
#pod
#pod =cut

has heartbeat_frequency_ms => (
    is      => 'ro',
    isa     => 'Num',
    default => 60_000,
);

# authentication attributes

#pod =attr username
#pod
#pod Optional username for this client connection.  If this field is set, the client
#pod will attempt to authenticate when connecting to servers.  Depending on the
#pod L</auth_mechanism>, the L</password> field or other attributes will need to be
#pod set for authentication to succeed.
#pod
#pod =cut

has username => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    builder => '_build_username',
);

#pod =attr password
#pod
#pod If an L</auth_mechanism> requires a password, this attribute will be
#pod used.  Otherwise, it will be ignored.
#pod
#pod =cut

has password => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    builder => '_build_password',
);

#pod =attr db_name
#pod
#pod Optional.  If an L</auth_mechanism> requires a database for authentication,
#pod this attribute will be used.  Otherwise, it will be ignored. Defaults to
#pod "admin".
#pod
#pod =cut

has db_name => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    builder => '_build_db_name',
);

#pod =attr auth_mechanism
#pod
#pod This attribute determines how the client authenticates with the server.
#pod Valid values are:
#pod
#pod =for :list
#pod * NONE
#pod * DEFAULT
#pod * MONGODB-CR
#pod * MONGODB-X509
#pod * GSSAPI
#pod * PLAIN
#pod * SCRAM-SHA-1
#pod
#pod If not specified, then if no username is provided, it defaults to NONE.
#pod If a username is provided, it is set to DEFAULT, which chooses SCRAM-SHA-1 if
#pod available or MONGODB-CR otherwise.
#pod
#pod =cut

has auth_mechanism => (
    is      => 'ro',
    isa     => 'AuthMechanism',
    lazy    => 1,
    builder => '_build_auth_mechanism',
    writer  => '_set_auth_mechanism',
);

#pod =attr auth_mechanism_properties
#pod
#pod This is an optional hash reference of authentication mechanism specific properties.
#pod See L</AUTHENTICATION> for details.
#pod
#pod =cut

has auth_mechanism_properties => (
    is      => 'ro',
    isa     => 'HashRef',
    lazy    => 1,
    builder => '_build_auth_mechanism_properties',
    writer  => '_set_auth_mechanism_properties',
);

# BSON conversion attributes

#pod =attr dt_type
#pod
#pod Sets the type of object which is returned for DateTime fields. The default is
#pod L<DateTime>. Other acceptable values are L<DateTime::Tiny> and C<undef>. The
#pod latter will give you the raw epoch value rather than an object.
#pod
#pod =cut

has dt_type => (
    is      => 'rw',
    default => 'DateTime'
);


#pod =attr inflate_dbrefs
#pod
#pod Controls whether L<DBRef|http://docs.mongodb.org/manual/applications/database-references/#dbref>s
#pod are automatically inflated into L<MongoDB::DBRef> objects. Defaults to true.
#pod Set this to C<0> if you don't want to auto-inflate them.
#pod
#pod =cut

has inflate_dbrefs => (
    is      => 'rw',
    isa     => 'Bool',
    default => 1
);

#pod =attr inflate_regexps
#pod
#pod Controls whether regular expressions stored in MongoDB are inflated into L<MongoDB::BSON::Regexp> objects instead of native Perl Regexps. The default is false. This can be dangerous, since the JavaScript regexps used internally by MongoDB are of a different dialect than Perl's. The default for this attribute may become true in future versions of the driver.
#pod
#pod =cut

has inflate_regexps => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
);

#--------------------------------------------------------------------------#
# deprecated public attributes
#--------------------------------------------------------------------------#

#pod =attr auto_connect (DEPRECATED)
#pod
#pod This attribute no longer has any effect.  Connections always connect on
#pod demand.
#pod
#pod =cut

has auto_connect => (
    is      => 'ro',
    isa     => 'Bool',
    default => 1,
);

#pod =attr auto_reconnect (DEPRECATED)
#pod
#pod This attribute no longer has any effect.  Connections always reconnect on
#pod demand.
#pod
#pod =cut

has auto_reconnect => (
    is      => 'ro',
    isa     => 'Bool',
    default => 1,
);


#pod =attr find_master (DEPRECATED)
#pod
#pod This attribute no longer has any effect.  The driver will always attempt
#pod to find an appropriate server for every operation.
#pod
#pod =cut

has find_master => (
    is      => 'ro',
    isa     => 'Bool',
    default => 0,
);

#pod =attr sasl (DEPRECATED)
#pod
#pod If true, the driver will set the authentication mechanism based on the
#pod C<sasl_mechanism> property.
#pod
#pod =cut

has sasl => (
    is      => 'ro',
    isa     => 'Bool',
    default => 0
);

#pod =attr sasl_mechanism (DEPRECATED)
#pod
#pod This specifies the SASL mechanism to use for authentication with a MongoDB server.
#pod It has the same valid values as L</auth_mechanism>.  The default is GSSAPI.
#pod
#pod =cut

has sasl_mechanism => (
    is      => 'ro',
    isa     => 'AuthMechanism',
    default => 'GSSAPI',
);

#--------------------------------------------------------------------------#
# private attributes
#--------------------------------------------------------------------------#

has _topology => (
    is         => 'ro',
    isa        => 'MongoDB::_Topology',
    lazy_build => 1,
    handles    => { topology_type => 'type' },
    clearer    => '_clear__topology',
);

has _credential => (
    is         => 'ro',
    isa        => 'MongoDB::_Credential',
    builder    => '_build__credential',
    lazy       => 1,
    writer     => '_set__credential',
);

has _min_wire_version => (
    is      => 'ro',
    isa     => 'Int',
    default => 0
);

has _max_wire_version => (
    is      => 'ro',
    isa     => 'Int',
    default => 3
);

has _uri => (
    is      => 'ro',
    isa     => 'MongoDB::_URI',
    lazy    => 1,
    builder => '_build__uri',
);

has _write_concern => (
    is     => 'ro',
    isa    => 'MongoDB::WriteConcern',
    writer => '_set_write_concern',
);

#--------------------------------------------------------------------------#
# builders
#--------------------------------------------------------------------------#

sub _build_auth_mechanism {
    my ($self) = @_;

    if ( $self->sasl ) {
        # XXX support deprecated legacy experimental API
        return $self->sasl_mechanism;
    }
    elsif ( my $mech = $self->_uri->options->{authMechanism} ) {
        return $mech;
    }
    elsif ( $self->username ) {
        return 'DEFAULT';
    }
    else {
        return 'NONE';
    }
}

sub _build_auth_mechanism_properties {
    my ($self) = @_;
    my $service_name = $self->_uri->options->{'authMechanism.SERVICE_NAME'};
    return {
        ( defined $service_name ? ( SERVICE_NAME => $service_name ) : () ),
    };
}

sub _build__topology {
    my ($self) = @_;

    my $type =
        $self->connect_type eq 'replicaSet' ? 'ReplicaSetNoPrimary'
      : $self->connect_type eq 'direct'     ? 'Single'
      :                                       'Unknown';

    MongoDB::_Topology->new(
        uri                         => $self->_uri,
        type                        => $type,
        server_selection_timeout_ms => $self->server_selection_timeout_ms,
        latency_threshold_ms        => $self->local_threshold_ms,
        heartbeat_frequency_ms      => $self->heartbeat_frequency_ms,
        max_wire_version            => $self->_max_wire_version,
        min_wire_version            => $self->_min_wire_version,
        credential                  => $self->_credential,
        link_options                => {
            with_ssl   => !!$self->ssl,
            ( ref( $self->ssl ) eq 'HASH' ? ( SSL_options => $self->ssl ) : () ),
        },
    );
}

sub _build_connect_type {
    my ($self) = @_;
    return
      exists $self->_uri->options->{connect} ? $self->_uri->options->{connect} : 'none';
}

sub _build_db_name {
    my ($self) = @_;
    return $self->_uri->options->{authSource} || $self->_uri->db_name;
}

sub _build_password {
    my ($self) = @_;
    return $self->_uri->password;
}

sub _build_username {
    my ($self) = @_;
    return $self->_uri->username;
}

sub _build__credential {
    my ($self) = @_;
    my $mechanism = $self->auth_mechanism;
    my $cred = MongoDB::_Credential->new(
        mechanism            => $mechanism,
        mechanism_properties => $self->auth_mechanism_properties,
        ( $self->username ? ( username => $self->username ) : () ),
        ( $self->password ? ( password => $self->password ) : () ),
        ( $self->db_name  ? ( source   => $self->db_name )  : () ),
    );
    return $cred;
}

sub _build__uri {
    my ($self) = @_;
    if ( $self->host =~ m{^mongodb://} ) {
        return MongoDB::_URI->new( uri => $self->host );
    }
    else {
        my $uri = $self->host =~ /:\d+$/
                ? $self->host
                : sprintf("%s:%s", map { $self->$_ } qw/host port/ );
        return MongoDB::_URI->new( uri => ("mongodb://$uri") );
    }
}

sub BUILD {
    my ($self, $opts) = @_;

    my $uri = $self->_uri;

    my @addresses = @{ $uri->hostpairs };
    if ( $self->connect_type eq 'direct' && @addresses > 1 ) {
        confess "Connect type 'direct' cannot be used with multiple addresses: @addresses";
    }

    my $options = $uri->options;

    # Add options from URI
    $self->_set_ssl(_str_to_bool($options->{ssl}))  if exists $options->{ssl};
    $self->timeout($options->{connectTimeoutMS})    if exists $options->{connectTimeoutMS};
    $self->w($options->{w})                         if exists $options->{w};
    $self->wtimeout($options->{wtimeoutMS})         if exists $options->{wtimeoutMS};
    $self->j(_str_to_bool($options->{journal}))     if exists $options->{journal};

    $self->_update_write_concern;

    $self->read_preference( $options->{readPreference}, $options->{readPreferenceTags} )
        if exists $options->{readPreference} || exists $options->{readPreferenceTags};

    return;
}

#--------------------------------------------------------------------------#
# helper functions
#--------------------------------------------------------------------------#

sub _str_to_bool {
    my $str = shift;
    confess "cannot convert undef to bool" unless defined $str;
    my $ret = $str eq "true" ? 1 : $str eq "false" ? 0 : undef;
    return $ret unless !defined $ret;
    confess "expected boolean string 'true' or 'false' but instead received '$str'";
}

sub _use_write_cmd {
    my ($link) = @_;
    return $link->min_wire_version <= 2 && 2 <= $link->max_wire_version;
}

#--------------------------------------------------------------------------#
# public methods - network communication
#--------------------------------------------------------------------------#

#pod =method connect
#pod
#pod     $client->connect;
#pod
#pod Calling this method is unnecessary, as connections are established
#pod automatically as needed.  It is kept for backwards compatibility.  Calling it
#pod will check all servers in the deployment which ensures a connection to any
#pod that are available.
#pod
#pod =cut

sub connect {
    my ($self) = @_;
    $self->_topology->scan_all_servers;
    return 1;
}

#pod =method disconnect
#pod
#pod     $client->disconnect;
#pod
#pod Drops all connections to servers.
#pod
#pod =cut

sub disconnect {
    my ($self) = @_;
    $self->_topology->close_all_links;
    return 1;
}

#--------------------------------------------------------------------------#
# semi-private methods; these are public but undocumented and their
# semantics might change in future releases
#--------------------------------------------------------------------------#

sub send_admin_command {
    my ($self, $command, $flags, $read_preference) = @_;

    $read_preference ||= MongoDB::ReadPreference->new;
    my $link = $self->_topology->get_readable_link( $read_preference );
    my $query = MongoDB::_Query->new( spec => $command );
    $self->_apply_read_prefs( $link, $query, $flags, $read_preference );

    return $self->_try_operation('_send_admin_command', $link, $query->spec, $flags );
}

sub send_command {
    my ($self, $db, $command, $flags, $read_preference) = @_;

    $read_preference ||= MongoDB::ReadPreference->new;
    my $link = $self->_topology->get_readable_link( $read_preference );
    my $query = MongoDB::_Query->new( spec => $command );
    $self->_apply_read_prefs( $link, $query, $flags, $read_preference );

    return $self->_try_operation('_send_command', $link, $db, $query->spec, $flags );
}

sub send_delete {
    my ( $self, $ns, $op_doc, $write_concern ) = @_;
    # $op_doc is { q: $query, limit: $limit }

    $write_concern ||= $self->_write_concern;
    my $link = $self->_topology->get_writable_link;

    return $self->_try_operation('_send_delete', $link, $ns, $op_doc, $write_concern );
}

sub send_get_more {
    my ( $self, $address, $ns, $cursor_id, $size ) = @_;

    my $link = $self->_topology->get_specific_link( $address );

    return $self->_try_operation('_send_get_more', $link, $ns, $cursor_id, $size, $self );
}

sub send_insert {
    my ( $self, $ns, $docs, $write_concern, $flags, $check_keys ) = @_;

    $docs = [ $docs ] unless ref $docs eq 'ARRAY'; # XXX from BulkWrite

    $write_concern ||= $self->_write_concern;
    my $link = $self->_topology->get_writable_link;

    return $self->_try_operation('_send_insert', $link, $ns, $docs, $flags, $check_keys, $write_concern );
}

sub send_kill_cursors {
    my ( $self, $address, @cursors ) = @_;

    my $link = $self->_topology->get_specific_link( $address );

    return $self->_try_operation('_send_kill_cursors', $link, @cursors );
}

sub send_update {
    my ( $self, $ns, $op_doc, $write_concern ) = @_;
    # $op_doc is { q: $query, u: $update, multi: $multi, upsert: $upsert }

    $write_concern ||= $self->_write_concern;
    my $link = $self->_topology->get_writable_link;

    return $self->_try_operation('_send_update', $link, $ns, $op_doc, $write_concern );
}

# XXX eventually, passing $self to _send_query should go away and we should
# pass in a BSON codec object
sub send_query {
    my ($self, $ns, $query, $fields, $skip, $limit, $batch_size, $flags, $read_preference) = @_;

    $read_preference ||= $self->_read_preference || MongoDB::ReadPreference->new;
    my $link = $self->_topology->get_readable_link( $read_preference );

    $self->_apply_read_prefs( $link, $query, $flags, $read_preference );

    return $self->_try_operation('_send_query', $link, $ns, $query->spec, $fields, $skip, $limit, $batch_size, $flags, $self );
}

# variants is a hash of wire protocol version to coderef
sub send_versioned_read {
    my ( $self, $variants, $read_preference ) = @_;

    $read_preference ||= MongoDB::ReadPreference->new;
    my $link = $self->_topology->get_readable_link($read_preference);

    # try highest protocol versions first
    for my $version ( sort { $b <=> $a } keys %$variants ) {
        if ( $link->accepts_wire_version($version) ) {
            return $variants->{$version}->($self, $link);
        }
    }

    MongoDB::Error->throw(
        sprintf(
            "Wire protocol error: server %s selected but doesn't accept protocol(s) %",
            join( ", ", keys %$variants ),
            $link->address
        )
    );
}

sub _apply_read_prefs {
    my ( $self, $link, $query, $flags, $read_preference ) = @_;

    if ( $link->server->type eq 'Mongos' ) {
        if ( $read_preference->has_empty_tag_sets ) {
            if ( $read_preference->mode eq 'primary' ) {
                $flags->{slave_ok} = 0;
            }
            elsif ( $read_preference->mode eq 'secondaryPreferred' ) {
                $flags->{slave_ok} = 1;
            }
            else {
                $query->set_modifier( '$readPreference' => $read_preference->for_mongos );
            }
        }
        else {
            $query->set_modifier( '$readPreference' => $read_preference->for_mongos );
        }
    }
    else {
        $flags->{slave_ok} = 1 if $read_preference->mode ne 'primary';
    }
}

sub _try_operation {
    my ($self, $method, $link, @args) = @_;

    my $result = try {
        $self->$method($link, @args);
    }
    catch {
        if ( $_->$_isa("MongoDB::ConnectionError") ) {
            $self->_topology->mark_server_unknown( $link->server, $_ );
        }
        elsif ( $_->$_isa("MongoDB::NotMasterError") ) {
            $self->_topology->mark_server_unknown( $link->server, $_ );
            $self->_topology->mark_stale;
        }
        # regardless of cleanup, rethrow the error
        die $_;
    };

    return $result;
}

#--------------------------------------------------------------------------#
# bulk operations
#--------------------------------------------------------------------------#

# XXX this can be a wrapper to grab link, write concern, and sizes off the
# link and then move the bulk of this code to _Client

sub send_bulk_queue {
    my ($self, %args) = @_;

    my $ns = $args{ns};
    my $queue = $args{queue} || [];
    my $ordered = $args{ordered};
    my $write_concern = $args{write_concern} || $self->_write_concern;

    my $link = $self->_topology->get_writable_link;

    my $use_write_cmd = _use_write_cmd($link);

    # If using legacy write ops, then there will never be a valid nModified
    # result so we set that to undef in the constructor; otherwise, we set it
    # to 0 so that results accumulate normally. If a mongos on a mixed topology
    # later fails to set it, results merging will handle it that case.
    my $result = MongoDB::WriteResult->new( nModified => $use_write_cmd ? 0 : undef, );

    for my $batch ( $ordered ? $self->_batch_ordered($link, $queue) : $self->_batch_unordered($link, $queue) ) {
        if ($use_write_cmd) {
            $self->_execute_write_command_batch( $link, $ns, $batch, $result, $ordered, $write_concern );
        }
        else {
            $self->_execute_legacy_batch( $link, $ns, $batch, $result, $ordered, $write_concern );
        }
    }

    # only reach here with an error for unordered bulk ops
    $result->assert_no_write_error;

    # write concern errors are thrown only for the entire batch
    $result->assert_no_write_concern_error;

    return $result;
}

my %OP_MAP = (
    insert => [ insert => 'documents' ],
    update => [ update => 'updates' ],
    delete => [ delete => 'deletes' ],
);

# _execute_write_command_batch may split batches if they are too large and
# execute them separately

sub _execute_write_command_batch {
    my ( $self, $link, $ns, $batch, $result, $ordered, $write_concern ) = @_;

    my ( $type, $docs )   = @$batch;
    my ( $cmd,  $op_key ) = @{ $OP_MAP{$type} };

    my $boolean_ordered = $ordered ? boolean::true : boolean::false;
    my ($db_name, $coll_name) = $ns =~ m{^([^.]+)\.(.*)$};

    my @left_to_send = ($docs);

    while (@left_to_send) {
        my $chunk = shift @left_to_send;

        my $cmd_doc = [
            $cmd    => $coll_name,
            $op_key => $chunk,
            ordered => $boolean_ordered,
            ( $write_concern ? ( writeConcern => $write_concern->as_struct ) : () )
        ];

        my $cmd_result = try {
            $self->send_command($db_name, $cmd_doc);
        }
        catch {
            if ( $_->$_isa("MongoDB::_CommandSizeError") ) {
                if ( @$chunk == 1 ) {
                    MongoDB::DocumentSizeError->throw(
                        message  => "document too large",
                        document => $chunk->[0],
                    );
                }
                else {
                    unshift @left_to_send, $self->_split_chunk( $link, $chunk, $_->size );
                }
            }
            else {
                die $_;
            }
            return;
        };

        redo unless $cmd_result; # restart after a chunk split

        my $r = MongoDB::WriteResult->_parse(
            op       => $type,
            op_count => scalar @$chunk,
            result   => $cmd_result,
        );

        # append corresponding ops to errors
        if ( $r->count_writeErrors ) {
            for my $error ( @{ $r->writeErrors } ) {
                $error->{op} = $chunk->[ $error->{index} ];
                # convert boolean::true|false back to 1 or 0
                for my $k (qw/upsert multi/) {
                    $error->{op}{$k} = 0+ $error->{op}{$k} if exists $error->{op}{$k};
                }
            }
        }

        $result->_merge_result($r);
        $result->assert_no_write_error if $ordered;
    }

    return;
}

sub _split_chunk {
    my ( $self, $link, $chunk, $size ) = @_;

    my $max_wire_size = $self->MAX_BSON_WIRE_SIZE; # XXX blech

    my $avg_cmd_size       = $size / @$chunk;
    my $new_cmds_per_chunk = int( $max_wire_size / $avg_cmd_size );

    my @split_chunks;
    while (@$chunk) {
        push @split_chunks, [ splice( @$chunk, 0, $new_cmds_per_chunk ) ];
    }

    return @split_chunks;
}

sub _batch_ordered {
    my ($self, $link, $queue) = @_;
    my @batches;
    my $last_type = '';
    my $count     = 0;

    my $max_batch_count = $link->max_write_batch_size;

    for my $op ( @$queue ) {
        my ( $type, $doc ) = @$op;
        if ( $type ne $last_type || $count == $max_batch_count ) {
            push @batches, [ $type => [$doc] ];
            $last_type = $type;
            $count     = 1;
        }
        else {
            push @{ $batches[-1][-1] }, $doc;
            $count++;
        }
    }

    return @batches;
}

sub _batch_unordered {
    my ($self, $link, $queue) = @_;
    my %batches = map { ; $_ => [ [] ] } keys %OP_MAP;

    my $max_batch_count = $link->max_write_batch_size;

    for my $op ( @$queue ) {
        my ( $type, $doc ) = @$op;
        if ( @{ $batches{$type}[-1] } == $max_batch_count ) {
            push @{ $batches{$type} }, [$doc];
        }
        else {
            push @{ $batches{$type}[-1] }, $doc;
        }
    }

    # insert/update/delete are guaranteed to be in random order on Perl 5.18+
    my @batches;
    for my $type ( grep { scalar @{ $batches{$_}[-1] } } keys %batches ) {
        push @batches, map { [ $type => $_ ] } @{ $batches{$type} };
    }
    return @batches;
}

sub _execute_legacy_batch {
    my ( $self, $link, $ns, $batch, $result, $ordered, $write_concern ) = @_;
    my ( $type, $docs ) = @$batch;

    my $method = "send_$type";

    # if write concern is not safe, we have to proxy with a safe one so that
    # we can interrupt ordered bulks, even while ignoring the actual error
    my $w_0;
    if ( ! $write_concern->is_safe ) {
        my $wc = $write_concern->as_struct;
        $wc->{w} = 1;
        $w_0 = MongoDB::WriteConcern->new( $wc );
    }

    # XXX successive inserts ought to get batched up, up to the max size for batch,
    # but we have no feedback on max size to know how many to put together. I wonder
    # if send_insert should return a list of write results, or if it should just
    # strip out however many docs it can from an arrayref and leave the rest, and
    # then this code can iterate.

    for my $doc (@$docs) {

        # legacy server doesn't check keys on insert; we fake an error if it happens
        if ( $type eq 'insert' && ( my $r = $self->_check_no_dollar_keys($doc) ) ) {
            if ($w_0) {
                last if $ordered;
            }
            else {
                $result->_merge_result($r);
                $result->assert_no_write_error if $ordered;
            }
            next;
        }

        my $gle_result = try {
            $self->$method( $ns, $doc, $w_0 ? $w_0 : $write_concern );
        }
        catch {
            die $_ unless $w_0 && /exceeds maximum size/;
            undef;
        };

        # Even for {w:0}, if the batch is ordered we have to break on the first
        # error, but we don't throw the error to the user.
        if ( $w_0 ) {
            last if $ordered && (!$gle_result || $gle_result->count_writeErrors);
        }
        else {
            $result->_merge_result($gle_result);
            $result->assert_no_write_error if $ordered;
        }
    }

    return;
}

sub _check_no_dollar_keys {
    my ( $self, $doc ) = @_;

    my @keys = ref $doc eq 'Tie::IxHash' ? $doc->Keys : keys %$doc;
    if ( my @bad = grep { substr( $_, 0, 1 ) eq '$' } @keys ) {
        my $errdoc = {
            index  => 0,
            errmsg => "Document can't have '\$' prefixed field names: @bad",
            code   => UNKNOWN_ERROR
        };

        return MongoDB::WriteResult->new(
            op_count    => 1,
            nModified   => undef,
            writeErrors => [$errdoc]
        );
    }

    return;
}


#--------------------------------------------------------------------------#
# write concern methods
#--------------------------------------------------------------------------#

sub _update_write_concern {
    my ($self) = @_;
    my $wc = MongoDB::WriteConcern->new(
        w        => $self->w,
        wtimeout => $self->wtimeout,
        ( $self->j ? ( j => $self->j ) : () ),
    );
    $self->_set_write_concern($wc);
}

#--------------------------------------------------------------------------#
# database helper methods
#--------------------------------------------------------------------------#

#pod =method database_names
#pod
#pod     my @dbs = $client->database_names;
#pod
#pod Lists all databases on the MongoDB server.
#pod
#pod =cut

sub database_names {
    my ($self) = @_;

    my @databases;
    my $max_tries = 3;
    for my $try ( 1 .. $max_tries ) {
        last if try {
            my $result = $self->get_database('admin')->_try_run_command({ listDatabases => 1 });
            if (ref($result) eq 'HASH' && exists $result->{databases}) {
                @databases = map { $_->{name} } @{ $result->{databases} };
            }
            return 1;
        } catch {
            # can't open db in a read lock
            return if $_->{result}->{result}{code} == CANT_OPEN_DB_IN_READ_LOCK() || $try < $max_tries;
            die $_;
        };
    }

    return @databases;
}

#pod =method get_database($name)
#pod
#pod     my $database = $client->get_database('foo');
#pod
#pod Returns a L<MongoDB::Database> instance for the database with the given C<$name>.
#pod
#pod =cut

sub get_database {
    my ($self, $database_name) = @_;
    return MongoDB::Database->new(
        _client     => $self,
        name        => $database_name,
    );
}

#pod =method fsync(\%args)
#pod
#pod     $client->fsync();
#pod
#pod A function that will forces the server to flush all pending writes to the storage layer.
#pod
#pod The fsync operation is synchronous by default, to run fsync asynchronously, use the following form:
#pod
#pod     $client->fsync({async => 1});
#pod
#pod The primary use of fsync is to lock the database during backup operations. This will flush all data to the data storage layer and block all write operations until you unlock the database. Note: you can still read while the database is locked.
#pod
#pod     $conn->fsync({lock => 1});
#pod
#pod =cut

sub fsync {
    my ($self, $args) = @_;

    $args ||= {};

    # Pass this in as array-ref to ensure that 'fsync => 1' is the first argument.
    return $self->get_database('admin')->run_command([fsync => 1, %$args]);
}

#pod =method fsync_unlock
#pod
#pod     $conn->fsync_unlock();
#pod
#pod Unlocks a database server to allow writes and reverses the operation of a $conn->fsync({lock => 1}); operation.
#pod
#pod =cut

sub fsync_unlock {
    my ($self) = @_;

    # Have to fetch from a special collection to unlock.
    return $self->get_database('admin')->get_collection('$cmd.sys.unlock')->find_one();
}

#pod =method authenticate (DEPRECATED)
#pod
#pod     $client->authenticate($dbname, $username, $password, $is_digest);
#pod
#pod B<This legacy method is deprecated but kept for backwards compatibility.>
#pod
#pod Instead, authentication credentials should be provided as constructor arguments
#pod or as part of the connection URI.
#pod
#pod When C<authenticate> is called, it disconnects the client (if any connections
#pod had been made), sets client attributes as if the username and password had been
#pod used initially in the client constructor, and reconnects to the configured
#pod servers.  The authentication mechanism will be MONGO-CR for servers before
#pod version 2.8 and SCRAM-SHA-1 for 2.8 or later.
#pod
#pod Passwords are expected to be cleartext and will be automatically hashed before
#pod sending over the wire, unless C<$is_digest> is true, which will assume you
#pod already did the proper hashing yourself.
#pod
#pod See also the L</AUTHENTICATION> section.
#pod
#pod =cut

sub authenticate {
    my ( $self, $db_name, $username, $password, $is_digest ) = @_;

    # set client properties
    $self->_set_auth_mechanism('DEFAULT');
    $self->_set_auth_mechanism_properties( {} );
    $self->db_name($db_name);
    $self->username($username);
    $self->password($password);

    my $cred = MongoDB::_Credential->new(
        mechanism            => $self->auth_mechanism,
        mechanism_properties => $self->auth_mechanism_properties,
        username             => $self->username,
        password             => $self->password,
        source               => $self->db_name,
        pw_is_digest         => $is_digest,
    );
    $self->_set__credential($cred);

    # ensure that we've authenticated by clearing the topology and trying a
    # command that opens a socket
    $self->_clear__topology;
    $self->send_admin_command( { ismaster => 1 } );

    return 1;
}

__PACKAGE__->meta->make_immutable( inline_destructor => 0 );

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

MongoDB::MongoClient - A connection to a MongoDB server or multi-server deployment

=head1 VERSION

version v0.999.998.1

=head1 SYNOPSIS

    use MongoDB; # also loads MongoDB::MongoClient

    # connect to localhost:27017
    my $client = MongoDB::MongoClient->new;

    # connect to specific host and port
    my $client = MongoDB::MongoClient->new(
        host => "mongodb://mongo.example.com:27017"
    );

    my $db = $client->get_database("test");
    my $coll = $db->get_collection("people");

    $coll->insert({ name => "John Doe", age => 42 });
    my @people = $coll->find()->all();

=head1 DESCRIPTION

The C<MongoDB::MongoClient> class represents a client connection to one or
more MongoDB servers.

By default, it connects to a single server running on the local machine
listening on the default port 27017:

    # connects to localhost:27017
    my $client = MongoDB::MongoClient->new;

It can connect to a database server running anywhere, though:

    my $client = MongoDB::MongoClient->new(host => 'example.com:12345');

See the L</"host"> attribute for more options for connecting to MongoDB.

MongoDB can be started in L<authentication
mode|http://docs.mongodb.org/manual/core/authentication/>, which requires
clients to log in before manipulating data.  By default, MongoDB does not start
in this mode, so no username or password is required to make a fully functional
connection.  To configure the client for authentication, see the
L</AUTHENTICATION> section.

The actual socket connections are lazy and created on demand.  When the client
object goes out of scope, all socket will be closed.  Note that
L<MongoDB::Database>, L<MongoDB::Collection> and related classes could hold a
reference to the client as well.  Only when all references are out of scope
will the sockets be closed.

=head1 ATTRIBUTES

=head2 host

The C<host> attribute specifies either a single server to connect to (as
C<hostname> or C<hostname:port>), or else a L<connection string URI|/CONNECTION
STRING URI> with a seed list of one or more servers plus connection options.

Defaults to the connection string URI C<mongodb://localhost:27017>.

=head2 port

If a network port is not specified as part of the C<host> attribute, this
attribute provides the port to use.  It defaults to 27107.

=head2 connect_type

Specifies the expected topology type of servers in the seed list.  The default
is 'none'.

Valid values include:

=over 4

=item *

replicaSet – the topology is a replica set (ignore non replica set members during discovery)

=item *

direct – the topology is a single server (connect as if the server is a standlone, even if it looks like a replica set member)

=item *

none – discover the deployment topology by checking servers in the seed list and connect accordingly

=back

=head2 timeout

Connection timeout in milliseconds. Defaults to C<20000>.

=head2 query_timeout

    # set query timeout to 1 second
    my $client = MongoDB::MongoClient->new(query_timeout => 1000);

    # set query timeout to 6 seconds
    $client->query_timeout(6000);

This will cause all queries (including C<find_one>s and C<run_command>s) to die
after this period if the database has not responded.

This value is in milliseconds and defaults to the value of
L<MongoDB::Cursor/timeout>.

    $MongoDB::Cursor::timeout = 5000;
    # query timeout for $conn will be 5 seconds
    my $client = MongoDB::MongoClient->new;

A value of -1 will cause the driver to wait forever for responses and 0 will
cause it to die immediately.

This value overrides L<MongoDB::Cursor/timeout>.

    $MongoDB::Cursor::timeout = 1000;
    my $client = MongoDB::MongoClient->new(query_timeout => 10);
    # timeout for $conn is 10 milliseconds

=head2 ssl

    ssl => 1
    ssl => \%ssl_options

This tells the driver that you are connecting to an SSL mongodb instance.

You must have L<IO::Socket::SSL> 1.42+ and L<Net::SSLeay> 1.49+ installed for
SSL support.

The C<ssl> attribute takes either a boolean value or a hash reference of
options to pass to IO::Socket::SSL.  For example, to set a CA file to validate
the server certificate and set a client certificate for the server to validate,
you could set the attribute like this:

    ssl => {
        SSL_ca_file   => "/path/to/ca.pem",
        SSL_cert_file => "/path/to/client.pem",
    }

If C<SSL_ca_file> is not provided, server certificates are verified against a
default list of CAs, either L<Mozilla::CA> or an operating-system-specific
default CA file.  To disable verification, you can use
C<< SSL_verify_mode => 0x00 >>.

B<You are strongly encouraged to use your own CA file for increased security>.

Server hostnames are also validated against the CN name in the server
certificate using C<< SSL_verifycn_scheme => 'default' >>.  You can use the
scheme 'none' to disable this check.

B<Disabling certificate or hostname verification is a security risk and is not
recommended>.

=head2 w

The client I<write concern>.

=over 4

=item * C<-1> Errors ignored. Do not use this.

=item * C<0> Unacknowledged. MongoClient will B<NOT> wait for an acknowledgment that
the server has received and processed the request. Older documentation may refer
to this as "fire-and-forget" mode. You must call C<getLastError> manually to check
if a request succeeds. This option is not recommended.

=item * C<1> Acknowledged. This is the default. MongoClient will wait until the
primary MongoDB acknowledges the write.

=item * C<2> Replica acknowledged. MongoClient will wait until at least two
replicas (primary and one secondary) acknowledge the write. You can set a higher
number for more replicas.

=item * C<all> All replicas acknowledged.

=item * C<majority> A majority of replicas acknowledged.

=back

In MongoDB v2.0+, you can "tag" replica members. With "tagging" you can specify a
new "getLastErrorMode" where you can create new
rules on how your data is replicated. To used you getLastErrorMode, you pass in the
name of the mode to the C<w> parameter. For more information see:
http://www.mongodb.org/display/DOCS/Data+Center+Awareness

=head2 wtimeout

The number of milliseconds an operation should wait for C<w> slaves to replicate
it.

Defaults to 1000 (1 second).

See C<w> above for more information.

=head2 j

If true, the client will block until write operations have been committed to the
server's journal. Prior to MongoDB 2.6, this option was ignored if the server was
running without journaling. Starting with MongoDB 2.6, write operations will fail
if this option is used when the server is running without journaling.

=head2 server_selection_timeout_ms

This attribute specifies the amount of time in milliseconds to wait for a
suitable server to be available for a read or write operation.  If no
server is available within this time period, an exception will be thrown.

The default is 30,000 ms.

See L</SERVER SELECTION> for more details.

=head2 local_threshold_ms

The width of the 'latency window': when choosing between multiple suitable
servers for an operation, the acceptable delta in milliseconds between shortest
and longest average round-trip times.  Servers within the latency window are
selected randomly.

Set this to "0" to always select the server with the shortest average round
trip time.  Set this to a very high value to always randomly choose any known
server.

Defaults to 15 ms.

See L</SERVER SELECTION> for more details.

=head2 read_preference

A L<MongoDB::ReadPreference> object, or a hash reference of attributes to
construct such an object.  The default is mode 'primary'.

For core documentation on read preference see
L<http://docs.mongodb.org/manual/core/read-preference/>.

B<The use of C<read_preference> as a mutator is deprecated.> If given a single
argument that is a L<MongoDB::ReadPreference> object, the read preference is
set to that object.  Otherwise, it takes positional arguments: the read
preference mode and a tag set list, which must be a valid mode and tag set list
as described in the L<MongoDB::ReadPreference> documentation.

=head2 heartbeat_frequency_ms

The time in milliseconds between scans of all servers to check if they
are up and update their latency.  Defaults to 60,000 ms.

=head2 username

Optional username for this client connection.  If this field is set, the client
will attempt to authenticate when connecting to servers.  Depending on the
L</auth_mechanism>, the L</password> field or other attributes will need to be
set for authentication to succeed.

=head2 password

If an L</auth_mechanism> requires a password, this attribute will be
used.  Otherwise, it will be ignored.

=head2 db_name

Optional.  If an L</auth_mechanism> requires a database for authentication,
this attribute will be used.  Otherwise, it will be ignored. Defaults to
"admin".

=head2 auth_mechanism

This attribute determines how the client authenticates with the server.
Valid values are:

=over 4

=item *

NONE

=item *

DEFAULT

=item *

MONGODB-CR

=item *

MONGODB-X509

=item *

GSSAPI

=item *

PLAIN

=item *

SCRAM-SHA-1

=back

If not specified, then if no username is provided, it defaults to NONE.
If a username is provided, it is set to DEFAULT, which chooses SCRAM-SHA-1 if
available or MONGODB-CR otherwise.

=head2 auth_mechanism_properties

This is an optional hash reference of authentication mechanism specific properties.
See L</AUTHENTICATION> for details.

=head2 dt_type

Sets the type of object which is returned for DateTime fields. The default is
L<DateTime>. Other acceptable values are L<DateTime::Tiny> and C<undef>. The
latter will give you the raw epoch value rather than an object.

=head2 inflate_dbrefs

Controls whether L<DBRef|http://docs.mongodb.org/manual/applications/database-references/#dbref>s
are automatically inflated into L<MongoDB::DBRef> objects. Defaults to true.
Set this to C<0> if you don't want to auto-inflate them.

=head2 inflate_regexps

Controls whether regular expressions stored in MongoDB are inflated into L<MongoDB::BSON::Regexp> objects instead of native Perl Regexps. The default is false. This can be dangerous, since the JavaScript regexps used internally by MongoDB are of a different dialect than Perl's. The default for this attribute may become true in future versions of the driver.

=head2 auto_connect (DEPRECATED)

This attribute no longer has any effect.  Connections always connect on
demand.

=head2 auto_reconnect (DEPRECATED)

This attribute no longer has any effect.  Connections always reconnect on
demand.

=head2 find_master (DEPRECATED)

This attribute no longer has any effect.  The driver will always attempt
to find an appropriate server for every operation.

=head2 sasl (DEPRECATED)

If true, the driver will set the authentication mechanism based on the
C<sasl_mechanism> property.

=head2 sasl_mechanism (DEPRECATED)

This specifies the SASL mechanism to use for authentication with a MongoDB server.
It has the same valid values as L</auth_mechanism>.  The default is GSSAPI.

=head1 METHODS

=head2 connect

    $client->connect;

Calling this method is unnecessary, as connections are established
automatically as needed.  It is kept for backwards compatibility.  Calling it
will check all servers in the deployment which ensures a connection to any
that are available.

=head2 disconnect

    $client->disconnect;

Drops all connections to servers.

=head2 database_names

    my @dbs = $client->database_names;

Lists all databases on the MongoDB server.

=head2 get_database($name)

    my $database = $client->get_database('foo');

Returns a L<MongoDB::Database> instance for the database with the given C<$name>.

=head2 fsync(\%args)

    $client->fsync();

A function that will forces the server to flush all pending writes to the storage layer.

The fsync operation is synchronous by default, to run fsync asynchronously, use the following form:

    $client->fsync({async => 1});

The primary use of fsync is to lock the database during backup operations. This will flush all data to the data storage layer and block all write operations until you unlock the database. Note: you can still read while the database is locked.

    $conn->fsync({lock => 1});

=head2 fsync_unlock

    $conn->fsync_unlock();

Unlocks a database server to allow writes and reverses the operation of a $conn->fsync({lock => 1}); operation.

=head2 authenticate (DEPRECATED)

    $client->authenticate($dbname, $username, $password, $is_digest);

B<This legacy method is deprecated but kept for backwards compatibility.>

Instead, authentication credentials should be provided as constructor arguments
or as part of the connection URI.

When C<authenticate> is called, it disconnects the client (if any connections
had been made), sets client attributes as if the username and password had been
used initially in the client constructor, and reconnects to the configured
servers.  The authentication mechanism will be MONGO-CR for servers before
version 2.8 and SCRAM-SHA-1 for 2.8 or later.

Passwords are expected to be cleartext and will be automatically hashed before
sending over the wire, unless C<$is_digest> is true, which will assume you
already did the proper hashing yourself.

See also the L</AUTHENTICATION> section.

=head1 DEPLOYMENT TOPOLOGY

MongoDB can operate as a single server or as a distributed system.  One or more
servers that collectively provide access to a single logical set of MongoDB
databases are referred to as a "deployment".

There are three types of deployments:

=over 4

=item *

Single server – a stand-alone mongod database

=item *

Replica set – a set of mongod databases with data replication and fail-over capability

=item *

Sharded cluster – a distributed deployment that spreads data across one or more shards, each of which can be a replica set.  Clients communicate with a mongos process that routes operations to the correct share.

=back

The state of a deployment, including its type, which servers are members, the
server types of members and the round-trip network latency to members is
referred to as the "topology" of the deployment.

To the greatest extent possible, the MongoDB driver abstracts away the details
of communicating with different deployment types.  It determines the deployment
topology through a combination of the connection string, configuration options
and direct discovery communicating with servers in the deployment.

=head1 CONNECTION STRING URI

MongoDB uses a pseudo-URI connection string to specify one or more servers to
connect to, along with configuration options.

To connect to more than one database server, provide host or host:port pairs
as a comma separated list:

    mongodb://host1[:port1][,host2[:port2],...[,hostN[:portN]]]

This list is referred to as the "seed list".  An arbitrary number of hosts can
be specified.  If a port is not specified for a given host, it will default to
27017.

If multiple hosts are given in the seed list or discovered by talking to
servers in the seed list, they must all be replica set members or must all be
mongos servers for a sharded cluster.

If a single, non-replica-set server is found, or if the L</connect_type> (or
C<connect> URI option) is 'direct', the deployment is treated as a single
server deployment.  For a replica set member, forcing the connection type to be
'direct' routes all operations to it alone; this is useful for carrying out
administrative activities on that server.

The connection string may also have a username and password:

    mongodb://username:password@host1:port1,host2:port2

The username and password must be URL-escaped.

A optional database name for authentication may be given:

    mongodb://username:password@host1:port1,host2:port2/my_database

Finally, connection string options may be given as URI attribute pairs in a query
string:

    mongodb://host1:port1,host2:port2/?ssl=1&wtimeoutMS=1000
    mongodb://username:password@host1:port1,host2:port2/my_database?ssl=1&wtimeoutMS=1000

The currently supported connection string options are:

=over 4

*authMechanism
*authMechanism.SERVICE_NAME
*connect
*connectTimeoutMS
*journal
*readPreference
*readPreferenceTags
*ssl
*w
*wtimeoutMS

=back

See the official MongoDB documentation on connection strings for more on the URI
format and connection string options:
L<http://docs.mongodb.org/manual/reference/connection-string/>.

=head1 SERVER SELECTION

For a single server deployment or a direct connection to a mongod or mongos, all
reads and writes and sent to that server.  Any read-preference is ignored.

When connected to a deployment with multiple servers, such as a replica set or
sharded cluster, the driver chooses a server for operations based on the type of
operation (read or write), the types of servers available and a read preference.

For a replica set deployment, writes are sent to the primary (if available) and
reads are sent to a server based on the L</read_preference> attribute, which default
to sending reads to the primary.  See L<MongoDB::ReadPreference> for more.

For a sharded cluster reads and writes are distributed across mongos servers in
the seed list.  Any read preference is passed through to the mongos and used
by it when executing reads against shards.

If multiple servers can service an operation (e.g. multiple mongos servers,
or multiple replica set members), one is chosen at random from within the
"latency window".  The server with the shortest average round-trip time (RTT)
is always in the window.  Any servers with an average round-trip time less than
or equal to the shortest RTT plus the L</local_threshold_ms> are also in the
latency window.

If a server is not immediately available, the driver will block for up to
L</server_selection_timeout_ms> milliseconds waiting for a suitable server to
become available.  If no server is available at the end of that time, an
exception is thrown.

=head1 SERVER MONITORING

When the client first needs to find a server for a database operation, all
servers from the L</host> attribute are scanned to determine which servers to
monitor.  If the deployment is a replica set, additional hosts may be
discovered in this process.  Invalid hosts are dropped.

After the initial scan, whenever the servers have not been checked in
L</heartbeat_frequency_ms> milliseconds, the scan will be repeated.  This
amortizes monitoring time over many of operations.

Additionally, if a socket has been idle for a while, it will be checked
before being used for an operation.

If an server operation fails because of a "not master" or "node is recovering"
error, the server is flagged as unavailable.  Assuming the error is caught and
handled, the next operation will rescan all servers immediately to find a new
primary.

Whenever a server is found to be unavailable, the driver records this fact, but
can continue to function as long as other servers are suitable per L</SERVER
SELECTION>.

=head1 AUTHENTICATION

The MongoDB server provides several authentication mechanisms, though some
are only available in the Enterprise edition.

MongoDB client authentication is controlled via the L</auth_mechanism>
attribute, which takes one of the following values:

=over 4

=item *

MONGODB-CR -- legacy username-password challenge-response

=item *

SCRAM-SHA-1 -- secure username-password challenge-response (2.8+)

=item *

MONGODB-X509 -- SSL client certificate authentication (2.6+)

=item *

PLAIN -- LDAP authentication via SASL PLAIN (Enterprise only)

=item *

GSSAPI -- Kerberos authentication (Enterprise only)

=back

The mechanism to use depends on the authentication configuration of the
server.  See the core documentation on authentication:
L<http://docs.mongodb.org/manual/core/access-control/>.

Usage information for each mechanism is given below.

=head2 MONGODB-CR and SCRAM-SHA-1 (for username/password)

These mechnisms require a username and password, given either as
constructor attributes or in the C<host> connection string.

If a username is provided and an authentication mechanism is not specified,
the client will use SCRAM-SHA-1 for version 2.8 or later servers and will
fall back to MONGODB-CR for older servers.

    my $mc = MongoDB::MongoClient->new(
        host => "mongodb://mongo.example.com/",
        username => "johndoe",
        password => "trustno1",
    );

    my $mc = MongoDB::MongoClient->new(
        host => "mongodb://johndoe:trustno1@mongo.example.com/",
    );

Usernames and passwords will be UTF-8 encoded before use.  The password is
never sent over the wire -- only a secure digest is used.  The SCRAM-SHA-1
mechanism is the Salted Challenge Response Authentication Mechanism
definedin L<RFC 5802|http://tools.ietf.org/html/rfc5802>.

The default database for authentication is 'admin'.  If another database
name should be used, specify it with the C<db_name> attribute or via the
connection string.

    db_name => auth_db

    mongodb://johndoe:trustno1@mongo.example.com/auth_db

=head2 MONGODB-X509 (for SSL client certificate)

X509 authentication requires SSL support (L<IO::Socket::SSL>) and requires
that a client certificate be configured and that the username attribute be
set to the "Subject" field, formatted according to RFC 2253.  To find the
correct username, run the C<openssl> program as follows:

  $ openssl x509 -in certs/client.pem -inform PEM -subject -nameopt RFC2253
  subject= CN=XXXXXXXXXXX,OU=XXXXXXXX,O=XXXXXXX,ST=XXXXXXXXXX,C=XX

In this case the C<username> attribute would be
C<CN=XXXXXXXXXXX,OU=XXXXXXXX,O=XXXXXXX,ST=XXXXXXXXXX,C=XX>.

Configure your client with the correct username and ssl parameters, and
specify the "MONGODB-X509" authentication mechanism.

    my $mc = MongoDB::MongoClient->new(
        host => "mongodb://sslmongo.example.com/",
        ssl => {
            SSL_ca_file   => "certs/ca.pem",
            SSL_cert_file => "certs/client.pem",
        },
        auth_mechanism => "MONGODB-X509",
        username       => "CN=XXXXXXXXXXX,OU=XXXXXXXX,O=XXXXXXX,ST=XXXXXXXXXX,C=XX"
    );

=head2 PLAIN (for LDAP)

This mechanism requires a username and password, which will be UTF-8
encoded before use.  The C<auth_mechanism> parameter must be given as a
constructor attribute or in the C<host> connection string:

    my $mc = MongoDB::MongoClient->new(
        host => "mongodb://mongo.example.com/",
        username => "johndoe",
        password => "trustno1",
        auth_mechanism => "PLAIN",
    );

    my $mc = MongoDB::MongoClient->new(
        host => "mongodb://johndoe:trustno1@mongo.example.com/authMechanism=PLAIN",
    );

=head2 GSSAPI (for Kerberos)

Kerberos authentication requires the CPAN module L<Authen::SASL> and a
GSSAPI-capable backend.

On Debian systems, L<Authen::SASL> may be available as
C<libauthen-sasl-perl>; on RHEL systems, it may be available as
C<perl-Authen-SASL>.

The L<Authen::SASL::Perl> backend comes with L<Authen::SASL> and requires
the L<GSSAPI> CPAN module for GSSAPI support.  On Debian systems, this may
be available as C<libgssapi-perl>; on RHEL systems, it may be available as
C<perl-GSSAPI>.

Installing the L<GSSAPI> module from CPAN rather than an OS package
requires C<libkrb5> and the C<krb5-config> utility (available for
Debian/RHEL systems in the C<libkrb5-dev> package).

Alternatively, the L<Authen::SASL::XS> or L<Authen::SASL::Cyrus> modules
may be used.  Both rely on Cyrus C<libsasl>.  L<Authen::SASL::XS> is
preferred, but not yet available as an OS package.  L<Authen::SASL::Cyrus>
is available on Debian as C<libauthen-sasl-cyrus-perl> and on RHEL as
C<perl-Authen-SASL-Cyrus>.

Installing L<Authen::SASL::XS> or L<Authen::SASL::Cyrus> from CPAM requires
C<libsasl>.  On Debian systems, it is available from C<libsasl2-dev>; on
RHEL, it is available in C<cyrus-sasl-devel>.

To use the GSSAPI mechanism, first run C<kinit> to authenticate with the ticket
granting service:

    $ kinit johndoe@EXAMPLE.COM

Configure MongoDB::MongoClient with the principal name as the C<username>
parameter and specify 'GSSAPI' as the C<auth_mechanism>:

    my $mc = MongoDB::MongoClient->new(
        host => 'mongodb://mongo.example.com',
        username => 'johndoe@EXAMPLE.COM',
        auth_mechanism => 'GSSAPI',
    );

Both can be specified in the C<host> connection string, keeping in mind
that the '@' in the principal name must be encoded as "%40":

    my $mc = MongoDB::MongoClient->new(
        host =>
          'mongodb://johndoe%40EXAMPLE.COM@mongo.examplecom/?authMechanism=GSSAPI',
    );

The default service name is 'mongodb'.  It can be changed with the
C<auth_mechanism_properties> attribute or in the connection string.

    auth_mechanism_properties => { SERVICE_NAME => 'other_service' }

    mongodb://.../?authMechanism=GSSAPI&authMechanism.SERVICE_NAME=other_service

=head1 THREAD-SAFETY AND FORK-SAFETY

Existing connections to servers are closed after forking or spawning a thread.  They
will reconnect on demand.

=head1 AUTHORS

=over 4

=item *

David Golden <david@mongodb.com>

=item *

Mike Friedman <friedo@mongodb.com>

=item *

Kristina Chodorow <kristina@mongodb.com>

=item *

Florian Ragwitz <rafl@debian.org>

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2014 by MongoDB, Inc..

This is free software, licensed under:

  The Apache License, Version 2.0, January 2004

=cut
