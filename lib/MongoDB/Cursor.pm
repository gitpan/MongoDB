package MongoDB::Cursor;
our $VERSION = '0.01';

# ABSTRACT: A cursor/iterator for Mongo query results

use Any::Moose;


has _oid_class => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
    default  => 'MongoDB::OID',
);


sub next {
    my ($self) = @_;
    return unless $self->_more;
    return $self->_next;
}


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

__END__
=head1 NAME

MongoDB::Cursor - A cursor/iterator for Mongo query results

=head1 VERSION

version 0.01

=head1 SYNOPSIS

    while (my $object = $cursor->next) {
        ...
    }

    my @objects = $cursor->all;



=head1 METHODS

=head2 next

    while (my $object = $cursor->next) {
        ...
    }

Returns the next object in the cursor. Will automatically fetch more data from
the server if necessary. Returns undef if no more data is available.



=head2 all

    my @objects = $cursor->all;

Returns a list of all objects in the result.

=head1 AUTHOR

  Florian Ragwitz <rafl@debian.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2009 by 10Gen.

This is free software, licensed under:

  The Apache License, Version 2.0, January 2004

