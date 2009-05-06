package MongoDB::OID;
our $VERSION = '0.01';

# ABSTRACT: A Mongo Object ID

use Any::Moose;


has value => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    builder => '_build_value',
);

no Any::Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__
=head1 NAME

MongoDB::OID - A Mongo Object ID

=head1 VERSION

version 0.01

=head1 ATTRIBUTES

=head2 value

The OID value. A random value will be generated if none exists already.

=head1 AUTHOR

  Florian Ragwitz <rafl@debian.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2009 by 10Gen.

This is free software, licensed under:

  The Apache License, Version 2.0, January 2004

