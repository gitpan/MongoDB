package MongoDB::Collection;
our $VERSION = '0.01';

# ABSTRACT: A Mongo Collection

use Any::Moose;

has _database => (
    is       => 'ro',
    isa      => 'MongoDB::Database',
    required => 1,
    handles  => [qw/query find_one insert update remove ensure_index/],
);


has name => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);


has full_name => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    builder => '_build_full_name',
);

sub _build_full_name {
    my ($self) = @_;
    my $name    = $self->name;
    my $db_name = $self->_database->name;
    return "${db_name}.${name}";
}


around qw/query find_one insert update remove ensure_index/ => sub {
    my ($next, $self, @args) = @_;
    return $self->$next($self->_query_ns, @args);
};

sub _query_ns {
    my ($self) = @_;
    return $self->name;
}


sub count {
    my ($self, $query) = @_;
    $query ||= {};

    my $obj;
    eval {
        $obj = $self->_database->run_command({
            count => $self->name,
            query => $query,
        });
    };

    if (my $error = $@) {
        if ($error =~ m/^ns missing/) {
            return 0;
        }
        die $error;
    }

    return $obj->{n};
}


sub validate {
    my ($self, $scan_data) = @_;
    $scan_data = 0 unless defined $scan_data;
    my $obj = $self->_database->run_command({ validate => $self->name });
}


sub drop_indexes {
    my ($self) = @_;
    return $self->drop_index('*');
}


sub drop_index {
    my ($self, $index_name) = @_;
    return $self->_database->run_command([
        deleteIndexes => $self->name,
        index         => $index_name,
    ]);
}


sub get_indexes {
    my ($self) = @_;
    return $self->_database->get_collection('system.indexes')->query({
        ns => $self->full_name,
    })->all;
}


sub drop {
    my ($self) = @_;
    $self->drop_indexes;
    $self->_database->run_command({ drop => $self->name });
    return;
}

no Any::Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__
=head1 NAME

MongoDB::Collection - A Mongo Collection

=head1 VERSION

version 0.01

=head1 ATTRIBUTES

=head2 name

The name of the collection.



=head2 full_name

The full_name of the collection, including the namespace of the database it's
in.



=head1 METHODS

=head2 query ($query)

    my $cursor = $collection->query({ i => { '$gt' => 42 } });

Executes the given C<$query> and returns a C<MongoDB::Cursor> with the results.

=head2 find_one ($query)

    my $object = $collection->find_one({ name => 'Resi' });

Executes the given C<$query> and returns the first object matching it.

=head2 insert ($object)

    my $id = $collection->insert({ name => 'mongo', type => 'database' });

Inserts the given C<$object> into the database and returns its C<MongoDB::OID>.

=head2 update ($update, $upsert?)

    $collection->update($object);

Updates an existing C<$object> in the database.

=head2 remove ($query)

    $collection->remove({ answer => { '$ne' => 42 } });

Removes all objects matching the given C<$query> from the database.

=head2 ensure_index (\@keys, $direction?)

    $collection->ensure_index([qw/foo bar/]);

Makes sure the given C<@keys> of this collection are indexed. The optional
index direction defaults to C<ascending>.



=head2 count ($query)

    my $n_objects = $collection->count({ name => 'Bob' });

Counts the number of objects in this collection that match the given C<$query>.



=head2 validate

    $collection->validate;

Asks the server to validate this collection.



=head2 drop_indexes

    $collection->drop_indexes;

Removes all indexes from this collection.



=head2 drop_index ($index_name)

    $collection->drop_index('foo');

Removes an index called C<$index_name> from this collection.



=head2 get_indexes

    my @indexes = $collection->get_indexes;

Returns a list of all indexes of this collection.



=head2 drop

    $collection->drop;

Deletes a collection as well as all of its indexes.

=head1 AUTHOR

  Florian Ragwitz <rafl@debian.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2009 by 10Gen.

This is free software, licensed under:

  The Apache License, Version 2.0, January 2004

