#
#  Copyright 2009 10gen, Inc.
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

package MongoDB::OID;
our $VERSION = '0.25';
# ABSTRACT: A Mongo Object ID

use Any::Moose;

=head1 NAME

MongoDB::OID - A Mongo Object ID

=head1 VERSION

version 0.25

=head1 SYNOPSIS

If no _id field is provided when a document is inserted into the
database, an _id field will be added with a new MongoDB::OID as
its value.

    my $id = $collection->insert({'name' => 'Alice', age => 20});

C<$id> will be a MongoDB::OID that can be used to retreive or
update the saved document:

    $collection->update({_id => $id}, {'age' => {'$inc' => 1}});
    # now Alice is 21

Warning: at the moment, OID generation is not thread safe.

=head1 ATTRIBUTES

=head2 value

The OID value. A random value will be generated if none exists already.
It is a 24-character hexidecimal string (12 bytes).  

Its string representation is the 24-character string.

=cut

has value => (
    is      => 'ro',
    isa     => 'Str',
    required => 1,
    builder => 'build_value',
);

sub BUILDARGS { 
    my $class = shift; 
    return $class->SUPER::BUILDARGS(flibble => @_)
        if @_ % 2; 
    return $class->SUPER::BUILDARGS(@_); 
}

sub build_value {
    my ($self, $str) = @_;
    $str = '' unless defined $str;

    _build_value($self, $str);
}

sub to_string {
    my ($self) = @_;
    $self->value;
}

use overload
    '""' => \&to_string,
    'fallback' => 1;

no Any::Moose;
__PACKAGE__->meta->make_immutable;

1;

=head1 AUTHOR

  Kristina Chodorow <kristina@mongodb.org>
