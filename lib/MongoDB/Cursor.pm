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

package MongoDB::Cursor;


# ABSTRACT: A lazy cursor for Mongo query results

use version;
our $VERSION = 'v0.999.998.1'; # TRIAL

use Moose;
use MongoDB;
use MongoDB::BSON;
use MongoDB::Error;
use MongoDB::QueryResult;
use MongoDB::_Protocol;
use MongoDB::_Types;
use boolean;
use Tie::IxHash;
use Try::Tiny;
use namespace::clean -except => 'meta';

use constant {
    CURSOR_ZERO => "\0" x 8,
    FLAG_ZERO => "\0" x 4,
};

#pod =head1 NAME
#pod
#pod MongoDB::Cursor - A cursor/iterator for Mongo query results
#pod
#pod =head1 SYNOPSIS
#pod
#pod     while (my $object = $cursor->next) {
#pod         ...
#pod     }
#pod
#pod     my @objects = $cursor->all;
#pod
#pod =head2 Multithreading
#pod
#pod Cursors are cloned in threads, but not reset.  Iterating the same cursor from
#pod multiple threads will give unpredictable results.  Only iterate from a single
#pod thread.
#pod
#pod =head1 SEE ALSO
#pod
#pod Core documentation on cursors: L<http://dochub.mongodb.org/core/cursors>.
#pod
#pod =cut

$MongoDB::Cursor::_request_id = int(rand(1000000));

#pod =head1 STATIC ATTRIBUTES
#pod
#pod =head2 slave_okay
#pod
#pod     $MongoDB::Cursor::slave_okay = 1;
#pod
#pod Whether it is okay to run queries on the slave.  Defaults to 0.
#pod
#pod =cut

$MongoDB::Cursor::slave_okay = 0;

#pod =head2 timeout
#pod
#pod B<Deprecated, use MongoDB::MongoClient::query_timeout instead.>
#pod
#pod How many milliseconds to wait for a response from the server.  Set to 30000
#pod (30 seconds) by default.  -1 waits forever (or until TCP times out, which is
#pod usually a long time).
#pod
#pod This value is overridden by C<MongoDB::MongoClient::query_timeout> and never
#pod used.
#pod
#pod =cut

$MongoDB::Cursor::timeout = 30000;

#pod =head1 ATTRIBUTES
#pod
#pod =head2 started_iterating
#pod
#pod If this cursor has queried the database yet. Methods
#pod modifying the query will complain if they are called
#pod after the database is queried.
#pod
#pod =cut

with 'MongoDB::Role::_Cursor';

# general attributes

has _client => (
    is => 'rw',
    isa => 'MongoDB::MongoClient',
    required => 1,
);

has _ns => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

# attributes for sending a query

has _query => (
    is => 'rw',
    isa => 'MongoDBQuery',
    required => 1,
    coerce => 1,
    writer => '_set_query',
);

has _fields => (
    is => 'rw',
    required => 0,
);

has _limit => (
    is => 'rw',
    isa => 'Int',
    required => 0,
    default => 0,
);

has _batch_size => (
    is => 'rw',
    isa => 'Int',
    required => 0,
    default => 0,
);

has _skip => (
    is => 'rw',
    isa => 'Int',
    required => 0,
    default => 0,
);

has _query_options => (
    is => 'ro',
    isa => 'HashRef',
    default => sub { { slave_ok => !! $MongoDB::Cursor::slave_okay } },
);

has _read_preference => (
    is      => 'ro',
    isa     => 'ReadPreference',
    lazy    => 1,
    builder => '_build__read_preference',
    writer  => '_set_read_preference',
);

sub _build__read_preference {
    my ($self) = @_;
    return $self->_client->read_preference;
}

# lazy result attribute
has result => (
    is        => 'ro',
    isa       => 'MongoDB::QueryResult',
    lazy      => 1,
    builder   => '_build_result',
    predicate => 'started_iterating',
    clearer   => '_clear_result',
);

# this does the query if it hasn't been done yet
sub _build_result {
    my ($self) = @_;
    return $self->_client->send_query(
        $self->_ns,
        $self->_query,
        $self->_fields,
        $self->_skip,
        $self->_limit,
        $self->_batch_size,
        $self->_query_options,
        $self->_read_preference,
    );
}

#--------------------------------------------------------------------------#
# methods that modify the query
#--------------------------------------------------------------------------#

