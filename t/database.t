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


use strict;
use warnings;
use Test::More;
use Test::Exception;
use Test::Warn;

use MongoDB::Timestamp; # needed if db is being run as master

use MongoDB;

use lib "t/lib";
use MongoDBTest '$conn', '$testdb';

# get_database
{
    isa_ok($conn, 'MongoDB::MongoClient');

    my $db = $conn->get_database($testdb->name);
    $db->drop;

    isa_ok($db, 'MongoDB::Database');

    $testdb->drop;
}

# collection_names
{
    is(scalar $testdb->collection_names, 0, 'no collections');
    my $coll = $testdb->get_collection('test');
    is($coll->count, 0, 'collection is empty');

    is($coll->find_one, undef, 'nothing for find_one');

    my $id = $coll->insert({ just => 'another', perl => 'hacker' });

    is(scalar $testdb->collection_names, 2, 'test and system.indexes');
    ok((grep { $_ eq 'test' } $testdb->collection_names), 'collection_names');
    is($coll->count, 1, 'count');
    is($coll->find_one->{perl}, 'hacker', 'find_one');
    is($coll->find_one->{_id}->value, $id->value, 'insert id');
}

# non-existent command
{
    my $result = $testdb->run_command({ foo => 'bar' });
    ok ($result =~ /no such cmd/, "run non-existent command: $result");
}

# getlasterror
SKIP: {
    my $admin = $conn->get_database('admin');
    my $buildinfo = $admin->run_command({buildinfo => 1});

    #skip "MongoDB 1.5+ needed", 1 if $buildinfo->{version} =~ /(0\.\d+\.\d+)|(1\.[1234]\d*.\d+)/;
    #my $result = $testdb->last_error({w => 20, wtimeout => 1});
    #is($result, 'timed out waiting for slaves', 'last error timeout');

    skip "MongoDB 1.5+ needed", 2 if $buildinfo->{version} =~ /(0\.\d+\.\d+)|(1\.[1234]\d*.\d+)/;

    my $result = $testdb->last_error({fsync => 1});
    is($result->{ok}, 1);
    is($result->{err}, undef);

    $result = $testdb->last_error;
    is($result->{ok}, 1, 'last_error1');
    is($result->{n}, 0, 'last_error2');
    is($result->{err}, undef, 'last_error3');
}

# reseterror 
{
    my $result = $testdb->run_command({reseterror => 1});
    is($result->{ok}, 1, 'reset error');
}

# forceerror
{
    $testdb->run_command({forceerror => 1});

    my $result = $testdb->last_error;
    is($result->{ok}, 1, 'last_error1');
    is($result->{n}, 0, 'last_error2');
    is($result->{err}, 'forced error', 'last_error3');
}

# eval
{
    my $hello = $testdb->eval('function(x) { return "hello, "+x; }', ["world"]);
    is('hello, world', $hello, 'db eval');

    my $err = $testdb->eval('function(x) { xreturn "hello, "+x; }', ["world"]);
    like( $err, qr/SyntaxError/, 'js err');
}

# tie
{
    my $admin = $conn->get_database('admin');
    my %cmd;
    tie( %cmd, 'Tie::IxHash', buildinfo => 1);
    my $result = $admin->run_command(\%cmd);
    is($result->{ok}, 1);
}

done_testing;
