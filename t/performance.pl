use strict;
use warnings;
use Time::HiRes qw(gettimeofday tv_interval);

use MongoDB;

use constant PER_TRIAL => 5000;
use constant BATCH_SIZE => 100;


my $small = {};
my $medium = {"integer" => 5,
              "number" => 5.05,
              "boolean" => 0,
              "array" => ["test", "benchmark"]};
my $large = {"base_url" => "http://www.example.com/test-me",
             "total_word_count" => 6743,
             "access_time" => time(),
             "meta_tags" => {"description" => "i am a long description string",
                             "author" => "Holly Man",
                             "dynamically_created_meta_tag" => "who know\n what"},
             "page_structure" => {"counted_tags" => 3450,
                                  "no_of_js_attached" => 10,
                                  "no_of_images" => 6},
             "harvested_words" => ["10gen","web","open","source","application","paas",
                                   "platform-as-a-service","technology","helps",
                                   "developers","focus","building","mongodb","mongo",
                                   "10gen","web","open","source","application","paas",
                                   "platform-as-a-service","technology","helps",
                                   "developers","focus","building","mongodb","mongo",
                                   "10gen","web","open","source","application","paas",
                                   "platform-as-a-service","technology","helps",
                                   "developers","focus","building","mongodb","mongo",
                                   "10gen","web","open","source","application","paas",
                                   "platform-as-a-service","technology","helps",
                                   "developers","focus","building","mongodb","mongo",
                                   "10gen","web","open","source","application","paas",
                                   "platform-as-a-service","technology","helps",
                                   "developers","focus","building","mongodb","mongo",
                                   "10gen","web","open","source","application","paas",
                                   "platform-as-a-service","technology","helps",
                                   "developers","focus","building","mongodb","mongo",
                                   "10gen","web","open","source","application","paas",
                                   "platform-as-a-service","technology","helps",
                                   "developers","focus","building","mongodb","mongo",
                                   "10gen","web","open","source","application","paas",
                                   "platform-as-a-service","technology","helps",
                                   "developers","focus","building","mongodb","mongo",
                                   "10gen","web","open","source","application","paas",
                                   "platform-as-a-service","technology","helps",
                                   "developers","focus","building","mongodb","mongo",
                                   "10gen","web","open","source","application","paas",
                                   "platform-as-a-service","technology","helps",
                                   "developers","focus","building","mongodb","mongo",
                                   "10gen","web","open","source","application","paas",
                                   "platform-as-a-service","technology","helps",
                                   "developers","focus","building","mongodb","mongo",
                                   "10gen","web","open","source","application","paas",
                                   "platform-as-a-service","technology","helps",
                                   "developers","focus","building","mongodb","mongo",
                                   "10gen","web","open","source","application","paas",
                                   "platform-as-a-service","technology","helps",
                                   "developers","focus","building","mongodb","mongo",
                                   "10gen","web","open","source","application","paas",
                                   "platform-as-a-service","technology","helps",
                                   "developers","focus","building","mongodb","mongo",
                                   "10gen","web","open","source","application","paas",
                                   "platform-as-a-service","technology","helps",
                                   "developers","focus","building","mongodb","mongo",
                                   "10gen","web","open","source","application","paas",
                                   "platform-as-a-service","technology","helps",
                                   "developers","focus","building","mongodb","mongo",
                                   "10gen","web","open","source","application","paas",
                                   "platform-as-a-service","technology","helps",
                                   "developers","focus","building","mongodb","mongo",
                                   "10gen","web","open","source","application","paas",
                                   "platform-as-a-service","technology","helps",
                                   "developers","focus","building","mongodb","mongo",
                                   "10gen","web","open","source","application","paas",
                                   "platform-as-a-service","technology","helps",
                                   "developers","focus","building","mongodb","mongo",
                                   "10gen","web","open","source","application","paas",
                                   "platform-as-a-service","technology","helps",
                                   "developers","focus","building","mongodb","mongo"]};


sub get_obj {
    my($name) = @_;
    if ($name eq "small") {
        $small;
    } elsif ($name eq "medium") {
        $medium; 
    } else {
        $large;
    }
}

sub coll_setup {
    my($name, $idx) = @_;

    my $coll = $db->get_collection($name . ($idx ? "_i" : ""));

    $coll->drop;
    if ($idx) {
        $coll->ensure_index({x => 'ascending'});
    }
    $coll->find_one;

    $coll;
}

sub insert {
    my($name, $idx) = @_;

    my $coll = coll_setup($coll, $idx);

    my $obj = get_obj($coll->name);

    my $t0 = [gettimeofday];

    for (my $count = 0; $count < PER_TRIAL; $count++) {
        $obj->{'x'} = $count;
        $coll->insert($obj);
    }

    my $total = tv_interval($t0);

    print "insert (" . $coll->name . ", " . ($idx ? "indexed" : "no index") . "): " . (PER_TRIAL/$total) . "\n";
}

sub finsert {
    my($coll, $idx) = @_;

    my $coll = coll_setup($coll, $idx);

    my $obj = get_obj($coll->name);

    my $t0 = [gettimeofday];

    for (my $count = 0; $count < PER_TRIAL; $count++) {
        $obj->{'x'} = $count;
        $coll->insert($obj);
    }
    $coll->find_one;

    my $total = tv_interval($t0);

    print "insert (" . $coll->name . ", " . ($idx ? "indexed" : "no index") . ") findOne: " . (PER_TRIAL/$total) . "\n";
}

my $conn = MongoDB::Connection->new;
my $db = $conn->get_database('perf');

my @colls = (, $db->get_collection('medium'), $db->get_collection('large'));

foreach my $coll (@colls) {
    insert($coll, 0);
#    finsert($coll, 0);
    find_one($coll, 0);

    insert($coll, 1);
#    finsert($coll, 1);

}

