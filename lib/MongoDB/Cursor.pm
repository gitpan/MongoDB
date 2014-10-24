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

package MongoDB::Cursor;
our $VERSION = '0.24';

# ABSTRACT: A cursor/iterator for Mongo query results
use Data::Dumper;
use Any::Moose;
use boolean;

=head1 NAME

MongoDB::Cursor - A cursor/iterator for Mongo query results

=head1 VERSION

version 0.24

=head1 SYNOPSIS

    while (my $object = $cursor->next) {
        ...
    }

    my @objects = $cursor->all;


=head1 STATIC ATTRIBUTES

=head2 slave_okay

    $MongoDB::Cursor::slave_okay = 1;

Whether it is okay to run queries on the slave.  Defaults to 0.

=cut

$MongoDB::Cursor::slave_okay = 0;

=head1 ATTRIBUTES

=head2 started_iterating

If this cursor has queried the database yet. Methods
mofifying the query will complain if they are called
after the database is queried.

=cut

has started_iterating => (
    is => 'rw',
    isa => 'Bool',
    required => 1,
    default => 0,
);

has _connection => (
    is => 'ro',
    isa => 'MongoDB::Connection',
    required => 1,
);

has _ns => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

has _query => (
    is => 'rw',
    isa => 'HashRef',
    required => 1,
);

has _fields => (
    is => 'rw',
    isa => 'HashRef',
    required => 0,
);

has _limit => (
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


=head1 METHODS

=head2 fields (\%f)

    $coll->insert({name => "Fred", age => 20});
    my $cursor = $coll->query->fields({ name => 1 });
    my $obj = $cursor->next;
    $obj->{name}; "Fred"
    $obj->{age}; # undef

Selects which fields are returned. 
The default is all fields.  _id is always returned.

=cut

sub fields {
    my ($self, $f) = @_;
    confess "cannot set fields after querying"
	if $self->started_iterating;
    confess 'not a hash reference' 
	unless ref $f eq 'HASH';

    $self->_fields($f);
    return $self;
}

=head2 sort (\%order)

    # sort by name, descending
    my $sort = {"name" => -1};
    $cursor = $coll->query->sort($sort);

Adds a sort to the query.
Returns this cursor for chaining operations.

=cut

sub sort {
    my ($self, $order) = @_;
    confess "cannot set sort after querying"
	if $self->started_iterating;
    confess 'not a hash reference' 
	unless ref $order eq 'HASH';

    $self->_query->{'orderby'} = $order;
    return $self;
}


=head2 limit ($num)

    $per_page = 20;
    $cursor = $coll->query->limit($per_page);

Returns a maximum of N results.
Returns this cursor for chaining operations.

=cut

sub limit {
    my ($self, $num) = @_;
    confess "cannot set limit after querying"
	if $self->started_iterating;

    $self->_limit($num);
    return $self;
}

=head2 skip ($num)

    $page_num = 7;
    $per_page = 100;
    $cursor = $coll->query->limit($per_page)->skip($page_num * $per_page);

Skips the first N results.
Returns this cursor for chaining operations.

=cut

sub skip {
    my ($self, $num) = @_;
    confess "cannot set skip after querying"
	if $self->started_iterating;

    $self->_skip($num);
    return $self;
}

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

=cut

sub snapshot {
    my ($self) = @_;
    confess "cannot set snapshot after querying"
	if $self->started_iterating;

    $self->_query->{'$snapshot'} = 1;
    return $self;
}

=head2 hint

    my $cursor = $coll->query->hint({'x' => 1});

Force Mongo to use a specific index for a query.

=cut

sub hint {
    my ($self, $index) = @_;
    confess "cannot set hint after querying"
	if $self->started_iterating;
    confess 'not a hash reference' 
	unless ref $index eq 'HASH';

    $self->_query->{'$hint'} = $index;
    return $self;
}

=head2 explain

    my $explanation = $cursor->explain;

This will tell you the type of cursor used, the number of records 
the DB had to examine as part of this query, the number of records 
returned by the query, and the time in milliseconds the query took 
to execute.  Requires C<boolean> package.

=cut

sub explain {
    my ($self) = @_;
    my $temp = $self->_limit;
    if ($self->_limit > 0) {
        $self->_limit($self->_limit * -1);
    }

    $self->_query->{'$explain'} = boolean::true;

    my $retval = $self->reset->next;
    $self->reset->limit($temp);

    return $retval;
}

=head2 count

    my $num = $cursor->count;

Returns the number of document this query will return.

=cut

sub count {
    my ($self) = @_;

    my ($db, $coll) = $self->_ns =~ m/^([^\.]+).(.*)/;
    my $cmd = {'count' => $coll};
    $cmd->{'query'} = $self->_query->{'query'}
        if exists $self->_query->{'query'};
    $cmd->{'fields'} = $self->_fields 
	if $self->_fields;

    my $result = $self->_connection->get_database($db)->run_command($cmd);

    # returns "ns missing" if collection doesn't exist
    return 0 unless ref $result eq 'HASH';

    if ($self->_limit && $result->{'n'} > $self->_limit) {
	return $self->_limit;
    }

    return $result->{'n'};
}

=head2 reset

Resets the cursor.  After being reset, pre-query methods can be
called on the cursor (sort, limit, etc.) and subsequent calls to
next, has_next, or all will re-query the database.


=head2 has_next

    while ($cursor->has_next) {
        ...
    }

Checks if there is another result to fetch.


=head2 next

    while (my $object = $cursor->next) {
        ...
    }

Returns the next object in the cursor. Will automatically fetch more data from
the server if necessary. Returns undef if no more data is available.


=head2 all

    my @objects = $cursor->all;

Returns a list of all objects in the result.

=cut

sub all {
    my ($self) = @_;
    my @ret;

    while (my $entry = $self->next) {
        push @ret, $entry;
    }

    return @ret;
}

no Any::Moose;
__PACKAGE__->meta->make_immutable;

1;

=head1 AUTHOR

  Kristina Chodorow <kristina@mongodb.org>