#pod =head1 QUERY MODIFIERS
#pod
#pod These methods modify the query to be run.  An exception will be thrown if
#pod they are called after results are iterated.
#pod
#pod =head2 immortal
#pod
#pod     $cursor->immortal(1);
#pod
#pod Ordinarily, a cursor "dies" on the database server after a certain length of
#pod time (approximately 10 minutes), to prevent inactive cursors from hogging
#pod resources.  This option sets that a cursor should not die until all of its
#pod results have been fetched or it goes out of scope in Perl.
#pod
#pod Boolean value, defaults to 0.
#pod
#pod C<immortal> is not equivalent to setting a client-side timeout.  If you are
#pod getting client-side timeouts (e.g., "recv timed out"), set C<query_timeout> on
#pod your connection.
#pod
#pod     # wait forever for a query to return results
#pod     $connection->query_timeout(-1);
#pod
#pod See L<MongoDB::MongoClient/query_timeout>.
#pod
#pod =cut

sub immortal {
    my ( $self, $bool ) = @_;
    confess "cannot set immortal after querying"
        if $self->started_iterating;

    $self->_query_options->{immortal} = !!$bool;
    return $self;
}

#pod =head2 fields (\%f)
#pod
#pod     $coll->insert({name => "Fred", age => 20});
#pod     my $cursor = $coll->query->fields({ name => 1 });
#pod     my $obj = $cursor->next;
#pod     $obj->{name}; "Fred"
#pod     $obj->{age}; # undef
#pod
#pod Selects which fields are returned.
#pod The default is all fields.  _id is always returned.
#pod
#pod =cut

sub fields {
    my ($self, $f) = @_;
    confess "cannot set fields after querying"
	if $self->started_iterating;
    confess 'not a hash reference'
	    unless ref $f eq 'HASH' || ref $f eq 'Tie::IxHash';

    $self->_fields($f);
    return $self;
}

#pod =head2 sort ($order)
#pod
#pod     # sort by name, descending
#pod     my $sort = {"name" => -1};
#pod     $cursor = $coll->query->sort($sort);
#pod
#pod Adds a sort to the query.  Argument is either
#pod a hash reference or a Tie::IxHash.
#pod Returns this cursor for chaining operations.
#pod
#pod =cut

sub sort {
    my ($self, $order) = @_;
    confess "cannot set sort after querying"
	if $self->started_iterating;
    confess 'not a hash reference'
	    unless ref $order eq 'HASH' || ref $order eq 'Tie::IxHash';

    $self->_query->set_modifier('$orderby', $order);
    return $self;
}


#pod =head2 limit ($num)
#pod
#pod     $per_page = 20;
#pod     $cursor = $coll->query->limit($per_page);
#pod
#pod Returns a maximum of N results.
#pod Returns this cursor for chaining operations.
#pod
#pod =cut

sub limit {
    my ($self, $num) = @_;
    confess "cannot set limit after querying"
	if $self->started_iterating;
    $self->_limit($num);
    return $self;
}


#pod =head2 max_time_ms( $millis )
#pod
#pod     $cursor = $coll->query->max_time_ms( 500 );
#pod
#pod Causes the server to abort the operation if the specified time in 
#pod milliseconds is exceeded. 
#pod
#pod =cut

sub max_time_ms { 
    my ( $self, $num ) = @_;
    $num = 0 unless defined $num;
    confess "max_time_ms must be non-negative"
      if $num < 0;
    confess "can not set max_time_ms after querying"
      if $self->started_iterating;

    $self->_query->set_modifier( '$maxTimeMS', $num );
    return $self;

}

#pod =head2 tailable ($bool)
#pod
#pod     $cursor->query->tailable(1);
#pod
#pod If a cursor should be tailable.  Tailable cursors can only be used on capped
#pod collections and are similar to the C<tail -f> command: they never die and keep
#pod returning new results as more is added to a collection.
#pod
#pod They are often used for getting log messages.
#pod
#pod Boolean value, defaults to 0.
#pod
#pod Returns this cursor for chaining operations.
#pod
#pod =cut

sub tailable {
    my ( $self, $bool ) = @_;
    confess "cannot set tailable after querying"
        if $self->started_iterating;

    $self->_query_options->{tailable} = !!$bool;
    return $self;
}



