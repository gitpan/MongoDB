use strict;
use warnings;
use Carp;
use Devel::Peek;
use Data::Dumper;
use Tie::IxHash;
use DateTime;

use MongoDB;
require MongoDB::GridFS::File;

my $conn = MongoDB::Connection->new;
my $db = $conn->get_database('foo');
my $c = $db->get_collection('bar');

#my $date = main::DateTime->from_epoch("epoch" => 1234567890);
my $x = $c->find_one();
print $x->{'x'}->epoch();

