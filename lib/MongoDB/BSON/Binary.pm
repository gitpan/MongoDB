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

package MongoDB::BSON::Binary;


# ABSTRACT: Binary type

use version;
our $VERSION = 'v0.999.998.1'; # TRIAL

use Moose;
use namespace::clean -except => 'meta';

#pod =head1 NAME
#pod
#pod MongoDB::BSON::Binary - A type that can be used to send binary data to the
#pod database
#pod
#pod =head1 SYNOPSIS
#pod
#pod Creates an instance of binary data with a specific subtype.
#pod
#pod =head1 EXAMPLE
#pod
#pod For example, suppose we wanted to store a profile pic.
#pod
#pod     my $pic = MongoDB::BSON::Binary->new(data => $pic_bytes);
#pod     $collection->insert({name => "profile pic", pic => $pic});
#pod
#pod You can also, optionally, specify a subtype:
#pod
#pod     my $pic = MongoDB::BSON::Binary->new(data => $pic_bytes,
#pod         subtype => MongoDB::BSON::Binary->SUBTYPE_GENERIC);
#pod     $collection->insert({name => "profile pic", pic => $pic});
#pod
#pod =head1 SUBTYPES
#pod
#pod MongoDB allows you to specify the "flavor" of binary data that you are storing
#pod by providing a subtype.  The subtypes are purely cosmetic: the database treats
#pod them all the same.
#pod
#pod There are several subtypes defined in the BSON spec:
#pod
#pod =over 4
#pod
#pod =item C<SUBTYPE_GENERIC> (0x00) is the default used by the driver (as of 0.46).
#pod
#pod =item C<SUBTYPE_FUNCTION> (0x01) is for compiled byte code.
#pod
#pod =item C<SUBTYPE_GENERIC_DEPRECATED> (0x02) is deprecated. It was used by the
#pod driver prior to version 0.46, but this subtype wastes 4 bytes of space so
#pod C<SUBTYPE_GENERIC> is preferred.  This is the only type that is parsed
#pod differently based on type.
#pod
#pod =item C<SUBTYPE_UUID_DEPRECATED> (0x03) is deprecated.  It is for UUIDs.
#pod
#pod =item C<SUBTYPE_UUID> (0x04) is for UUIDs.
#pod
#pod =item C<SUBTYPE_MD5> can be (0x05) is for MD5 hashes.
#pod
#pod =item C<SUBTYPE_USER_DEFINED> (0x80) is for user-defined binary types.
#pod
#pod =back
#pod
#pod =cut

use constant {
    SUBTYPE_GENERIC            => 0,
    SUBTYPE_FUNCTION           => 1,
    SUBTYPE_GENERIC_DEPRECATED => 2,
    SUBTYPE_UUID_DEPRECATED    => 3,
    SUBTYPE_UUID               => 4,
    SUBTYPE_MD5                => 5,
    SUBTYPE_USER_DEFINED       => 128
};

#pod =head2 data
#pod
#pod A string of binary data.
#pod
#pod =cut

has data => (
    is => 'ro',
    isa => 'Str',
    required => 1
);

#pod =head2 subtype
#pod
#pod A subtype.  Defaults to C<SUBTYPE_GENERIC>.
#pod
#pod =cut

has subtype => (
    is => 'ro',
    isa => 'Int',
    required => 0,
    default => MongoDB::BSON::Binary->SUBTYPE_GENERIC
);

