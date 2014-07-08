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

package MongoDB::BSON;


# ABSTRACT: Tools for serializing and deserializing data in BSON form

use version;
our $VERSION = 'v0.704.2.0';

use Moose;
use MongoDB;
use namespace::clean -except => 'meta';

#pod =head1 NAME
#pod
#pod MongoDB::BSON - Encoding and decoding utilities (more to come)
#pod
#pod =head1 ATTRIBUTES
#pod
#pod =head2 C<looks_like_number>
#pod
#pod     $MongoDB::BSON::looks_like_number = 1;
#pod     $collection->insert({age => "4"}); # stores 4 as an int
#pod
#pod If this is set, the driver will be more aggressive about converting strings into
#pod numbers.  Anything that L<Scalar::Util>'s looks_like_number would approve as a
#pod number will be sent to MongoDB as its numeric value.
#pod
#pod Defaults to 0 (for backwards compatibility).
#pod
#pod If you do not set this, you may be using strings more often than you intend to.
#pod See the L<MongoDB::DataTypes> section for more info on the behavior of strings
#pod vs. numbers.
#pod
#pod =cut

$MongoDB::BSON::looks_like_number = 0;

#pod =head2 char
#pod
#pod     $MongoDB::BSON::char = ":";
#pod     $collection->query({"x" => {":gt" => 4}});
#pod
#pod Can be used to set a character other than "$" to use for special operators.
#pod
#pod =cut

$MongoDB::BSON::char = '$';

#pod =head2 Turn on/off UTF8 flag when return strings
#pod
#pod     # turn off utf8 flag on strings
#pod     $MongoDB::BSON::utf8_flag_on = 0;
#pod
#pod Default is turn on, that compatible with version before 0.34.
#pod
#pod If set to 0, will turn of utf8 flag on string attribute and return on bytes mode, meant same as :
#pod
#pod     utf8::encode($str)
#pod
#pod Currently MongoDB return string with utf8 flag, on character mode , some people
#pod wish to turn off utf8 flag and return string on byte mode, it maybe help to display "pretty" strings.
#pod
#pod NOTE:
#pod
#pod If you turn off utf8 flag, the string  length will compute as bytes, and is_utf8 will return false.
#pod
#pod =cut

$MongoDB::BSON::utf8_flag_on = 1;

#pod =head2 Return boolean values as booleans instead of integers
#pod
#pod     $MongoDB::BSON::use_boolean = 1
#pod
#pod By default, booleans are deserialized as integers.  If you would like them to be
#pod deserialized as L<boolean/true> and L<boolean/false>, set
#pod C<$MongoDB::BSON::use_boolean> to 1.
#pod
#pod =cut

$MongoDB::BSON::use_boolean = 0;

#pod =head2 Return binary data as instances of L<MongoDB::BSON::Binary> instead of
#pod string refs.
#pod
#pod     $MongoDB::BSON::use_binary = 1
#pod
#pod For backwards compatibility, binary data is deserialized as a string ref.  If
#pod you would like to have it deserialized as instances of L<MongoDB::BSON::Binary>
#pod (to, say, preserve the subtype), set C<$MongoDB::BSON::use_binary> to 1.
#pod
#pod =cut

$MongoDB::BSON::use_binary = 0;

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

MongoDB::BSON - Tools for serializing and deserializing data in BSON form

=head1 VERSION

version v0.704.2.0

=head1 NAME

MongoDB::BSON - Encoding and decoding utilities (more to come)

=head1 ATTRIBUTES

=head2 C<looks_like_number>

    $MongoDB::BSON::looks_like_number = 1;
    $collection->insert({age => "4"}); # stores 4 as an int

If this is set, the driver will be more aggressive about converting strings into
numbers.  Anything that L<Scalar::Util>'s looks_like_number would approve as a
number will be sent to MongoDB as its numeric value.

Defaults to 0 (for backwards compatibility).

If you do not set this, you may be using strings more often than you intend to.
See the L<MongoDB::DataTypes> section for more info on the behavior of strings
vs. numbers.

=head2 char

    $MongoDB::BSON::char = ":";
    $collection->query({"x" => {":gt" => 4}});

Can be used to set a character other than "$" to use for special operators.

=head2 Turn on/off UTF8 flag when return strings

    # turn off utf8 flag on strings
    $MongoDB::BSON::utf8_flag_on = 0;

Default is turn on, that compatible with version before 0.34.

If set to 0, will turn of utf8 flag on string attribute and return on bytes mode, meant same as :

    utf8::encode($str)

Currently MongoDB return string with utf8 flag, on character mode , some people
wish to turn off utf8 flag and return string on byte mode, it maybe help to display "pretty" strings.

NOTE:

If you turn off utf8 flag, the string  length will compute as bytes, and is_utf8 will return false.

=head2 Return boolean values as booleans instead of integers

    $MongoDB::BSON::use_boolean = 1

By default, booleans are deserialized as integers.  If you would like them to be
deserialized as L<boolean/true> and L<boolean/false>, set
C<$MongoDB::BSON::use_boolean> to 1.

=head2 Return binary data as instances of L<MongoDB::BSON::Binary> instead of
string refs.

    $MongoDB::BSON::use_binary = 1

For backwards compatibility, binary data is deserialized as a string ref.  If
you would like to have it deserialized as instances of L<MongoDB::BSON::Binary>
(to, say, preserve the subtype), set C<$MongoDB::BSON::use_binary> to 1.

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
