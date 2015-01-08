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

use 5.008;
use strict;
use warnings;

package MongoDB;
# ABSTRACT: Official MongoDB Driver for Perl

use version;
our $VERSION = 'v0.999.998.1'; # TRIAL

# regexp_pattern was unavailable before 5.10, had to be exported to load the
# function implementation on 5.10, and was automatically available in 5.10.1
use if ($] eq '5.010000'), 're', 'regexp_pattern';

use Carp ();
use MongoDB::BSON;
use MongoDB::MongoClient;
use MongoDB::Database;
use MongoDB::Collection;
use MongoDB::DBRef;
use MongoDB::OID;
use MongoDB::Timestamp;
use MongoDB::BSON::Binary;
use MongoDB::BSON::Regexp;
use MongoDB::BulkWrite;
use MongoDB::_Link;
use MongoDB::_Protocol;

*read_documents = \&MongoDB::BSON::decode_bson;

# regexp_pattern was unavailable before 5.10, had to be exported to load the
# function implementation on 5.10, and was automatically available in 5.10.1
if ( $] eq '5.010' ) {
    require re;
    re->import('regexp_pattern');
}

sub force_double {
    if ( ref $_[0] ) {
        Carp::croak("Can't force a reference into a double");
    }
    return $_[0] = unpack("d",pack("d", $_[0]));
}

