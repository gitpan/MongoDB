use strict;
use warnings;
use Test::More;
use Test::Exception;

use MongoDB;

my $conn;
eval {
    my $host = "localhost";
    if (exists $ENV{MONGOD}) {
        $host = $ENV{MONGOD};
    }
    $conn = MongoDB::Connection->new(host => $host);
};

if ($@) {
    plan skip_all => $@;
}
else {
    plan tests => 14;
}

isa_ok($conn, 'MongoDB::Connection');

my $db = $conn->get_database('test_database');
$db->drop;

isa_ok($db, 'MongoDB::Database');

$db->drop;

is(scalar $db->collection_names, 0, 'no collections');
my $coll = $db->get_collection('test');
is($coll->count, 0, 'collection is empty');

is($coll->find_one, undef, 'nothing for find_one');

my $id = $coll->insert({ just => 'another', perl => 'hacker' });

is(scalar $db->collection_names, 3, 'test, system.indexes, and test.$_id_');
ok((grep { $_ eq 'test' } $db->collection_names), 'collection_names');
is($coll->count, 1, 'count');
is($coll->find_one->{perl}, 'hacker', 'find_one');
is($coll->find_one->{_id}->value, $id->value, 'insert id');

is($db->run_command({ foo => 'bar' }), "no such cmd");

# getlasterror
SKIP: {
    my $admin = $conn->get_database('admin');
    my $buildinfo = $admin->run_command({buildinfo => 1});
    skip "MongoDB 1.5+ needed", 3 if $buildinfo->{version} =~ /(0\.\d+\.\d+)|(1\.[1234]\d*.\d+)/;

    my $result = $db->last_error({w => 20, wtimeout => 1});
    is($result, 'timed out waiting for slaves', 'last error timeout');

    $result = $db->last_error({fsync => 1});
    is($result->{ok}, 1);
    is($result->{err}, undef);
}