#pod =head2 skip ($num)
#pod
#pod     $page_num = 7;
#pod     $per_page = 100;
#pod     $cursor = $coll->query->limit($per_page)->skip($page_num * $per_page);
#pod
#pod Skips the first N results. Returns this cursor for chaining operations.
#pod
#pod See also core documentation on limit: L<http://dochub.mongodb.org/core/limit>.
#pod
#pod =cut

sub skip {
    my ($self, $num) = @_;
    confess "cannot set skip after querying"
	if $self->started_iterating;

    $self->_skip($num);
    return $self;
}

#pod =head2 snapshot
#pod
#pod     my $cursor = $coll->query->snapshot;
#pod
#pod Uses snapshot mode for the query.  Snapshot mode assures no
#pod duplicates are returned, or objects missed, which were present
#pod at both the start and end of the query's execution (if an object
#pod is new during the query, or deleted during the query, it may or
#pod may not be returned, even with snapshot mode).  Note that short
#pod query responses (less than 1MB) are always effectively
#pod snapshotted.  Currently, snapshot mode may not be used with
#pod sorting or explicit hints.
#pod
#pod =cut

sub snapshot {
    my ($self) = @_;
    confess "cannot set snapshot after querying"
	if $self->started_iterating;

    $self->_query->set_modifier('$snapshot', 1);
    return $self;
}

#pod =head2 hint
#pod
#pod     my $cursor = $coll->query->hint({'x' => 1});
#pod     my $cursor = $coll->query->hint(['x', 1]);
#pod     my $cursor = $coll->query->hint('x_1');
#pod
#pod Force Mongo to use a specific index for a query.
#pod
#pod =cut

sub hint {
    my ($self, $index) = @_;
    confess "cannot set hint after querying"
        if $self->started_iterating;

    # $index must either be a string or a reference to an array, hash, or IxHash
    if (ref $index eq 'ARRAY') {

        $index = Tie::IxHash->new(@$index);

    } elsif (ref $index && !(ref $index eq 'HASH' || ref $index eq 'Tie::IxHash')) {

        confess 'not a hash reference';
    }

    $self->_query->set_modifier('$hint', $index);
    return $self;
}

#pod =head2 partial
#pod
#pod     $cursor->partial(1);
#pod
#pod If a shard is down, mongos will return an error when it tries to query that
#pod shard.  If this is set, mongos will just skip that shard, instead.
#pod
#pod Boolean value, defaults to 0.
#pod
#pod =cut

sub partial {
    my ($self, $value) = @_;
    $self->_query_options->{partial} = !! $value;

    # XXX returning self is an API change but more consistent with other cursor methods
    return $self;
}

#pod =head2 read_preference
#pod
#pod     my $cursor = $coll->find()->read_preference($read_preference_object);
#pod     my $cursor = $coll->find()->read_preference('secondary', [{foo => 'bar'}]);
#pod
#pod Sets read preference for the cursor's connection.
#pod
#pod If given a single argument that is a L<MongoDB::ReadPreference> object, the
#pod read preference is set to that object.  Otherwise, it takes positional
#pod arguments: the read preference mode and a tag set list, which must be a valid
#pod mode and tag set list as described in the L<MongoDB::ReadPreference>
#pod documentation.
#pod
#pod Returns $self so that this method can be chained.
#pod
#pod =cut

sub read_preference {
    my $self = shift;

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

    return $self;
}

#pod =head2 slave_okay
#pod
#pod     $cursor->slave_okay(1);
#pod
#pod If a query can be done on a slave database server.
#pod
#pod Boolean value, defaults to 0.
#pod
#pod Returns the cursor object
#pod
#pod =cut

sub slave_okay {
    my ($self, $value) = @_;
    $self->_query_options->{slave_ok} = !! $value;

    # XXX returning self is an API change but more consistent with other cursor methods
    return $self;
}

#pod =head1 QUERY INTROSPECTION AND RESET
#pod
#pod These methods run introspection methods on the query conditions and modifiers
#pod stored within the cursor object.
#pod
#pod =head2 explain
#pod
#pod     my $explanation = $cursor->explain;
#pod
#pod This will tell you the type of cursor used, the number of records the DB had to
#pod examine as part of this query, the number of records returned by the query, and
#pod the time in milliseconds the query took to execute.  Requires L<boolean> package.
#pod
#pod C<explain> resets the cursor, so calling C<next> or C<has_next> after an explain
#pod will requery the database.
#pod
#pod See also core documentation on explain:
#pod L<http://dochub.mongodb.org/core/explain>.
#pod
#pod =cut

