#
#  Copyright 2014 MongoDB, Inc.
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

package MongoDB::CommandResult;

# ABSTRACT: MongoDB generic command result document

use version;
our $VERSION = 'v0.999.998.1'; # TRIAL

use Moose;
use MongoDB::Error;
use namespace::clean -except => 'meta';

with 'MongoDB::Role::_LastError';

#pod =attr result
#pod
#pod Hash reference with the result of a database command
#pod
#pod =cut

has result => (
    is       => 'ro',
    isa      => 'HashRef',
    required => 1,
);

#pod =attr address
#pod
#pod Address ("host:port") of server that ran the command
#pod
#pod =cut

has address => (
    is       => 'ro',
    isa      => 'HostAddress',
    required => 1,
);

#pod =method last_errmsg
#pod
#pod Error string (if any) or the empty string if there was no error.
#pod
#pod =cut

sub last_errmsg {
    my ($self) = @_;
    for my $err_key (qw/$err err errmsg/) {
        return $self->result->{$err_key} if exists $self->result->{$err_key};
    }
    return "";
}

sub assert {
    my ($self) = @_;
    if ( ! $self->result->{ok} ) {
        my $err = $self->last_errmsg;
        my $code = $self->result->{code};
        my $error_class;

        # XXX should we be detecting write/writeConcern/etc errors here?
        if ( $err =~ /^(?:not master|node is recovering)/ ) {
            $error_class = "MongoDB::NotMasterError";
        }
        else {
            $error_class = "MongoDB::DatabaseError";
        }

        $error_class->throw(
            result => $self,
            ( length($err)   ? ( message => $err )  : () ),
            ( defined($code) ? ( code    => $code ) : () ),
        );
    }
    return 1;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

MongoDB::CommandResult - MongoDB generic command result document

=head1 VERSION

version v0.999.998.1

=head1 DESCRIPTION

This class encapsulates the results from a database command.  Currently, it is only
available from the C<result> attribute of C<MongoDB::DatabaseError>.

=head1 ATTRIBUTES

=head2 result

Hash reference with the result of a database command

=head2 address

Address ("host:port") of server that ran the command

=head1 METHODS

=head2 last_errmsg

Error string (if any) or the empty string if there was no error.

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
