package MongoDB::BSON::Regexp;
# ABSTRACT: Regular expression type

use version;
our $VERSION = 'v0.999.998.1'; # TRIAL

use Moose;
use namespace::clean -except => 'meta';

has pattern => ( 
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has flags => ( 
    is        => 'ro',
    isa       => 'Str',
    required  => 0,
    predicate => 'has_flags',
    writer    => '_set_flags',
);

my %ALLOWED_FLAGS = ( 
    i   => 1,
    m   => 1,
    x   => 1,
    l   => 1,
    s   => 1,
    u   => 1
);

sub BUILD { 
    my $self = shift;

    if ( $self->has_flags ) { 
        my %seen;
        my @flags = grep { !$seen{$_}++ } split '', $self->flags;
        foreach my $f( @flags ) { 
            die "Regexp flag $f is not supported by MongoDB" if not exists $ALLOWED_FLAGS{$f};
        }

        $self->_set_flags( join '', sort @flags );
    }
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

MongoDB::BSON::Regexp - Regular expression type

=head1 VERSION

version v0.999.998.1

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