sub explain {
    my ($self) = @_;
    my $temp = $self->_limit;
    if ($self->_limit > 0) {
        $self->_limit($self->_limit * -1);
    }

    my $old_query = $self->_query;
    my $new_query = $old_query->clone;
    $new_query->set_modifier('$explain', boolean::true);

    $self->_set_query( $new_query  );

    my $retval = $self->reset->next;

    $self->_set_query( $old_query );
    $self->reset->limit($temp);

    return $retval;
}

#pod =head2 count($all?)
#pod
#pod     my $num = $cursor->count;
#pod     my $num = $cursor->skip(20)->count(1);
#pod
#pod Returns the number of document this query will return.  Optionally takes a
#pod boolean parameter, indicating that the cursor's limit and skip fields should be
#pod used in calculating the count.
#pod
#pod =cut

sub count {
    my ($self, $all) = @_;
    # XXX deprecate this unintuitive API?

    my ($db, $coll) = $self->_ns =~ m/^([^\.]+)\.(.*)/;
    my $cmd = new Tie::IxHash(count => $coll);

    $cmd->Push(query => $self->_query->query_doc);

    if ($all) {
        $cmd->Push(limit => $self->_limit) if $self->_limit;
        $cmd->Push(skip => $self->_skip) if $self->_skip;
    }

    if (my $hint = $self->_query->get_modifier('$hint')) {
        $cmd->Push(hint => $hint);
    }

    my $result = try {
        $self->_client->get_database($db)->_try_run_command($cmd);
    }
    catch {
        # if there was an error, check if it was the "ns missing" one that means the
        # collection hasn't been created or a real error.
        die $_ unless /^ns missing/;
    };

    return $result ? $result->{n} : 0;
}


#pod =head1 QUERY ITERATION
#pod
#pod These methods allow you to iterate over results.
#pod
#pod =head2 result
#pod
#pod     my $result = $cursor->result;
#pod
#pod This method will return a L<MongoDB::QueryResult> object with the result of the
#pod query.  The query will be executed on demand.
#pod
#pod Iterating with a MongoDB::QueryResult object directly instead of a
#pod MongoDB::Cursor will be slightly faster, since the MongoDB::Cursor methods
#pod below just internally call the corresponding method on the result object.
#pod
#pod =cut

#--------------------------------------------------------------------------#
# methods delgated to result object
#--------------------------------------------------------------------------#

#pod =head2 has_next
#pod
#pod     while ($cursor->has_next) {
#pod         ...
#pod     }
#pod
#pod Checks if there is another result to fetch.  Will automatically fetch more
#pod data from the server if necessary.
#pod
#pod =cut

sub has_next { $_[0]->result->has_next }

#pod =head2 next
#pod
#pod     while (my $object = $cursor->next) {
#pod         ...
#pod     }
#pod
#pod Returns the next object in the cursor. Will automatically fetch more data from
#pod the server if necessary. Returns undef if no more data is available.
#pod
#pod =cut

sub next { $_[0]->result->next }

#pod =head2 all
#pod
#pod     my @objects = $cursor->all;
#pod
#pod Returns a list of all objects in the result.
#pod
#pod =cut

sub all { $_[0]->result->all }

#pod =head2 reset
#pod
#pod Resets the cursor.  After being reset, pre-query methods can be
#pod called on the cursor (sort, limit, etc.) and subsequent calls to
#pod next, has_next, or all will re-query the database.
#pod
#pod =cut

sub reset {
    my ($self) = @_;
    $self->_clear_result;
    return $self;
}

