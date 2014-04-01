package MongoDB::BSON::Regexp;
# ABSTRACT: Regular expression type

use version;
our $VERSION = 'v0.703.3'; # TRIAL

use Moose;

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


1;

__END__

=pod

=head1 NAME

MongoDB::BSON::Regexp - Regular expression type

=head1 VERSION

version v0.703.3

=head1 AUTHORS

=over 4

=item *

Florian Ragwitz <rafl@debian.org>

=item *

Kristina Chodorow <kristina@mongodb.org>

=item *

Mike Friedman <friedo@mongodb.com>

=item *

David Golden <david.golden@mongodb.org>

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2014 by MongoDB, Inc..

This is free software, licensed under:

  The Apache License, Version 2.0, January 2004

=cut
