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

package MongoDB::_URI;

use version;
our $VERSION = 'v0.999.998.1'; # TRIAL

use Moose;
use MongoDB::_Types;
use namespace::clean -except => 'meta';

my $uri_re = MongoDB::_Types::connection_uri_re();

has uri => (
    is => 'ro',
    isa => 'ConnectionStr',
    required => 1,
);

has username => (
    is => 'ro',
    isa => 'Str',
    writer => '_set_username',
    default => '',
);

has password => (
    is => 'ro',
    isa => 'Str',
    writer => '_set_password',
    default => '',
);

has db_name => (
    is => 'ro',
    isa => 'Str',
    writer => '_set_db_name',
    default => '',
);

has options => (
    is => 'ro',
    isa => 'HashRef',
    writer => '_set_options',
    default => sub { {} },
);

has hostpairs => (
    is => 'ro',
    isa => 'ArrayRef',
    writer => '_set_hostpairs',
    default => sub { [] },
);

sub _unescape_all {
    my $str = shift;
    return '' unless defined $str;
    $str =~ s/%([0-9a-f]{2})/chr(hex($1))/ieg;
    return $str;
}

sub _parse_tag_set {
    my ($string) = @_;
    my $set = {};
    for my $tag ( split /,/, $string ) {
        if ( $tag =~ /\S/ ) {
            my @kv = map { s{^\s*}{}; s{\s*$}{}; $_ } split /:/, $tag, 2;
            confess "readPreferenceTagSet '$tag' is not a key:value pair"
              unless @kv == 2;
            $set->{$kv[0]} = $kv[1];
        }
    }
    return $set;
}

sub BUILD {
    my ($self) = @_;

    my $uri = $self->uri;
    my %result;

    if ($uri =~ m{^$uri_re$}) {

        ($result{username}, $result{password}, $result{hostpairs}, $result{db_name}, $result{options}) = ($1, $2, $3, $4, $5);

        # Decode components
        for my $subcomponent ( qw/username password db_name/ ) {
            $result{$subcomponent} = _unescape_all($result{$subcomponent}) unless !(defined $result{$subcomponent});
        }

        $result{hostpairs} = 'localhost' unless $result{hostpairs};
        $result{hostpairs} = [
            map { lc $_ }
            map { @_ = split ':', $_; _unescape_all($_[0]).":"._unescape_all($_[1]) }
            map { $_ .= ':27017' unless $_ =~ /:/ ; $_ } split ',', $result{hostpairs}
        ];

        if ( defined $result{options} ) {
            my %parsed;
            for my $opt ( split '&', $result{options} ) {
                my @kv = split '=', $opt;
                push @kv, '' if @kv == 1;
                confess 'expected key value pair' unless @kv == 2;
                my ($k, $v) = map { _unescape_all($_) } @kv;
                if ( $k eq 'readPreferenceTags' ) {
                    $parsed{$k} ||= [];
                    push @{$parsed{$k}}, _parse_tag_set($v);
                }
                else {
                    $parsed{$k} = $v;
                }
            }
            $result{options} = \%parsed;
        }

        delete $result{username} unless defined $result{username} && length $result{username};
        delete $result{password} unless defined $result{password}; # can be empty string
        delete $result{db_name} unless defined $result{db_name} && length $result{db_name};
    }
    else {
        confess "URI '$uri' could not be parsed";
    }

    for my $attr ( qw/username password db_name options hostpairs/ ) {
        my $setter = "_set_$attr";
        $self->$setter( $result{$attr} ) if defined $result{$attr};
    }

    return;
}

use overload
    '""' => sub { $_[0]->uri },
    'fallback' => 1;

__PACKAGE__->meta->make_immutable;

1;

# vim: ts=4 sts=4 sw=4 et:
