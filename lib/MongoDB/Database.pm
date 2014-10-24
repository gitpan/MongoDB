package MongoDB::Database;
our $VERSION = '0.01';

# ABSTRACT: A Mongo Database

use Any::Moose;

has _connection => (
    is       => 'ro',
    isa      => 'MongoDB::Connection',
    required => 1,
    handles  => [qw/query find_one insert update remove ensure_index/],
);


has name => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has _collection_class => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
    default  => 'MongoDB::Collection',
);

sub BUILD {
    my ($self) = @_;
    Any::Moose::load_class($self->_collection_class);
}

around qw/query find_one insert update remove ensure_index/ => sub {
    my ($next, $self, $ns, @args) = @_;
    return $self->$next($self->_query_ns($ns), @args);
};

sub _query_ns {
    my ($self, $ns) = @_;
    my $name = $self->name;
    return qq{${name}.${ns}};
}


sub collection_names {
    my ($self) = @_;
    my $it = $self->query('system.namespaces', {}, 0, 0);
    return map {
        substr($_, length($self->name) + 1)
    } map { $_->{name} } $it->all;
}


sub get_collection {
    my ($self, $collection_name) = @_;
    return $self->_collection_class->new(
        _database => $self,
        name      => $collection_name,
    );
}


sub drop {
    my ($self) = @_;
    return $self->run_command({ dropDatabase => 1 });
}


sub run_command {
    my ($self, $command) = @_;
    my $obj = $self->find_one('$cmd', $command);
    return $obj if $obj->{ok};
    confess $obj->{errmsg};
}

no Any::Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__
=head1 NAME

MongoDB::Database - A Mongo Database

=head1 VERSION

version 0.01

=head1 ATTRIBUTES

=head2 name

The name of the database.



=head1 METHODS

=head2 collection_names

    my @collections = $database->collection_names;

Returns the list of collections in this database.



=head2 get_collection ($name)

    my $collection = $database->get_collection('foo');

Returns a C<MongoDB::Collection> for the collection called C<$name> within this
database.



=head2 drop

    $database->drop;

Deletes the database.



=head2 run_command ($command)

    my $result = $database->run_command({ some_command => 1 });

Runs a command for this database on the mongo server. Throws an exception with
an error message if the command fails. Returns the result of the command on
success.

=head1 AUTHOR

  Florian Ragwitz <rafl@debian.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2009 by 10Gen.

This is free software, licensed under:

  The Apache License, Version 2.0, January 2004

