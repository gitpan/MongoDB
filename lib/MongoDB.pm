use strict;
use warnings;

package MongoDB;
# ABSTRACT: A Mongo Driver for Perl


our $VERSION = '0.01';

use XSLoader;
use MongoDB::Connection;

XSLoader::load(__PACKAGE__, $VERSION);

1;

__END__
=head1 NAME

MongoDB - A Mongo Driver for Perl

=head1 VERSION

version 0.01

=head1 SYNOPSIS

    use MongoDB;

    my $connection = MongoDB::Connection->new(host => 'localhost, port => 27017);
    my $database   = $connection->get_database('foo');
    my $collection = $database->get_collection('bar');
    my $id         = $collection->insert({ some => 'data' });
    my $data       = $collection->find_one({ _id => $id });

=head1 AUTHOR

  Florian Ragwitz <rafl@debian.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2009 by 10Gen.

This is free software, licensed under:

  The Apache License, Version 2.0, January 2004

