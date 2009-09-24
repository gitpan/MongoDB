use strict;
use warnings;
use Carp;
use Devel::Peek;
use Data::Dumper;
use Tie::IxHash;

use MongoDB;
require MongoDB::GridFS::File;

my $conn = MongoDB::Connection->new;
my $db = $conn->get_database('foo');
my $c = $db->get_collection('bar');

my $keys = tie(my %idx, 'Tie::IxHash');
%idx = ('sn' => 'ascending', 'ts' => 'descending');
$c->ensure_index($keys);

#MongoDB::GridFS::File->new({_grid => $grid, meta => {}});