#pod =head2 info
#pod
#pod Returns a hash of information about this cursor.  This is intended for
#pod debugging purposes and users should not rely on the contents of this method for
#pod production use.  Currently the fields are:
#pod
#pod =for :list
#pod * C<cursor_id>  -- the server-side id for this cursor as.  This is an opaque string.
#pod   A C<cursor_id> of "\0\0\0\0\0\0\0\0" means there are no more results on the server.
#pod * C<num> -- the number of results received from the server so far
#pod * C<at> -- the (zero-based) index of the document that will be returned next from L</next>
#pod * C<flag> -- if the database could not find the cursor or another error occurred, C<flag> may
#pod   contain a hash reference of flags set in the response (depending on the error).  See
#pod   L<http://www.mongodb.org/display/DOCS/Mongo+Wire+Protocol#MongoWireProtocol-OPREPLY>
#pod   for a full list of flag values.
#pod * C<start> -- the index of the result that the current batch of results starts at.
#pod
#pod If the cursor has not yet executed, only the C<num> field will be returned with
#pod a value of 0.
#pod
#pod =cut

sub info {
    my $self = shift;
    if ( $self->started_iterating ) {
        return $self->result->info;
    }
    else {
        return { num => 0 };
    }
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

MongoDB::Cursor - A lazy cursor for Mongo query results

=head1 VERSION

version v0.999.998.1

=head1 SYNOPSIS

    while (my $object = $cursor->next) {
        ...
    }

    my @objects = $cursor->all;

=head2 Multithreading

Cursors are cloned in threads, but not reset.  Iterating the same cursor from
multiple threads will give unpredictable results.  Only iterate from a single
thread.

=head1 NAME

MongoDB::Cursor - A cursor/iterator for Mongo query results

=head1 SEE ALSO

Core documentation on cursors: L<http://dochub.mongodb.org/core/cursors>.

=head1 STATIC ATTRIBUTES

=head2 slave_okay

    $MongoDB::Cursor::slave_okay = 1;

Whether it is okay to run queries on the slave.  Defaults to 0.

=head2 timeout

B<Deprecated, use MongoDB::MongoClient::query_timeout instead.>

How many milliseconds to wait for a response from the server.  Set to 30000
(30 seconds) by default.  -1 waits forever (or until TCP times out, which is
usually a long time).

This value is overridden by C<MongoDB::MongoClient::query_timeout> and never
used.

=head1 ATTRIBUTES

=head2 started_iterating

If this cursor has queried the database yet. Methods
modifying the query will complain if they are called
after the database is queried.

=head1 QUERY MODIFIERS

These methods modify the query to be run.  An exception will be thrown if
they are called after results are iterated.

=head2 immortal

    $cursor->immortal(1);

Ordinarily, a cursor "dies" on the database server after a certain length of
time (approximately 10 minutes), to prevent inactive cursors from hogging
resources.  This option sets that a cursor should not die until all of its
results have been fetched or it goes out of scope in Perl.

Boolean value, defaults to 0.

C<immortal> is not equivalent to setting a client-side timeout.  If you are
getting client-side timeouts (e.g., "recv timed out"), set C<query_timeout> on
your connection.

    # wait forever for a query to return results
    $connection->query_timeout(-1);

See L<MongoDB::MongoClient/query_timeout>.

=head2 fields (\%f)

    $coll->insert({name => "Fred", age => 20});
    my $cursor = $coll->query->fields({ name => 1 });
    my $obj = $cursor->next;
    $obj->{name}; "Fred"
    $obj->{age}; # undef

Selects which fields are returned.
The default is all fields.  _id is always returned.

=head2 sort ($order)

    # sort by name, descending
    my $sort = {"name" => -1};
    $cursor = $coll->query->sort($sort);

Adds a sort to the query.  Argument is either
a hash reference or a Tie::IxHash.
Returns this cursor for chaining operations.

=head2 limit ($num)

    $per_page = 20;
    $cursor = $coll->query->limit($per_page);

Returns a maximum of N results.
Returns this cursor for chaining operations.

=head2 max_time_ms( $millis )

    $cursor = $coll->query->max_time_ms( 500 );

Causes the server to abort the operation if the specified time in 
milliseconds is exceeded. 

=head2 tailable ($bool)

    $cursor->query->tailable(1);

If a cursor should be tailable.  Tailable cursors can only be used on capped
collections and are similar to the C<tail -f> command: they never die and keep
returning new results as more is added to a collection.

They are often used for getting log messages.

Boolean value, defaults to 0.

Returns this cursor for chaining operations.

=head2 skip ($num)

    $page_num = 7;
    $per_page = 100;
    $cursor = $coll->query->limit($per_page)->skip($page_num * $per_page);

Skips the first N results. Returns this cursor for chaining operations.

See also core documentation on limit: L<http://dochub.mongodb.org/core/limit>.

=head2 snapshot

    my $cursor = $coll->query->snapshot;

Uses snapshot mode for the query.  Snapshot mode assures no
duplicates are returned, or objects missed, which were present
at both the start and end of the query's execution (if an object
is new during the query, or deleted during the query, it may or
may not be returned, even with snapshot mode).  Note that short
query responses (less than 1MB) are always effectively
snapshotted.  Currently, snapshot mode may not be used with
sorting or explicit hints.

