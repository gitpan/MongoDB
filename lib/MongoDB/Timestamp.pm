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

package MongoDB::Timestamp;


# ABSTRACT: Replication timestamp

use version;
our $VERSION = 'v0.704.0.0';

#pod =head1 NAME
#pod
#pod MongoDB::Timestamp - Timestamp used for replication
#pod
#pod =head1 SYNOPSIS
#pod
#pod This is an internal type used for replication.  It is not for storing dates,
#pod times, or timestamps in the traditional sense.  Unless you are looking to mess
#pod with MongoDB's replication internals, the class you are probably looking for is
#pod L<DateTime>.  See <MongoDB::DataTypes> for more information.
#pod
#pod =cut

use Moose;
use namespace::clean -except => 'meta';

#pod =head1 ATTRIBUTES
#pod
#pod =head2 sec
#pod
#pod Seconds since epoch.
#pod
#pod =cut

has sec => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

#pod =head2 inc
#pod
#pod Incrementing field.
#pod
#pod =cut

has inc => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

MongoDB::Timestamp - Replication timestamp

=head1 VERSION

version v0.704.0.0

=head1 SYNOPSIS

This is an internal type used for replication.  It is not for storing dates,
times, or timestamps in the traditional sense.  Unless you are looking to mess
with MongoDB's replication internals, the class you are probably looking for is
L<DateTime>.  See <MongoDB::DataTypes> for more information.

=head1 NAME

MongoDB::Timestamp - Timestamp used for replication

=head1 ATTRIBUTES

=head2 sec

Seconds since epoch.

=head2 inc

Incrementing field.

=head1 AUTHORS

=over 4

=item *

David Golden <david.golden@mongodb.org>

=item *

Mike Friedman <friedo@mongodb.com>

=item *

Kristina Chodorow <kristina@mongodb.org>

=item *

Florian Ragwitz <rafl@debian.org>

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2014 by MongoDB, Inc..

This is free software, licensed under:

  The Apache License, Version 2.0, January 2004

=cut