#pod =head2 Why is C<SUBTYPE_GENERIC_DEPRECATED> deprecated?
#pod
#pod Binary data is stored with the length of the binary data, the subtype, and the
#pod actually data.  C<SUBTYPE_GENERIC DEPRECATED> stores the length of the data a
#pod second time, which just wastes four bytes.
#pod
#pod If you have been using C<SUBTYPE_GENERIC_DEPRECATED> for binary data, moving to
#pod C<SUBTYPE_GENERIC> should be painless: just use the driver normally and all
#pod new/resaved data will be stored as C<SUBTYPE_GENERIC>.
#pod
#pod It gets a little trickier if you've been querying by binary data fields:
#pod C<SUBTYPE_GENERIC> won't match C<SUBTYPE_GENERIC_DEPRECATED>, even if the data
#pod itself is the same.
#pod
#pod =head2 Why is C<SUBTYPE_UUID_DEPRECATED> deprecated?
#pod
#pod Other languages were using the UUID type to deserialize into their languages'
#pod native UUID type.  They were doing this in different ways, so to standardize,
#pod they decided on a deserialization format for everyone to use and changed the
#pod subtype for UUID to the universal format.
#pod
#pod This should not affect Perl users at all, as Perl does not deserialize it into
#pod any native UUID type.
#pod
#pod =cut

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

MongoDB::BSON::Binary - Binary type

=head1 VERSION

version v0.999.998.1

=head1 SYNOPSIS

Creates an instance of binary data with a specific subtype.

=head1 NAME

MongoDB::BSON::Binary - A type that can be used to send binary data to the
database

=head1 EXAMPLE

For example, suppose we wanted to store a profile pic.

    my $pic = MongoDB::BSON::Binary->new(data => $pic_bytes);
    $collection->insert({name => "profile pic", pic => $pic});

You can also, optionally, specify a subtype:

    my $pic = MongoDB::BSON::Binary->new(data => $pic_bytes,
        subtype => MongoDB::BSON::Binary->SUBTYPE_GENERIC);
    $collection->insert({name => "profile pic", pic => $pic});

=head1 SUBTYPES

MongoDB allows you to specify the "flavor" of binary data that you are storing
by providing a subtype.  The subtypes are purely cosmetic: the database treats
them all the same.

There are several subtypes defined in the BSON spec:

=over 4

=item C<SUBTYPE_GENERIC> (0x00) is the default used by the driver (as of 0.46).

=item C<SUBTYPE_FUNCTION> (0x01) is for compiled byte code.

=item C<SUBTYPE_GENERIC_DEPRECATED> (0x02) is deprecated. It was used by the
driver prior to version 0.46, but this subtype wastes 4 bytes of space so
C<SUBTYPE_GENERIC> is preferred.  This is the only type that is parsed
differently based on type.

=item C<SUBTYPE_UUID_DEPRECATED> (0x03) is deprecated.  It is for UUIDs.

=item C<SUBTYPE_UUID> (0x04) is for UUIDs.

=item C<SUBTYPE_MD5> can be (0x05) is for MD5 hashes.

=item C<SUBTYPE_USER_DEFINED> (0x80) is for user-defined binary types.

=back

=head2 data

A string of binary data.

=head2 subtype

A subtype.  Defaults to C<SUBTYPE_GENERIC>.

=head2 Why is C<SUBTYPE_GENERIC_DEPRECATED> deprecated?

Binary data is stored with the length of the binary data, the subtype, and the
actually data.  C<SUBTYPE_GENERIC DEPRECATED> stores the length of the data a
second time, which just wastes four bytes.

If you have been using C<SUBTYPE_GENERIC_DEPRECATED> for binary data, moving to
C<SUBTYPE_GENERIC> should be painless: just use the driver normally and all
new/resaved data will be stored as C<SUBTYPE_GENERIC>.

It gets a little trickier if you've been querying by binary data fields:
C<SUBTYPE_GENERIC> won't match C<SUBTYPE_GENERIC_DEPRECATED>, even if the data
itself is the same.

=head2 Why is C<SUBTYPE_UUID_DEPRECATED> deprecated?

Other languages were using the UUID type to deserialize into their languages'
native UUID type.  They were doing this in different ways, so to standardize,
they decided on a deserialization format for everyone to use and changed the
subtype for UUID to the universal format.

This should not affect Perl users at all, as Perl does not deserialize it into
any native UUID type.

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