=head2 hint

    my $cursor = $coll->query->hint({'x' => 1});
    my $cursor = $coll->query->hint(['x', 1]);
    my $cursor = $coll->query->hint('x_1');

Force Mongo to use a specific index for a query.

=head2 partial

    $cursor->partial(1);

If a shard is down, mongos will return an error when it tries to query that
shard.  If this is set, mongos will just skip that shard, instead.

Boolean value, defaults to 0.

=head2 read_preference

    my $cursor = $coll->find()->read_preference($read_preference_object);
    my $cursor = $coll->find()->read_preference('secondary', [{foo => 'bar'}]);

Sets read preference for the cursor's connection.

If given a single argument that is a L<MongoDB::ReadPreference> object, the
read preference is set to that object.  Otherwise, it takes positional
arguments: the read preference mode and a tag set list, which must be a valid
mode and tag set list as described in the L<MongoDB::ReadPreference>
documentation.

Returns $self so that this method can be chained.

=head2 slave_okay

    $cursor->slave_okay(1);

If a query can be done on a slave database server.

Boolean value, defaults to 0.

Returns the cursor object

=head1 QUERY INTROSPECTION AND RESET

These methods run introspection methods on the query conditions and modifiers
stored within the cursor object.

=head2 explain

    my $explanation = $cursor->explain;

This will tell you the type of cursor used, the number of records the DB had to
examine as part of this query, the number of records returned by the query, and
the time in milliseconds the query took to execute.  Requires L<boolean> package.

C<explain> resets the cursor, so calling C<next> or C<has_next> after an explain
will requery the database.

See also core documentation on explain:
L<http://dochub.mongodb.org/core/explain>.

=head2 count($all?)

    my $num = $cursor->count;
    my $num = $cursor->skip(20)->count(1);

Returns the number of document this query will return.  Optionally takes a
boolean parameter, indicating that the cursor's limit and skip fields should be
used in calculating the count.

=head1 QUERY ITERATION

These methods allow you to iterate over results.

=head2 result

    my $result = $cursor->result;

This method will return a L<MongoDB::QueryResult> object with the result of the
query.  The query will be executed on demand.

Iterating with a MongoDB::QueryResult object directly instead of a
MongoDB::Cursor will be slightly faster, since the MongoDB::Cursor methods
below just internally call the corresponding method on the result object.

=head2 has_next

    while ($cursor->has_next) {
        ...
    }

Checks if there is another result to fetch.  Will automatically fetch more
data from the server if necessary.

=head2 next

    while (my $object = $cursor->next) {
        ...
    }

Returns the next object in the cursor. Will automatically fetch more data from
the server if necessary. Returns undef if no more data is available.

=head2 all

    my @objects = $cursor->all;

Returns a list of all objects in the result.

=head2 reset

Resets the cursor.  After being reset, pre-query methods can be
called on the cursor (sort, limit, etc.) and subsequent calls to
next, has_next, or all will re-query the database.

=head2 info

Returns a hash of information about this cursor.  This is intended for
debugging purposes and users should not rely on the contents of this method for
production use.  Currently the fields are:

=over 4

=item *

C<cursor_id>  -- the server-side id for this cursor as.  This is an opaque string. A C<cursor_id> of "\0\0\0\0\0\0\0\0" means there are no more results on the server.

=item *

C<num> -- the number of results received from the server so far

=item *

C<at> -- the (zero-based) index of the document that will be returned next from L</next>

=item *

C<flag> -- if the database could not find the cursor or another error occurred, C<flag> may contain a hash reference of flags set in the response (depending on the error).  See L<http://www.mongodb.org/display/DOCS/Mongo+Wire+Protocol#MongoWireProtocol-OPREPLY> for a full list of flag values.

=item *

C<start> -- the index of the result that the current batch of results starts at.

=back

If the cursor has not yet executed, only the C<num> field will be returned with
a value of 0.

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