sub force_int {
    if ( ref $_[0] ) {
        Carp::croak("Can't force a reference into an int");
    }
    return $_[0] = int($_[0]);
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

MongoDB - Official MongoDB Driver for Perl

=head1 VERSION

version v0.999.998.1

This is the Alpha 1 release for v1.0.0.0.

=head1 ALPHA RELEASE NOTICE AND ROADMAP

The v0.999.998.x releases are B<alpha> releases towards v1.0.0.0.  While they
are believed be as reliable as the stable release series, the implementation
and API are still subject to change.  While preserving back-compatibility is
important and will be delivered to a great extent, it will not be guaranteed.

Using the v0.999.998.x series means that you understand that your code may break
due to changes in the driver between now and the v1.0.0.0 stable release.

This alpha 1 release includes these major changes:

=over

=item *

All networking code is implemented in pure-Perl.  SSL support is provided by
L<IO::Socket::SSL> (if installed).  Likewise, SASL authentication support is
provided by L<Authen::SASL> backends (if installed).  This should improve
portability and ease installation.

=item *

Server monitoring and failover are significantly improved.

=item *

Expanded use of exceptions for error handling.

=back

More details on changes and how to upgrade applications may be found in
L<MongoDB::Upgrading>.

=head2 Roadmap

Subsequent alphas will be released approximately monthly.  The v1.0.0.0 release
is expected in the middle of 2015.

Some expected (but not guaranteed) changes in future releases include:

=over

=item *

The driver will become pure-Perl capable, using the Moo framework instead of Moose.

=item *

BSON encoding will be extracted to a separate module, with both pure-Perl and C variants available.

=item *

Transformation of Perl data structures to/from BSON will become more customizable.

=item *

An exception-based error system will be used exclusively throughout the driver.

=item *

Some existing options and methods will be deprecated to improve consistency and clarity of what remains.

=item *

Some configuration options and method return values will be implemented with objects for validation and interface consistency.

=item *

Various internal changes to support new protocol capabilities of MongoDB 2.6 and later.

=item *

The driver will have a smaller total dependency tree.

=item *

Documentation will be significantly revised.

=back

=head1 SYNOPSIS

    use MongoDB;

    my $client     = MongoDB::MongoClient->new(host => 'localhost', port => 27017);
    my $database   = $client->get_database( 'foo' );
    my $collection = $database->get_collection( 'bar' );
    my $id         = $collection->insert({ some => 'data' });
    my $data       = $collection->find_one({ _id => $id });

=head1 DESCRIPTION

This is the official Perl driver for MongoDB.  MongoDB is an open-source
document database that provides high performance, high availability, and easy
scalability.

A MongoDB server (or multi-server deployment) hosts a number of databases. A
database holds a set of collections. A collection holds a set of documents. A
document is a set of key-value pairs. Documents have dynamic schema. Dynamic
schema means that documents in the same collection do not need to have the same
set of fields or structure, and common fields in a collection's documents may
hold different types of data.

Here are some resources for learning more about MongoDB:

=over 4

=item *

L<MongoDB Manual|http://docs.mongodb.org/manual/contents/>

=item *

L<MongoDB CRUD Introduction|http://docs.mongodb.org/manual/core/crud-introduction/>

=item *

L<MongoDB Data Modeling Introductions|http://docs.mongodb.org/manual/core/data-modeling-introduction/>

=back

For getting started with the Perl driver, see these pages:

=over 4

=item *

L<MongoDB Perl Driver Tutorial|MongoDB::Tutorial>

=item *

L<MongoDB Perl Driver Examples|MongoDB::Examples>

=back

Extensive documentation and support resources are available via the
L<MongoDB community website|http://www.mongodb.org/>.

=head1 USAGE

The MongoDB driver is organized into a set of classes representing different
levels of abstraction and functionality.

As a user, you first create and configure a L<MongoDB::MongoClient> object to
connect to a MongoDB deployment.  From that client object, you can get
a L<MongoDB::Database> object for interacting with a specific database.

From a database object you can get a L<MongoDB::Collection> object for CRUD
operations on that specific collection, or a L<MongoDB::GridFS> object for
working with an abstract file system hosted on the database.  Each of those
classes may return other objects for specific features or functions.

See the documentation of those classes for more details or the
L<MongoDB Perl Driver Tutorial|MongoDB::Tutorial> for an example.

=head1 SEMANTIC VERSIONING SCHEME

Starting with MongoDB v0.704.0.0, the driver will be using a modified
L<semantic versioning|http://semver.org/> scheme.

Versions will have a C<vX.Y.Z.N> tuple scheme with the following properties:

=over 4

=item *

C<X> will be incremented for incompatible API changes

=item *

C<Y> will be incremented for new functionality that is backwards compatible

=item *

C<Z> will be incremented for backwards-compatible bug fixes

=item *

C<N> will be zero for a stable release; C<N> will be non-zero for development releases

=back

We use C<N> because CPAN does not support pre-release version labels (e.g.
"-alpha1") and requires non-decreasing version numbers for releases.

When C<N> is non-zero, C<X>, C<Y>, and C<Z> have no semantic meaning except to
indicate the last stable release.

For example, v0.704.0.1 is merely the first development release after
v0.704.0.0.  The next stable release could be a bug fix (v0.704.1.0), a feature
enhancement (v0.705.0.0), or an API change (v1.0.0.0).

See the Changes file included with development releases for an indication of
the nature of changes involved.

=for :stopwords cpan testmatrix url annocpan anno bugtracker rt cpants kwalitee diff irc mailto metadata placeholders metacpan

=head1 SUPPORT

=head2 Bugs / Feature Requests

Please report any bugs or feature requests through the issue tracker at L<https://jira.mongodb.org/browse/PERL>.  You will be notified automatically of any progress on your issue.

=head2 Source Code

This is open source software.  The code repository is available for public review and contribution under the terms of the license.
L<https://github.com/mongodb/mongo-perl-driver>

  git clone https://github.com/mongodb/mongo-perl-driver.git

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

=head1 CONTRIBUTORS

=for stopwords Andrew Page Andrey Khozov Ashley Willis Ask Bjørn Hansen Brendan W. McAdams Casey Rojas Christian Sturm Colin Cyr danny David Morrison Nadle Steinbrunner Storch D. Ilmari Mannsåker Eric Daniels Gerard Goossen Graham Barr Jason Carey Toffaletti Johann Rolschewski Joseph Harnish Joshua Juran J. Stewart Kamil Slowikowski Ken Williams mapbuh Matthew Shopsin Michael Langner Rotmanov Mike Dirolf Friedman nightlord nightsailer Nuno Carvalho Orlando Vazquez Othello Maurer Robin Lee Roman Yerin Ronald J Kimball Stephen Oberholtzer Steve Sanbeg Stuart Watt Uwe Voelker Whitney.Jackson

=over 4

=item *

Andrew Page <andrew@infosiftr.com>

=item *

Andrey Khozov <avkhozov@gmail.com>

=item *

Ashley Willis <ashleyw@cpan.org>

=item *

Ask Bjørn Hansen <ask@develooper.com>

=item *

Brendan W. McAdams <brendan@mongodb.com>

=item *

Casey Rojas <casey.j.rojas@gmail.com>

=item *

Christian Sturm <kind@gmx.at>

=item *

Colin Cyr <ccyr@sailingyyc.com>

=item *

danny <danny@paperskymedia.com>

=item *

David Morrison <dmorrison@venda.com>

=item *

David Nadle <david@nadle.com>

=item *

David Steinbrunner <dsteinbrunner@pobox.com>

=item *

David Storch <david.storch@mongodb.com>

=item *

D. Ilmari Mannsåker <ilmari.mannsaker@net-a-porter.com>

=item *

Eric Daniels <eric.daniels@mongodb.com>

=item *

Gerard Goossen <gerard@ggoossen.net>

=item *

Graham Barr <gbarr@pobox.com>

=item *

Jason Carey <jason.carey@mongodb.com>

=item *

Jason Toffaletti <jason@topsy.com>

=item *

Johann Rolschewski <rolschewski@gmail.com>

=item *

Joseph Harnish <bigjoe1008@gmail.com>

=item *

Joshua Juran <jjuran@metamage.com>

=item *

J. Stewart <jstewart@langley.theshire>

=item *

Kamil Slowikowski <kslowikowski@gmail.com>

=item *

Ken Williams <kwilliams@cpan.org>

=item *

mapbuh <n.trupcheff@gmail.com>

=item *

Matthew Shopsin <matt.shopsin@mongodb.com>

=item *

Michael Langner <langner@fch.de>

=item *

Michael Rotmanov <rotmanov@sipgate.de>

=item *

Mike Dirolf <mike@mongodb.com>

=item *

Mike Friedman <mike.friedman@mongodb.com>

=item *

nightlord <zzh_621@yahoo.com>

=item *

nightsailer <nightsailer@gmail.com>

=item *

Nuno Carvalho <mestre.smash@gmail.com>

=item *

Orlando Vazquez <ovazquez@gmail.com>

=item *

Othello Maurer <omaurer@venda.com>

=item *

Robin Lee <cheeselee@fedoraproject.org>

=item *

Roman Yerin <kid@cpan.org>

=item *

Ronald J Kimball <rkimball@pangeamedia.com>

=item *

Stephen Oberholtzer <stevie@qrpff.net>

=item *

Steve Sanbeg <stevesanbeg@buzzfeed.com>

=item *

Stuart Watt <stuart@morungos.com>

=item *

Uwe Voelker <uwe.voelker@xing.com>

=item *

Whitney.Jackson <whjackson@gmail.com>

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2014 by MongoDB, Inc..

This is free software, licensed under:

  The Apache License, Version 2.0, January 2004

=cut
